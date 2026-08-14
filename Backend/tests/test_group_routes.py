import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.auth import AuthenticatedUser, get_current_user
from app.api.routes import router
from app.db.database import Base, get_db
from app.models import domain
from app.models import schemas


engine = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)


@event.listens_for(engine, "connect")
def enable_sqlite_foreign_keys(dbapi_connection, _connection_record):
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


TestingSession = sessionmaker(autocommit=False, autoflush=False, bind=engine)
USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
MEMORY_1 = "00000000-0000-0000-0000-000000000101"
JPEG_BYTES = b"\xff\xd8\xff\xe0cleave-test-image"


@pytest.fixture()
def db():
    Base.metadata.create_all(bind=engine)
    session = TestingSession()
    try:
        session.add_all(
            [
                domain.Profile(id=USER_1, email="one@example.com", username="one"),
                domain.Profile(id=USER_2, email="two@example.com", username="two"),
                domain.Profile(id=USER_3, email="three@example.com", username="three"),
            ]
        )
        session.commit()
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)


@pytest.fixture()
def app(db):
    test_app = FastAPI()
    test_app.state.limiter = Limiter(key_func=get_remote_address)
    test_app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    test_app.include_router(router, prefix="/api")

    def override_db():
        yield db

    test_app.dependency_overrides[get_db] = override_db
    test_app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_1)
    return test_app


def test_group_creation_uses_server_id_and_returns_members(app):
    client = TestClient(app)
    response = client.post(
        "/api/groups",
        json={
            "name": "Trip",
            "is_collaborative": True,
            "member_ids": [USER_2],
        },
    )

    assert response.status_code == 201
    payload = response.json()
    assert payload["name"] == "Trip"
    assert payload["created_by"] == USER_1
    assert {member["id"] for member in payload["members"]} == {USER_1, USER_2}

    listed = client.get("/api/groups").json()
    assert [group["id"] for group in listed] == [payload["id"]]


def test_capabilities_publish_required_beta_contract(app):
    response = TestClient(app).get("/api/capabilities")

    assert response.status_code == 200
    assert response.json()["api_version"] == 3
    assert {
        "receipt_review",
        "payment_status",
        "profile_settings",
        "scan_idempotency",
        "individual_receipt_claims",
        "receipt_deletion",
        "group_leave",
        "display_names",
        "receipt_currencies",
        "friend_profiles",
    } <= set(
        response.json()["features"]
    )


