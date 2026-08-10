from __future__ import annotations

import os
import uuid
from io import BytesIO
from typing import List

import httpx
from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from slowapi import Limiter
from slowapi.util import get_remote_address
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload
from starlette.responses import StreamingResponse

from app.api.auth import AuthenticatedUser, get_current_user
from app.db.database import get_db
from app.models import domain, schemas
from app.services.balance_calculator import calculate_balances
from app.services.receipt_parser import parseReceiptImage
from app.services.storage import (
    delete_images_from_gcs,
    download_image_from_gcs,
    upload_image_to_gcs,
)


router = APIRouter()
limiter = Limiter(key_func=get_remote_address)
MAX_RECEIPT_BYTES = 10 * 1024 * 1024
ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/heic", "image/heif"}


def _group_query(db: Session):
    return db.query(domain.Group).options(
        selectinload(domain.Group.members).selectinload(domain.GroupMember.user)
    )


def _serialize_group(group: domain.Group) -> dict:
    return {
        "id": group.id,
        "name": group.name,
        "created_by": group.created_by,
        "is_collaborative": group.is_collaborative,
        "created_at": group.created_at,
        "members": [
            {"id": membership.user.id, "username": membership.user.username}
            for membership in group.members
            if membership.user is not None
        ],
    }


def _membership(db: Session, group_id: str, user_id: str) -> domain.GroupMember | None:
    return (
        db.query(domain.GroupMember)
        .filter(
            domain.GroupMember.group_id == group_id,
            domain.GroupMember.user_id == user_id,
        )
        .first()
    )


def _require_group_access(
    db: Session,
    group_id: str,
    user: AuthenticatedUser,
    *,
    require_owner: bool = False,
) -> domain.Group:
    group = _group_query(db).filter(domain.Group.id == group_id).first()
    if group is None:
        raise HTTPException(status_code=404, detail="Group not found")
    if require_owner:
        if group.created_by != user.id:
            raise HTTPException(status_code=403, detail="Only the group owner can do that")
    elif _membership(db, group_id, user.id) is None:
        raise HTTPException(status_code=403, detail="You are not a member of this group")
    return group


def _require_receipt_access(
    db: Session, receipt_id: str, user: AuthenticatedUser
) -> domain.Receipt:
    receipt = (
        db.query(domain.Receipt)
        .options(
            selectinload(domain.Receipt.items),
            selectinload(domain.Receipt.memories),
        )
        .filter(domain.Receipt.id == receipt_id)
        .first()
    )
    if receipt is None:
        raise HTTPException(status_code=404, detail="Receipt not found")
    _require_group_access(db, receipt.group_id, user)
    return receipt


def _validate_member_ids(db: Session, group_id: str, user_ids: list[str]) -> None:
    if not user_ids:
        return
    valid_count = (
        db.query(domain.GroupMember)
        .filter(
            domain.GroupMember.group_id == group_id,
            domain.GroupMember.user_id.in_(set(user_ids)),
        )
        .count()
    )
    if valid_count != len(set(user_ids)):
        raise HTTPException(status_code=400, detail="Assignments must reference group members")


def _group_image_objects(db: Session, group_id: str) -> list[str]:
    receipt_ids = [
        receipt_id
        for (receipt_id,) in db.query(domain.Receipt.id)
        .filter(domain.Receipt.group_id == group_id)
        .all()
    ]
    receipt_objects = [
        object_name
        for (object_name,) in db.query(domain.Receipt.image_url)
        .filter(
            domain.Receipt.group_id == group_id,
            domain.Receipt.image_url.is_not(None),
        )
        .all()
    ]
    if not receipt_ids:
        return receipt_objects
    memory_objects = [
        object_name
        for (object_name,) in db.query(domain.ReceiptMemory.image_url)
        .filter(domain.ReceiptMemory.receipt_id.in_(receipt_ids))
        .all()
    ]
    return receipt_objects + memory_objects


