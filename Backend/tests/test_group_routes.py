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
        files={"file": ("avatar.jpg", b"avatar-bytes", "image/jpeg")},
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
        files={"file": ("receipt.jpg", b"receipt-bytes", "image/jpeg")},
    )

    assert response.status_code == 200
    assert response.json()["vendor_name"] == "Local Cafe"
    assert response.json()["line_items"][0]["description"] == "Coffee"


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
            "tax_amount": 1.5,
            "tip_amount": 2.0,
            "discount_amount": 0,
            "items": [{"name": "Coffee", "price": 5.0}],
        },
    )

    assert receipt_response.status_code == 200
    receipt = receipt_response.json()
    assert receipt["group_id"] == group["id"]
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

    assert created.status_code == 200
    assert updated.json()["rating"] == 5
    experiences = db.query(domain.ReceiptExperience).all()
    assert len(experiences) == 1
    assert experiences[0].rating == 5


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
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "service-role-key")
    monkeypatch.setattr(
        "app.api.routes.httpx.delete",
        lambda *args, **kwargs: AcceptedResponse(),
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