def test_profile_settings_save_as_one_form(app):
    response = TestClient(app).put(
        "/api/profiles/me/settings",
        json={
            "profile": {
                "username": "new-name",
                "display_name": "New Name",
                "age_band": "18_plus",
                "avatar_visibility": "private",
                "payment_visibility": "everyone",
            },
            "payment_details": {
                "region_code": "AE",
                "venmo_username": "new-venmo",
                "upi_id": "new@bank",
                "aani_id": "+971500000000",
            },
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["username"] == "new-name"
    assert payload["display_name"] == "New Name"
    assert payload["age_band"] == "18_plus"
    assert payload["avatar_visibility"] == "private"
    assert payload["payment_visibility"] == "everyone"
    assert payload["region_code"] == "AE"
    assert payload["venmo_username"] == "new-venmo"
    assert payload["upi_id"] == "new@bank"
    assert payload["aani_id"] == "+971500000000"


def test_collaborative_group_updates_recipient_inbox_and_friends(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Trip", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    inbox = client.get("/api/inbox")
    friends = client.get("/api/friends")

    assert inbox.status_code == 200
    assert inbox.json()[0]["group_id"] == group["id"]
    assert inbox.json()[0]["is_read"] is False
    assert {profile["id"] for profile in friends.json()} == {USER_1}

    marked = client.post(f"/api/inbox/{inbox.json()[0]['id']}/read")
    assert marked.status_code == 200
    assert marked.json()["is_read"] is True


def test_friend_detail_uses_display_name_and_respects_payment_visibility(app, db):
    db.query(domain.Profile).filter(domain.Profile.id == USER_1).update({
        "display_name": "Alex Rivera",
        "region_code": "US",
        "venmo_username": "alex-r",
        "payment_visibility": "shared_groups",
    })
    db.commit()
    client = TestClient(app)
    client.post(
        "/api/groups",
        json={"name": "Friends", "is_collaborative": True, "member_ids": [USER_2]},
    )

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    response = client.get(f"/api/friends/{USER_1}")

    assert response.status_code == 200
    assert response.json()["display_name"] == "Alex Rivera"
    assert response.json()["username"] == "one"
    assert response.json()["venmo_username"] == "alex-r"

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_3)
    assert client.get(f"/api/friends/{USER_1}").status_code == 404


def test_payment_details_are_private_but_available_to_shared_group_members(app, db):
    client = TestClient(app)
    updated = client.patch(
        "/api/profiles/me/payment-details",
        json={
            "region_code": "US",
            "venmo_username": "cleave-one",
            "upi_id": None,
            "aani_id": "one@aani",
        },
    )
    assert updated.status_code == 200
    assert updated.json()["venmo_username"] == "cleave-one"

    search = client.get("/api/profiles", params={"query": "one"})
    assert search.status_code == 200
    assert all("venmo_username" not in profile for profile in search.json())
    assert all("email" not in profile for profile in search.json())

    group = client.post(
        "/api/groups",
        json={"name": "Private payments", "is_collaborative": True, "member_ids": [USER_2]},
    )
    assert group.status_code == 201
    owner = next(member for member in group.json()["members"] if member["id"] == USER_1)
    assert owner["region_code"] == "US"
    assert owner["venmo_username"] == "cleave-one"
    assert owner["aani_id"] == "one@aani"

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_3)
    assert client.get("/api/groups").json() == []


def test_all_payment_handles_can_be_saved_or_cleared_together(app):
    client = TestClient(app)
    saved = client.patch(
        "/api/profiles/me/payment-details",
        json={
            "region_code": "AE",
            "venmo_username": "cleave-one",
            "upi_id": "one@upi",
            "aani_id": "+971501234567",
        },
    )
    assert saved.status_code == 200
    assert saved.json()["venmo_username"] == "cleave-one"
    assert saved.json()["upi_id"] == "one@upi"
    assert saved.json()["aani_id"] == "+971501234567"

    cleared = client.patch(
        "/api/profiles/me/payment-details",
        json={
            "region_code": "AE",
            "venmo_username": None,
            "upi_id": None,
            "aani_id": None,
        },
    )
    assert cleared.status_code == 200
    assert cleared.json()["venmo_username"] is None
    assert cleared.json()["upi_id"] is None
    assert cleared.json()["aani_id"] is None


def test_profile_photo_upload_and_download_are_private(app, monkeypatch):
    client = TestClient(app)
    monkeypatch.setattr(
        "app.api.routes.upload_image_to_gcs",
        lambda _content, _mime_type, folder: f"{folder}/avatar.jpg",
    )
    monkeypatch.setattr(
        "app.api.routes.download_image_from_gcs",
        lambda object_name: (b"avatar-bytes", "image/jpeg") if object_name else None,
    )

    uploaded = client.post(
        "/api/profiles/me/avatar",
        files={"file": ("avatar.jpg", JPEG_BYTES, "image/jpeg")},
    )
    downloaded = client.get(f"/api/profiles/{USER_1}/avatar")

    assert uploaded.status_code == 200
    assert uploaded.json()["avatar_url"] == "avatars/avatar.jpg"
    assert downloaded.status_code == 200
    assert downloaded.content == b"avatar-bytes"


def test_local_group_receipt_parse_does_not_require_remote_group(app, monkeypatch):
    client = TestClient(app)
    monkeypatch.setattr(
        "app.api.routes.parseReceiptImage",
        lambda _content, _mime_type: schemas.ParsedReceipt(
            vendor_name="Local Cafe",
            tax=1,
            tip=0,
            discount=0,
            total=6,
            line_items=[schemas.LineItemBase(description="Coffee", price=5)],
        ),
    )

    response = client.post(
        "/api/receipts/parse",
        files={"file": ("receipt.jpg", JPEG_BYTES, "image/jpeg")},
    )

    assert response.status_code == 200
    assert response.json()["vendor_name"] == "Local Cafe"
    assert response.json()["line_items"][0]["description"] == "Coffee"


def test_receipt_scan_retry_is_idempotent(app, monkeypatch, db):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Reliable scans", "is_collaborative": True, "member_ids": []},
    ).json()
    parse_calls = 0

    def parsed_receipt(_content, _mime_type):
        nonlocal parse_calls
        parse_calls += 1
        return schemas.ParsedReceipt(
            vendor_name="Retry Cafe",
            tax=1,
            tip=0,
            discount=0,
            total=6,
            line_items=[schemas.LineItemBase(description="Coffee", price=5)],
        )

    monkeypatch.setattr("app.api.routes.parseReceiptImage", parsed_receipt)
    monkeypatch.setattr(
        "app.api.routes.upload_image_to_gcs",
        lambda _content, _mime_type: "receipts/retry.jpg",
    )
    request_id = "10000000-0000-0000-0000-000000000001"
    request = {
        "files": {"file": ("receipt.jpg", JPEG_BYTES, "image/jpeg")},
        "headers": {"Idempotency-Key": request_id},
    }

    first = client.post(f"/api/receipts?group_id={group['id']}", **request)
    second = client.post(f"/api/receipts?group_id={group['id']}", **request)

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["id"] == first.json()["id"]
    assert parse_calls == 1
    assert db.query(domain.Receipt).count() == 1