def _account_image_objects(db: Session, user_id: str) -> list[str]:
    avatar = db.query(domain.Profile.avatar_url).filter(domain.Profile.id == user_id).scalar()
    owned_group_ids = [
        group_id
        for (group_id,) in db.query(domain.Group.id)
        .filter(domain.Group.created_by == user_id)
        .all()
    ]
    deleted_receipt_ids = {
        receipt_id
        for (receipt_id,) in db.query(domain.Receipt.id)
        .filter(
            (domain.Receipt.admin_id == user_id)
            | (domain.Receipt.group_id.in_(owned_group_ids))
        )
        .all()
    }
    receipt_objects = [
        object_name
        for (object_name,) in db.query(domain.Receipt.image_url)
        .filter(
            domain.Receipt.id.in_(deleted_receipt_ids),
            domain.Receipt.image_url.is_not(None),
        )
        .all()
    ]
    memory_filter = domain.ReceiptMemory.user_id == user_id
    if deleted_receipt_ids:
        memory_filter = memory_filter | domain.ReceiptMemory.receipt_id.in_(deleted_receipt_ids)
    memory_objects = [
        object_name
        for (object_name,) in db.query(domain.ReceiptMemory.image_url)
        .filter(memory_filter)
        .all()
    ]
    return receipt_objects + memory_objects + ([avatar] if avatar else [])


@router.post("/profiles/bootstrap", response_model=schemas.Profile)
def bootstrap_profile(
    profile: schemas.ProfileBase,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    existing = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if existing:
        return existing
    if user.email and profile.email.casefold() != user.email.casefold():
        raise HTTPException(status_code=403, detail="Email does not match authenticated user")
    username = profile.username.strip()
    username_taken = (
        db.query(domain.Profile).filter(domain.Profile.username == username).first()
        is not None
    )
    if username_taken:
        username = f"{username[:31]}-{user.id[:8]}"
    created = domain.Profile(
        id=user.id,
        email=user.email or profile.email,
        username=username,
    )
    db.add(created)
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=409, detail="A profile already exists for this account") from error
    db.refresh(created)
    return created