def test_non_member_cannot_read_group_receipts(app):
    client = TestClient(app)
    created = client.post(
        "/api/groups",
        json={"name": "Private", "is_collaborative": False, "member_ids": []},
    ).json()

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_3)
    response = client.get(f"/api/groups/{created['id']}/receipts")

    assert response.status_code == 403


def test_manual_receipt_is_persisted_under_authoritative_group(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Dinner", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()

    receipt_response = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={
            "title": "Cafe",
            "currency_code": "AED",
            "tax_amount": 1.5,
            "tip_amount": 2.0,
            "discount_amount": 0,
            "items": [{"name": "Coffee", "price": 5.0}],
        },
    )

    assert receipt_response.status_code == 200
    receipt = receipt_response.json()
    assert receipt["group_id"] == group["id"]
    assert receipt["currency_code"] == "AED"
    assert receipt["items"][0]["name"] == "Coffee"
    assert client.get(f"/api/groups/{group['id']}/receipts").json()[0]["id"] == receipt["id"]


def test_only_owner_can_add_member(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Owners", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)

    response = client.post(
        f"/api/groups/{group['id']}/members",
        json={"user_id": USER_3},
    )

    assert response.status_code == 403


def test_members_leave_instead_of_deleting_and_owner_transfers(app, db):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Leave safely", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Pending dinner", "items": [{"name": "Burger", "price": 12}]},
    ).json()

    deletion = client.delete(f"/api/groups/{group['id']}")
    assert deletion.status_code == 405
    assert "Leave" in deletion.json()["detail"]

    left = client.post(f"/api/groups/{group['id']}/leave")
    assert left.status_code == 204
    assert client.get("/api/groups").json() == []
    assert db.query(domain.GroupMember).filter_by(
        group_id=group["id"], user_id=USER_1
    ).first() is None
    assert db.query(domain.ReceiptParticipant).filter_by(
        receipt_id=receipt["id"], user_id=USER_1
    ).one().status == "submitted"

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    remaining_group = client.get("/api/groups").json()[0]
    assert remaining_group["created_by"] == USER_2
    renamed = client.patch(
        f"/api/groups/{group['id']}", json={"name": "New owner can rename"}
    )
    assert renamed.status_code == 200


def test_last_member_leaving_closes_unreachable_group(app, db):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Solo", "is_collaborative": True, "member_ids": []},
    ).json()

    response = client.post(f"/api/groups/{group['id']}/leave")

    assert response.status_code == 204
    assert db.query(domain.Group).filter_by(id=group["id"]).first() is None


def test_receipt_edits_and_assignments_are_saved_atomically(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Atomic", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={
            "title": "Original",
            "items": [
                {"name": "Coffee", "price": 5.0},
                {"name": "Cake", "price": 6.0},
            ],
        },
    ).json()

    edited_items = [
        {"id": item["id"], "name": f"Edited {item['name']}", "price": item["price"] + 1}
        for item in receipt["items"]
    ]
    edit_response = client.patch(
        f"/api/receipts/{receipt['id']}",
        json={
            "title": "Edited",
            "tax_amount": 1.0,
            "tip_amount": 2.0,
            "discount_amount": 0.5,
            "items": edited_items,
        },
    )
    assignments_response = client.patch(
        f"/api/receipts/{receipt['id']}/assignments",
        json={
            "items": [
                {"item_id": receipt["items"][0]["id"], "user_ids": [USER_1]},
                {"item_id": receipt["items"][1]["id"], "user_ids": [USER_1, USER_2]},
            ]
        },
    )

    assert edit_response.status_code == 200
    assert edit_response.json()["title"] == "Edited"
    assert edit_response.json()["discount_amount"] == 0.5
    assert assignments_response.status_code == 200
    reopened = client.get(f"/api/groups/{group['id']}/receipts").json()[0]
    assert reopened["items"][0]["assigned_user_ids"] == [USER_1]
    assert set(reopened["items"][1]["assigned_user_ids"]) == {USER_1, USER_2}


def test_scanner_is_receipt_admin_even_when_group_was_created_by_someone_else(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Shared scanners", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    assert group["created_by"] == USER_1

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Scanned by two", "items": [{"name": "Tea", "price": 3}]},
    )

    assert receipt.status_code == 200
    assert receipt.json()["admin_id"] == USER_2


def test_receipt_snapshots_participants_and_members_submit_only_their_own_claims(app, db):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Self claims", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={
            "title": "Dinner",
            "tax_amount": 2,
            "items": [
                {"name": "Shared fries", "price": 8},
                {"name": "Tea", "price": 4},
            ],
        },
    ).json()

    assert {value["user_id"] for value in receipt["participants"]} == {USER_1, USER_2}
    assert {value["status"] for value in receipt["participants"]} == {"pending"}

    admin_claim = client.put(
        f"/api/receipts/{receipt['id']}/claim",
        json={"item_ids": [receipt["items"][0]["id"]]},
    )
    assert admin_claim.status_code == 200
    assert next(
        value for value in admin_claim.json()["receipt"]["participants"] if value["user_id"] == USER_1
    )["status"] == "submitted"

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    member_claim = client.put(
        f"/api/receipts/{receipt['id']}/claim",
        json={"item_ids": [receipt["items"][0]["id"], receipt["items"][1]["id"]]},
    )
    assert member_claim.status_code == 200
    reopened = member_claim.json()["receipt"]
    shared = next(value for value in reopened["items"] if value["name"] == "Shared fries")
    assert set(shared["assigned_user_ids"]) == {USER_1, USER_2}
    balances = {value["user_id"]: value for value in member_claim.json()["balances"]}
    assert balances[USER_1]["items_total"] == 4
    assert balances[USER_2]["items_total"] == 8
    assert balances[USER_1]["items"][0]["name"] == "Shared fries"

    # Resubmitting an empty claim removes only this member's rows and is an
    # explicit completed state, rather than leaving them pending forever.
    empty_claim = client.put(
        f"/api/receipts/{receipt['id']}/claim",
        json={"item_ids": []},
    )
    assert empty_claim.status_code == 200
    assert all(
        USER_2 not in value["assigned_user_ids"]
        for value in empty_claim.json()["receipt"]["items"]
    )
    assert db.query(domain.ReceiptParticipant).filter_by(
        receipt_id=receipt["id"], user_id=USER_2
    ).one().status == "submitted"