@router.get("/profiles/me", response_model=schemas.Profile)
def get_my_profile(
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    profile = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if profile is None:
        raise HTTPException(status_code=404, detail="Profile not found")
    return profile


@router.patch("/profiles/me", response_model=schemas.Profile)
def update_my_profile(
    payload: schemas.ProfileUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    profile = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if profile is None:
        raise HTTPException(status_code=404, detail="Profile not found")
    existing = (
        db.query(domain.Profile)
        .filter(
            domain.Profile.username == payload.username.strip(),
            domain.Profile.id != user.id,
        )
        .first()
    )
    if existing:
        raise HTTPException(status_code=409, detail="That username is already taken")
    profile.username = payload.username.strip()
    db.commit()
    db.refresh(profile)
    return profile


@router.post("/profiles/me/avatar", response_model=schemas.Profile)
async def update_my_avatar(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    profile = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if profile is None:
        raise HTTPException(status_code=404, detail="Profile not found")
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Choose a JPEG, PNG, or HEIC image")
    image_bytes = await file.read(MAX_RECEIPT_BYTES + 1)
    if not image_bytes:
        raise HTTPException(status_code=400, detail="The profile image is empty")
    if len(image_bytes) > MAX_RECEIPT_BYTES:
        raise HTTPException(status_code=413, detail="The profile image must be under 10 MB")

    old_avatar = profile.avatar_url
    object_name = await run_in_threadpool(
        upload_image_to_gcs,
        image_bytes,
        file.content_type or "image/jpeg",
        folder="avatars",
    )
    if not object_name:
        raise HTTPException(status_code=503, detail="Profile photo storage is temporarily unavailable")
    profile.avatar_url = object_name
    db.commit()
    db.refresh(profile)
    if old_avatar:
        await run_in_threadpool(delete_images_from_gcs, [old_avatar])
    return profile


@router.get("/profiles/{profile_id}/avatar")
def get_profile_avatar(
    profile_id: str,
    db: Session = Depends(get_db),
    _user: AuthenticatedUser = Depends(get_current_user),
):
    profile = db.query(domain.Profile).filter(domain.Profile.id == profile_id).first()
    if profile is None or not profile.avatar_url:
        raise HTTPException(status_code=404, detail="Profile photo not found")
    downloaded = download_image_from_gcs(profile.avatar_url)
    if downloaded is None:
        raise HTTPException(status_code=404, detail="Profile photo not found")
    content, content_type = downloaded
    return StreamingResponse(BytesIO(content), media_type=content_type)


@router.delete("/profiles/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_my_account(
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    service_role_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not supabase_url or not service_role_key:
        raise HTTPException(
            status_code=503,
            detail="Account deletion is temporarily unavailable",
        )

    image_objects = _account_image_objects(db, user.id)

    try:
        response = httpx.delete(
            f"{supabase_url}/auth/v1/admin/users/{user.id}",
            headers={
                "Authorization": f"Bearer {service_role_key}",
                "apikey": service_role_key,
            },
            timeout=10,
        )
    except httpx.HTTPError as error:
        raise HTTPException(status_code=503, detail="Account deletion is temporarily unavailable") from error
    if response.status_code not in {200, 204, 404}:
        raise HTTPException(status_code=502, detail="The identity provider rejected account deletion")

    # Supabase normally cascades auth.users -> profiles. This fallback also
    # supports local/test databases where that trigger does not exist.
    db.expire_all()
    profile = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if profile is not None:
        db.delete(profile)
        db.commit()
    delete_images_from_gcs(image_objects)


@router.get("/profiles", response_model=List[schemas.Profile])
def search_profiles(
    query: str = Query(default="", max_length=40),
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    profiles = db.query(domain.Profile).filter(domain.Profile.id != user.id)
    if query.strip():
        escaped = query.strip().replace("%", r"\%").replace("_", r"\_")
        profiles = profiles.filter(domain.Profile.username.ilike(f"%{escaped}%", escape="\\"))
    return profiles.order_by(domain.Profile.username.asc()).limit(20).all()


@router.get("/friends", response_model=List[schemas.Profile])
def list_friends(
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    shared_group_ids = [
        group_id
        for (group_id,) in db.query(domain.GroupMember.group_id)
        .join(domain.Group, domain.Group.id == domain.GroupMember.group_id)
        .filter(
            domain.GroupMember.user_id == user.id,
            domain.Group.is_collaborative.is_(True),
        )
        .all()
    ]
    if not shared_group_ids:
        return []
    friend_ids = {
        friend_id
        for (friend_id,) in db.query(domain.GroupMember.user_id)
        .filter(
            domain.GroupMember.group_id.in_(shared_group_ids),
            domain.GroupMember.user_id != user.id,
        )
        .all()
    }
    if not friend_ids:
        return []
    return db.query(domain.Profile).filter(domain.Profile.id.in_(friend_ids)).order_by(domain.Profile.username).all()


@router.get("/inbox", response_model=List[schemas.InboxItem])
def get_inbox(
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    return (
        db.query(domain.InboxItem)
        .filter(domain.InboxItem.user_id == user.id)
        .order_by(domain.InboxItem.created_at.desc())
        .limit(100)
        .all()
    )


@router.post("/inbox/{item_id}/read", response_model=schemas.InboxItem)
def mark_inbox_item_read(
    item_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    item = db.query(domain.InboxItem).filter(
        domain.InboxItem.id == item_id,
        domain.InboxItem.user_id == user.id,
    ).first()
    if item is None:
        raise HTTPException(status_code=404, detail="Inbox item not found")
    item.is_read = True
    db.commit()
    db.refresh(item)
    return item


@router.post("/groups", response_model=schemas.Group, status_code=status.HTTP_201_CREATED)
def create_group(
    payload: schemas.GroupCreate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    creator = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if creator is None:
        raise HTTPException(status_code=409, detail="Create your profile before creating a group")

    requested_ids = set(payload.member_ids)
    requested_ids.add(user.id)
    profiles = db.query(domain.Profile).filter(domain.Profile.id.in_(requested_ids)).all()
    if len(profiles) != len(requested_ids):
        raise HTTPException(status_code=400, detail="One or more selected members no longer exist")

    group = domain.Group(
        id=str(uuid.uuid4()),
        name=payload.name.strip(),
        created_by=user.id,
        is_collaborative=payload.is_collaborative,
    )
    db.add(group)
    db.flush()
    db.add_all(
        [domain.GroupMember(group_id=group.id, user_id=profile.id) for profile in profiles]
    )
    if payload.is_collaborative:
        for profile in profiles:
            if profile.id != user.id:
                db.add(domain.InboxItem(
                    id=str(uuid.uuid4()),
                    user_id=profile.id,
                    actor_id=user.id,
                    group_id=group.id,
                    kind="group_added",
                    title=f"You were added to {group.name}",
                    body=f"{creator.username} added you to a collaborative group.",
                ))
    db.commit()
    return _serialize_group(_group_query(db).filter(domain.Group.id == group.id).one())


@router.get("/groups", response_model=List[schemas.Group])
def get_groups(
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    groups = (
        _group_query(db)
        .join(domain.GroupMember)
        .filter(domain.GroupMember.user_id == user.id)
        .order_by(domain.Group.created_at.desc())
        .all()
    )
    return [_serialize_group(group) for group in groups]


@router.patch("/groups/{group_id}", response_model=schemas.Group)
def update_group(
    group_id: str,
    payload: schemas.GroupUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    group = _require_group_access(db, group_id, user, require_owner=True)
    group.name = payload.name.strip()
    db.commit()
    return _serialize_group(_group_query(db).filter(domain.Group.id == group_id).one())


@router.delete("/groups/{group_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_group(
    group_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    group = _require_group_access(db, group_id, user, require_owner=True)
    image_objects = _group_image_objects(db, group_id)
    db.delete(group)
    db.commit()
    delete_images_from_gcs(image_objects)


@router.post("/groups/{group_id}/members", response_model=schemas.Group)
def add_group_member(
    group_id: str,
    payload: schemas.MemberAdd,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_group_access(db, group_id, user, require_owner=True)
    if db.query(domain.Profile).filter(domain.Profile.id == payload.user_id).first() is None:
        raise HTTPException(status_code=404, detail="Profile not found")
    existing = _membership(db, group_id, payload.user_id)
    if existing is None:
        db.add(domain.GroupMember(group_id=group_id, user_id=payload.user_id))
        group = _group_query(db).filter(domain.Group.id == group_id).one()
        actor = db.query(domain.Profile).filter(domain.Profile.id == user.id).one()
        db.add(domain.InboxItem(
            id=str(uuid.uuid4()),
            user_id=payload.user_id,
            actor_id=user.id,
            group_id=group_id,
            kind="group_added",
            title=f"You were added to {group.name}",
            body=f"{actor.username} added you to a collaborative group.",
        ))
        db.commit()
    return _serialize_group(_group_query(db).filter(domain.Group.id == group_id).one())


@router.get("/groups/{group_id}/receipts", response_model=List[schemas.Receipt])
def get_group_receipts(
    group_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_group_access(db, group_id, user)
    return (
        db.query(domain.Receipt)
        .options(
            selectinload(domain.Receipt.items),
            selectinload(domain.Receipt.memories),
        )
        .filter(domain.Receipt.group_id == group_id)
        .order_by(domain.Receipt.created_at.desc())
        .all()
    )


def _create_receipt(
    db: Session,
    *,
    group_id: str,
    user_id: str,
    title: str,
    tax: float,
    tip: float,
    discount: float,
    items: list[schemas.ReceiptItemCreate],
    image_url: str | None = None,
) -> domain.Receipt:
    receipt = domain.Receipt(
        id=str(uuid.uuid4()),
        group_id=group_id,
        title=title,
        admin_id=user_id,
        tax_amount=tax,
        tip_amount=tip,
        discount_amount=discount,
        image_url=image_url,
    )
    db.add(receipt)
    db.flush()
    db.add_all(
        [
            domain.ReceiptItem(
                id=str(uuid.uuid4()),
                receipt_id=receipt.id,
                name=item.name,
                price=item.price,
            )
            for item in items
        ]
    )
    db.commit()
    return (
        db.query(domain.Receipt)
        .options(
            selectinload(domain.Receipt.items),
            selectinload(domain.Receipt.memories),
        )
        .filter(domain.Receipt.id == receipt.id)
        .one()
    )


@router.post("/groups/{group_id}/receipts/manual", response_model=schemas.Receipt)
def create_manual_receipt(
    group_id: str,
    payload: schemas.ManualReceiptCreate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_group_access(db, group_id, user)
    return _create_receipt(
        db,
        group_id=group_id,
        user_id=user.id,
        title=payload.title.strip(),
        tax=payload.tax_amount,
        tip=payload.tip_amount,
        discount=payload.discount_amount,
        items=payload.items,
    )


@router.patch("/receipts/{receipt_id}", response_model=schemas.Receipt)
def update_receipt(
    receipt_id: str,
    payload: schemas.ReceiptUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_access(db, receipt_id, user)
    existing_items = {item.id: item for item in receipt.items}
    requested_ids = [item.id for item in payload.items]
    if len(requested_ids) != len(set(requested_ids)) or set(requested_ids) != set(existing_items):
        raise HTTPException(
            status_code=400,
            detail="Receipt edits must contain every original item exactly once",
        )

    receipt.title = payload.title.strip()
    receipt.tax_amount = payload.tax_amount
    receipt.tip_amount = payload.tip_amount
    receipt.discount_amount = payload.discount_amount
    for item in payload.items:
        existing_items[item.id].name = item.name.strip()
        existing_items[item.id].price = item.price
    db.commit()
    return _require_receipt_access(db, receipt_id, user)


@router.post("/receipts", response_model=schemas.Receipt)
@limiter.limit("5/minute")
async def upload_receipt(
    request: Request,
    group_id: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_group_access(db, group_id, user)
    mime_type = (file.content_type or "").lower()
    if mime_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Upload a JPEG, PNG, HEIC, or HEIF image")

    image_bytes = await file.read(MAX_RECEIPT_BYTES + 1)
    if not image_bytes:
        raise HTTPException(status_code=400, detail="The receipt image is empty")
    if len(image_bytes) > MAX_RECEIPT_BYTES:
        raise HTTPException(status_code=413, detail="Receipt images must be 10 MB or smaller")

    try:
        parsed = await run_in_threadpool(parseReceiptImage, image_bytes, mime_type)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    image_url = await run_in_threadpool(upload_image_to_gcs, image_bytes, mime_type)
    if not image_url:
        raise HTTPException(status_code=503, detail="Receipt image storage is temporarily unavailable")
    items = [
        schemas.ReceiptItemCreate(name=item.description, price=item.price)
        for item in parsed.line_items
    ]
    if not items:
        raise HTTPException(status_code=422, detail="No receipt items were detected")
    return _create_receipt(
        db,
        group_id=group_id,
        user_id=user.id,
        title=parsed.vendor_name,
        tax=parsed.tax,
        tip=parsed.tip,
        discount=parsed.discount,
        items=items,
        image_url=image_url,
    )


@router.post("/receipts/parse", response_model=schemas.ParsedReceipt)
@limiter.limit("5/minute")
async def parse_receipt_without_group(
    request: Request,
    file: UploadFile = File(...),
    _user: AuthenticatedUser = Depends(get_current_user),
):
    mime_type = (file.content_type or "").lower()
    if mime_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Upload a JPEG, PNG, HEIC, or HEIF image")
    image_bytes = await file.read(MAX_RECEIPT_BYTES + 1)
    if not image_bytes:
        raise HTTPException(status_code=400, detail="The receipt image is empty")
    if len(image_bytes) > MAX_RECEIPT_BYTES:
        raise HTTPException(status_code=413, detail="Receipt images must be 10 MB or smaller")
    try:
        return await run_in_threadpool(parseReceiptImage, image_bytes, mime_type)
    except ValueError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error


@router.patch("/receipts/{receipt_id}/items/{item_id}/assignments")
def assign_receipt_item(
    receipt_id: str,
    item_id: str,
    payload: schemas.AssignmentUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_access(db, receipt_id, user)
    item = (
        db.query(domain.ReceiptItem)
        .filter(
            domain.ReceiptItem.id == item_id,
            domain.ReceiptItem.receipt_id == receipt_id,
        )
        .first()
    )
    if item is None:
        raise HTTPException(status_code=404, detail="Receipt item not found")
    _validate_member_ids(db, receipt.group_id, payload.user_ids)

    db.query(domain.ReceiptAssignment).filter(
        domain.ReceiptAssignment.item_id == item_id
    ).delete(synchronize_session=False)
    db.add_all(
        [domain.ReceiptAssignment(item_id=item_id, user_id=user_id) for user_id in set(payload.user_ids)]
    )
    db.commit()
    return {"status": "ok"}


@router.patch("/receipts/{receipt_id}/assignments")
def assign_receipt_items(
    receipt_id: str,
    payload: schemas.AssignmentBatchUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_access(db, receipt_id, user)
    receipt_item_ids = {item.id for item in receipt.items}
    requested_item_ids = [item.item_id for item in payload.items]
    if (
        len(requested_item_ids) != len(set(requested_item_ids))
        or set(requested_item_ids) != receipt_item_ids
    ):
        raise HTTPException(
            status_code=400,
            detail="Assignments must contain every receipt item exactly once",
        )

    all_user_ids = {
        user_id
        for item in payload.items
        for user_id in item.user_ids
    }
    _validate_member_ids(db, receipt.group_id, list(all_user_ids))
    db.query(domain.ReceiptAssignment).filter(
        domain.ReceiptAssignment.item_id.in_(receipt_item_ids)
    ).delete(synchronize_session=False)
    db.add_all(
        domain.ReceiptAssignment(item_id=item.item_id, user_id=user_id)
        for item in payload.items
        for user_id in set(item.user_ids)
    )
    db.commit()
    return {"status": "ok"}


@router.post(
    "/receipts/{receipt_id}/memories",
    response_model=schemas.ReceiptMemory,
    status_code=status.HTTP_201_CREATED,
)
async def upload_receipt_memory(
    receipt_id: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_receipt_access(db, receipt_id, user)
    mime_type = (file.content_type or "").lower()
    if mime_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Upload a JPEG, PNG, HEIC, or HEIF image")
    image_bytes = await file.read(MAX_RECEIPT_BYTES + 1)
    if not image_bytes or len(image_bytes) > MAX_RECEIPT_BYTES:
        raise HTTPException(status_code=413, detail="Memory photos must be between 1 byte and 10 MB")
    url = await run_in_threadpool(upload_image_to_gcs, image_bytes, mime_type)
    if not url:
        raise HTTPException(status_code=503, detail="Photo storage is temporarily unavailable")
    memory = domain.ReceiptMemory(
        id=str(uuid.uuid4()),
        receipt_id=receipt_id,
        user_id=user.id,
        image_url=url,
    )
    db.add(memory)
    db.commit()
    db.refresh(memory)
    return memory


@router.get("/receipts/{receipt_id}/memories/{memory_id}/content")
def get_receipt_memory_content(
    receipt_id: str,
    memory_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_receipt_access(db, receipt_id, user)
    memory = (
        db.query(domain.ReceiptMemory)
        .filter(
            domain.ReceiptMemory.id == memory_id,
            domain.ReceiptMemory.receipt_id == receipt_id,
        )
        .first()
    )
    if memory is None:
        raise HTTPException(status_code=404, detail="Memory not found")
    downloaded = download_image_from_gcs(memory.image_url)
    if downloaded is None:
        raise HTTPException(status_code=503, detail="Photo storage is temporarily unavailable")
    image_bytes, mime_type = downloaded
    return StreamingResponse(
        BytesIO(image_bytes),
        media_type=mime_type,
        headers={"Cache-Control": "private, max-age=300"},
    )


@router.put(
    "/receipts/{receipt_id}/experience",
    response_model=schemas.ReceiptExperience,
)
def save_receipt_experience(
    receipt_id: str,
    payload: schemas.ReceiptExperienceUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_receipt_access(db, receipt_id, user)
    experience = (
        db.query(domain.ReceiptExperience)
        .filter(
            domain.ReceiptExperience.receipt_id == receipt_id,
            domain.ReceiptExperience.user_id == user.id,
        )
        .first()
    )
    if experience is None:
        experience = domain.ReceiptExperience(
            receipt_id=receipt_id,
            user_id=user.id,
            rating=payload.rating,
        )
        db.add(experience)
    else:
        experience.rating = payload.rating
    db.commit()
    db.refresh(experience)
    return experience


@router.get("/receipts/{receipt_id}/balances", response_model=List[schemas.Balance])
def get_receipt_balances(
    receipt_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_receipt_access(db, receipt_id, user)
    return calculate_balances(db, receipt_id)


@router.post("/settlements", response_model=schemas.Settlement)
def create_settlement(
    payload: schemas.SettlementCreate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_access(db, payload.receipt_id, user)
    _validate_member_ids(
        db,
        receipt.group_id,
        [payload.from_user_id, payload.to_user_id],
    )
    if user.id not in {payload.from_user_id, payload.to_user_id}:
        raise HTTPException(status_code=403, detail="You must be part of the settlement")
    settlement = domain.Settlement(
        id=str(uuid.uuid4()),
        receipt_id=payload.receipt_id,
        from_user_id=payload.from_user_id,
        to_user_id=payload.to_user_id,
        amount=payload.amount,
    )
    db.add(settlement)
    db.commit()
    db.refresh(settlement)
    return settlement