def test_payment_waits_for_all_participants_and_all_items_to_be_claimed(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Wait", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Lunch", "items": [{"name": "Meal", "price": 10}]},
    ).json()
    client.put(
        f"/api/receipts/{receipt['id']}/claim",
        json={"item_ids": [receipt["items"][0]["id"]]},
    )
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    blocked = client.put(f"/api/receipts/{receipt['id']}/payment-status")
    assert blocked.status_code == 409
    assert "Everyone" in blocked.json()["detail"]

    client.put(
        f"/api/receipts/{receipt['id']}/claim",
        json={"item_ids": [receipt["items"][0]["id"]]},
    )
    paid = client.put(f"/api/receipts/{receipt['id']}/payment-status")
    assert paid.status_code == 200
    assert paid.json()["amount"] == 5


def test_new_group_member_is_not_silently_added_to_an_existing_receipt(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Snapshot", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Before join", "items": [{"name": "Tea", "price": 3}]},
    ).json()
    client.post(f"/api/groups/{group['id']}/members", json={"user_id": USER_3})
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_3)
    claim = client.put(
        f"/api/receipts/{receipt['id']}/claim",
        json={"item_ids": [receipt["items"][0]["id"]]},
    )
    assert claim.status_code == 403


def test_only_receipt_admin_can_delete_receipt_and_private_images(app, db, monkeypatch):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Delete", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Mistake", "items": [{"name": "Tea", "price": 3}]},
    ).json()
    stored = db.query(domain.Receipt).filter_by(id=receipt["id"]).one()
    stored.image_url = "receipts/source.jpg"
    db.add(domain.ReceiptMemory(
        id=MEMORY_1,
        receipt_id=receipt["id"],
        user_id=USER_1,
        image_url="receipts/memory.jpg",
    ))
    db.commit()
    deleted_objects = []
    monkeypatch.setattr(
        "app.api.routes.delete_images_from_gcs",
        lambda names: deleted_objects.extend(names) or True,
    )

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    assert client.delete(f"/api/receipts/{receipt['id']}").status_code == 403
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_1)
    assert client.delete(f"/api/receipts/{receipt['id']}").status_code == 204
    assert db.query(domain.Receipt).filter_by(id=receipt["id"]).first() is None
    assert set(deleted_objects) == {"receipts/source.jpg", "receipts/memory.jpg"}


def test_non_admin_cannot_edit_receipt_or_allocations(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Admin only", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Original", "items": [{"name": "Tea", "price": 3}]},
    ).json()
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)

    edit = client.patch(
        f"/api/receipts/{receipt['id']}",
        json={
            "title": "Tampered",
            "items": [{"id": receipt["items"][0]["id"], "name": "Tea", "price": 1}],
        },
    )
    allocation = client.patch(
        f"/api/receipts/{receipt['id']}/assignments",
        json={"items": [{"item_id": receipt["items"][0]["id"], "user_ids": [USER_2]}]},
    )

    assert edit.status_code == 403
    assert allocation.status_code == 403


def test_member_marks_calculated_payment_and_admin_confirms_it(app, db):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Payment review", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Dinner", "tax_amount": 2, "items": [{"name": "Meal", "price": 10}]},
    ).json()
    client.put(f"/api/receipts/{receipt['id']}/claim", json={"item_ids": []})

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    client.put(
        f"/api/receipts/{receipt['id']}/claim",
        json={"item_ids": [receipt["items"][0]["id"]]},
    )
    first = client.put(f"/api/receipts/{receipt['id']}/payment-status")
    second = client.put(f"/api/receipts/{receipt['id']}/payment-status")
    member_review = client.get(f"/api/receipts/{receipt['id']}/review")

    assert first.status_code == 200
    assert first.json()["amount"] == 12
    assert first.json()["status"] == "pending"
    assert second.json()["id"] == first.json()["id"]
    assert len(db.query(domain.Settlement).all()) == 1
    assert len(member_review.json()["payments"]) == 1
    assert member_review.json()["viewer_is_admin"] is False

    forbidden = client.patch(
        f"/api/receipts/{receipt['id']}/payments/{first.json()['id']}",
        json={"status": "confirmed"},
    )
    assert forbidden.status_code == 403

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_1)
    confirmed = client.patch(
        f"/api/receipts/{receipt['id']}/payments/{first.json()['id']}",
        json={"status": "confirmed"},
    )
    assert confirmed.status_code == 200
    assert confirmed.json()["status"] == "confirmed"
    assert confirmed.json()["reviewed_by"] == USER_1

    locked_edit = client.patch(
        f"/api/receipts/{receipt['id']}",
        json={
            "title": "Changed after payment",
            "items": [{"id": receipt["items"][0]["id"], "name": "Meal", "price": 9}],
        },
    )
    assert locked_edit.status_code == 409

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    withdrawal = client.delete(f"/api/receipts/{receipt['id']}/payment-status")
    assert withdrawal.status_code == 409


def test_legacy_settlement_endpoint_rejects_spoofed_amount_or_other_payer(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "No spoofing", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Lunch", "items": [{"name": "Meal", "price": 10}]},
    ).json()
    client.patch(
        f"/api/receipts/{receipt['id']}/assignments",
        json={"items": [{"item_id": receipt["items"][0]["id"], "user_ids": [USER_2]}]},
    )
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)

    spoofed = client.post(
        "/api/settlements",
        json={
            "receipt_id": receipt["id"],
            "from_user_id": USER_2,
            "to_user_id": USER_1,
            "amount": 0.01,
        },
    )
    other_payer = client.post(
        "/api/settlements",
        json={
            "receipt_id": receipt["id"],
            "from_user_id": USER_3,
            "to_user_id": USER_1,
            "amount": 10,
        },
    )
    assert spoofed.status_code == 409
    assert other_payer.status_code == 403


def test_admin_changes_reject_pending_mark_and_member_can_resubmit_current_amount(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Allocation changes", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Lunch", "items": [{"name": "Meal", "price": 10}]},
    ).json()
    item_id = receipt["items"][0]["id"]
    client.put(f"/api/receipts/{receipt['id']}/claim", json={"item_ids": []})

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    client.put(
        f"/api/receipts/{receipt['id']}/claim",
        json={"item_ids": [item_id]},
    )
    first = client.put(f"/api/receipts/{receipt['id']}/payment-status")
    assert first.json()["amount"] == 10

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_1)
    changed = client.put(
        f"/api/receipts/{receipt['id']}/review",
        json={
            "receipt": {
                "title": "Lunch",
                "tax_amount": 0,
                "tip_amount": 0,
                "discount_amount": 0,
                "items": [{"id": item_id, "name": "Meal", "price": 15}],
            },
            "assignments": {"items": [{"item_id": item_id, "user_ids": [USER_2]}]},
        },
    )
    assert changed.status_code == 200

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    invalidated = client.get(f"/api/receipts/{receipt['id']}/review")
    assert invalidated.json()["payments"][0]["status"] == "rejected"
    client.put(
        f"/api/receipts/{receipt['id']}/claim",
        json={"item_ids": [item_id]},
    )
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_1)
    client.put(f"/api/receipts/{receipt['id']}/claim", json={"item_ids": []})
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    resubmitted = client.put(f"/api/receipts/{receipt['id']}/payment-status")
    assert resubmitted.json()["amount"] == 15
    assert resubmitted.json()["status"] == "pending"


def test_profile_visibility_controls_shared_handle_and_avatar_access(app, monkeypatch):
    client = TestClient(app)
    monkeypatch.setattr(
        "app.api.routes.upload_image_to_gcs",
        lambda _content, _mime_type, folder: f"{folder}/avatar.jpg",
    )
    monkeypatch.setattr(
        "app.api.routes.download_image_from_gcs",
        lambda _object_name: (b"avatar", "image/jpeg"),
    )
    client.post(
        "/api/profiles/me/avatar",
        files={"file": ("avatar.jpg", JPEG_BYTES, "image/jpeg")},
    )
    client.patch(
        "/api/profiles/me/payment-details",
        json={"region_code": "US", "venmo_username": "hidden-one", "upi_id": None, "aani_id": None},
    )
    privacy = client.patch(
        "/api/profiles/me",
        json={
            "age_band": "18_plus",
            "avatar_visibility": "private",
            "payment_visibility": "private",
        },
    )
    assert privacy.status_code == 200
    assert privacy.json()["age_band"] == "18_plus"

    group = client.post(
        "/api/groups",
        json={"name": "Private profile", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    listed = client.get("/api/groups").json()[0]
    owner = next(member for member in listed["members"] if member["id"] == USER_1)

    assert owner["venmo_username"] is None
    assert client.get(f"/api/profiles/{USER_1}/avatar").status_code == 404

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_1)
    client.patch(
        "/api/profiles/me",
        json={"avatar_visibility": "shared_groups", "payment_visibility": "shared_groups"},
    )
    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    shared = client.get("/api/groups").json()[0]
    shared_owner = next(member for member in shared["members"] if member["id"] == USER_1)
    assert shared_owner["venmo_username"] == "hidden-one"
    assert client.get(f"/api/profiles/{USER_1}/avatar").status_code == 200


def test_batch_assignments_reject_non_group_members(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Private", "is_collaborative": True, "member_ids": []},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Lunch", "items": [{"name": "Soup", "price": 4.0}]},
    ).json()

    response = client.patch(
        f"/api/receipts/{receipt['id']}/assignments",
        json={
            "items": [
                {"item_id": receipt["items"][0]["id"], "user_ids": [USER_3]}
            ]
        },
    )

    assert response.status_code == 400


def test_receipt_experience_is_upserted_per_user(app, db):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Experience", "is_collaborative": False, "member_ids": []},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Cafe", "items": [{"name": "Tea", "price": 3.0}]},
    ).json()

    created = client.put(
        f"/api/receipts/{receipt['id']}/experience",
        json={"rating": 4},
    )
    updated = client.put(
        f"/api/receipts/{receipt['id']}/experience",
        json={"rating": 5},
    )
    fetched = client.get(f"/api/receipts/{receipt['id']}/experience")

    assert created.status_code == 200
    assert updated.json()["rating"] == 5
    assert fetched.status_code == 200
    assert fetched.json()["rating"] == 5
    experiences = db.query(domain.ReceiptExperience).all()
    assert len(experiences) == 1
    assert experiences[0].rating == 5


def test_receipt_experience_is_private_to_current_user(app):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Experience", "is_collaborative": True, "member_ids": [USER_2]},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Cafe", "items": [{"name": "Tea", "price": 3.0}]},
    ).json()
    client.put(f"/api/receipts/{receipt['id']}/experience", json={"rating": 4})

    app.dependency_overrides[get_current_user] = lambda: AuthenticatedUser(id=USER_2)
    response = client.get(f"/api/receipts/{receipt['id']}/experience")

    assert response.status_code == 200
    assert response.json() is None
    group_receipt = client.get(f"/api/groups/{group['id']}/receipts").json()[0]
    assert group_receipt["experiences"] == [
        {
            "rating": 4,
            "receipt_id": receipt["id"],
            "user_id": USER_1,
            "created_at": group_receipt["experiences"][0]["created_at"],
            "updated_at": group_receipt["experiences"][0]["updated_at"],
        }
    ]


def test_bootstrap_uses_onboarding_username_for_trigger_created_profile(app, db):
    client = TestClient(app)

    response = client.post(
        "/api/profiles/bootstrap",
        json={"username": "Chosen Name", "email": "one@example.com"},
    )

    assert response.status_code == 200
    assert response.json()["username"] == "Chosen Name"
    assert db.query(domain.Profile).filter(domain.Profile.id == USER_1).one().username == "Chosen Name"


def test_deleted_profile_cannot_be_recreated_by_stale_token_in_production(app, db, monkeypatch):
    db.query(domain.Profile).filter(domain.Profile.id == USER_1).delete()
    db.commit()
    monkeypatch.setenv("ENVIRONMENT", "production")

    response = TestClient(app).post(
        "/api/profiles/bootstrap",
        json={"username": "Restored", "email": "one@example.com"},
    )

    assert response.status_code == 401
    assert db.query(domain.Profile).filter(domain.Profile.id == USER_1).first() is None


def test_image_upload_rejects_spoofed_content_before_storage(app, monkeypatch):
    upload_called = False

    def upload_should_not_run(*_args, **_kwargs):
        nonlocal upload_called
        upload_called = True
        return "avatars/unsafe.jpg"

    monkeypatch.setattr("app.api.routes.upload_image_to_gcs", upload_should_not_run)
    response = TestClient(app).post(
        "/api/profiles/me/avatar",
        files={"file": ("avatar.jpg", b"<script>alert(1)</script>", "image/jpeg")},
    )

    assert response.status_code == 415
    assert upload_called is False


def test_memory_content_requires_receipt_access_and_streams_private_object(
    app, db, monkeypatch
):
    client = TestClient(app)
    group = client.post(
        "/api/groups",
        json={"name": "Photos", "is_collaborative": False, "member_ids": []},
    ).json()
    receipt = client.post(
        f"/api/groups/{group['id']}/receipts/manual",
        json={"title": "Cafe", "items": [{"name": "Tea", "price": 3.0}]},
    ).json()
    db.add(
        domain.ReceiptMemory(
            id=MEMORY_1,
            receipt_id=receipt["id"],
            user_id=USER_1,
            image_url="receipts/private.jpg",
        )
    )
    db.commit()
    monkeypatch.setattr(
        "app.api.routes.download_image_from_gcs",
        lambda _: (b"private-image", "image/jpeg"),
    )

    response = client.get(
        f"/api/receipts/{receipt['id']}/memories/{MEMORY_1}/content"
    )

    assert response.status_code == 200
    assert response.content == b"private-image"
    assert response.headers["cache-control"] == "private, max-age=300"


def test_account_deletion_removes_profile_after_identity_provider_accepts(
    app, db, monkeypatch
):
    class AcceptedResponse:
        status_code = 204

    monkeypatch.setenv("SUPABASE_URL", "https://project.supabase.co")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", "sb_secret_backend")
    monkeypatch.delenv("SUPABASE_SERVICE_ROLE_KEY", raising=False)
    delete_request = {}

    def accept_delete(*args, **kwargs):
        delete_request["args"] = args
        delete_request["kwargs"] = kwargs
        return AcceptedResponse()

    monkeypatch.setattr(
        "app.api.routes.httpx.delete",
        accept_delete,
    )
    deleted_objects = []
    monkeypatch.setattr(
        "app.api.routes.delete_images_from_gcs",
        lambda names: deleted_objects.extend(names) or True,
    )
    group = domain.Group(
        id="00000000-0000-0000-0000-000000000201",
        name="Owned",
        created_by=USER_1,
    )
    receipt = domain.Receipt(
        id="00000000-0000-0000-0000-000000000202",
        group_id=group.id,
        title="Dinner",
        admin_id=USER_1,
        image_url="receipts/scan.jpg",
    )
    memory = domain.ReceiptMemory(
        id=MEMORY_1,
        receipt_id=receipt.id,
        user_id=USER_1,
        image_url="receipts/memory.jpg",
    )
    group_id = group.id
    db.add_all([group, receipt, memory])
    db.commit()

    response = TestClient(app).delete("/api/profiles/me")

    assert response.status_code == 204
    assert db.query(domain.Profile).filter(domain.Profile.id == USER_1).first() is None
    assert db.query(domain.Group).filter(domain.Group.id == group_id).first() is None
    assert set(deleted_objects) == {"receipts/scan.jpg", "receipts/memory.jpg"}
    assert delete_request["kwargs"]["headers"] == {
        "Authorization": "Bearer sb_secret_backend",
        "apikey": "sb_secret_backend",
    }
