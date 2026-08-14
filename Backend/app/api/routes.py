from __future__ import annotations

import logging
import os
import uuid
from datetime import datetime, timezone
from io import BytesIO
from typing import List

import httpx
from fastapi import APIRouter, Depends, File, Header, HTTPException, Query, Request, UploadFile, status
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
from app.services.image_validation import ALLOWED_IMAGE_TYPES, validate_image_upload
from app.services.receipt_parser import parseReceiptImage
from app.services.storage import (
    delete_images_from_gcs,
    download_image_from_gcs,
    upload_image_to_gcs,
)


router = APIRouter()
logger = logging.getLogger(__name__)
limiter = Limiter(key_func=get_remote_address)
MAX_RECEIPT_BYTES = 10 * 1024 * 1024


@router.get("/capabilities")
def capabilities():
    return {
        "api_version": 3,
        "features": [
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
        ],
    }


def _group_query(db: Session):
    return db.query(domain.Group).options(
        selectinload(domain.Group.members).selectinload(domain.GroupMember.user)
    )


def _payment_details_visible(profile: domain.Profile, viewer_id: str, *, shares_group: bool) -> bool:
    return profile.id == viewer_id or profile.payment_visibility == "everyone" or (
        profile.payment_visibility == "shared_groups" and shares_group
    )


def _currency_for_user(db: Session, user_id: str) -> str:
    region_code = db.query(domain.Profile.region_code).filter(domain.Profile.id == user_id).scalar()
    return {"IN": "INR", "AE": "AED"}.get(region_code, "USD")


def _serialize_member(profile: domain.Profile, viewer_id: str, *, shares_group: bool) -> dict:
    payment_visible = _payment_details_visible(profile, viewer_id, shares_group=shares_group)
    return {
        "id": profile.id,
        "username": profile.username,
        "display_name": profile.display_name or profile.username,
        "region_code": profile.region_code if payment_visible else None,
        "venmo_username": profile.venmo_username if payment_visible else None,
        "upi_id": profile.upi_id if payment_visible else None,
        "aani_id": profile.aani_id if payment_visible else None,
    }


def _serialize_group(group: domain.Group, viewer_id: str) -> dict:
    return {
        "id": group.id,
        "name": group.name,
        "created_by": group.created_by,
        "is_collaborative": group.is_collaborative,
        "created_at": group.created_at,
        "members": [
            _serialize_member(membership.user, viewer_id, shares_group=True)
            for membership in group.members
            if membership.user is not None
        ],
    }


def _serialize_group_with_profiles(
    group: domain.Group, profiles: list[domain.Profile], viewer_id: str
) -> dict:
    return {
        "id": group.id,
        "name": group.name,
        "created_by": group.created_by,
        "is_collaborative": group.is_collaborative,
        "created_at": group.created_at,
        "members": [
            _serialize_member(profile, viewer_id, shares_group=True)
            for profile in sorted(profiles, key=lambda value: (value.username.casefold(), value.id))
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
    # Access checks do not need the members collection. Avoiding eager loading
    # here saves two database round trips on every receipt mutation.
    group = db.query(domain.Group).filter(domain.Group.id == group_id).first()
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
            selectinload(domain.Receipt.items).selectinload(domain.ReceiptItem.assignments),
            selectinload(domain.Receipt.memories),
            selectinload(domain.Receipt.participants),
            selectinload(domain.Receipt.experiences),
        )
        .filter(domain.Receipt.id == receipt_id)
        .first()
    )
    if receipt is None:
        raise HTTPException(status_code=404, detail="Receipt not found")
    _require_group_access(db, receipt.group_id, user)
    return receipt


def _require_receipt_admin(
    db: Session, receipt_id: str, user: AuthenticatedUser
) -> domain.Receipt:
    receipt = _require_receipt_access(db, receipt_id, user)
    if receipt.admin_id != user.id:
        raise HTTPException(status_code=403, detail="Only the receipt admin can do that")
    return receipt


def _shares_collaborative_group(db: Session, viewer_id: str, profile_id: str) -> bool:
    if viewer_id == profile_id:
        return True
    viewer_groups = db.query(domain.GroupMember.group_id).join(
        domain.Group, domain.Group.id == domain.GroupMember.group_id
    ).filter(
        domain.GroupMember.user_id == viewer_id,
        domain.Group.is_collaborative.is_(True),
    )
    return db.query(domain.GroupMember).filter(
        domain.GroupMember.user_id == profile_id,
        domain.GroupMember.group_id.in_(viewer_groups),
    ).first() is not None


def _serialize_public_profile(db: Session, profile: domain.Profile, viewer_id: str) -> dict:
    shares_group = _shares_collaborative_group(db, viewer_id, profile.id)
    avatar_visible = profile.id == viewer_id or profile.avatar_visibility == "everyone" or (
        profile.avatar_visibility == "shared_groups" and shares_group
    )
    return {
        "id": profile.id,
        "username": profile.username,
        "display_name": profile.display_name or profile.username,
        "avatar_url": profile.avatar_url if avatar_visible else None,
        "created_at": profile.created_at,
    }


def _validate_participant_ids(receipt: domain.Receipt, user_ids: list[str]) -> None:
    if not user_ids:
        return
    participant_ids = {participant.user_id for participant in receipt.participants}
    if not set(user_ids).issubset(participant_ids):
        raise HTTPException(status_code=400, detail="Assignments must reference receipt participants")


def _apply_assignments(
    db: Session,
    receipt: domain.Receipt,
    payload: schemas.AssignmentBatchUpdate,
) -> None:
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
    _validate_participant_ids(receipt, list(all_user_ids))
    desired = {
        (item.item_id, user_id)
        for item in payload.items
        for user_id in set(item.user_ids)
    }
    existing = db.query(domain.ReceiptAssignment).filter(
        domain.ReceiptAssignment.item_id.in_(receipt_item_ids)
    ).all()
    existing_keys = {(assignment.item_id, assignment.user_id) for assignment in existing}
    for assignment in existing:
        if (assignment.item_id, assignment.user_id) not in desired:
            db.delete(assignment)
    db.add_all(
        domain.ReceiptAssignment(item_id=item_id, user_id=user_id)
        for item_id, user_id in desired - existing_keys
    )


def _apply_receipt_update(receipt: domain.Receipt, payload: schemas.ReceiptUpdate) -> None:
    existing_items = {item.id: item for item in receipt.items}
    requested_ids = [item.id for item in payload.items]
    if len(requested_ids) != len(set(requested_ids)) or set(requested_ids) != set(existing_items):
        raise HTTPException(
            status_code=400,
            detail="Receipt edits must contain every original item exactly once",
        )
    receipt.title = payload.title.strip()
    if payload.currency_code is not None:
        receipt.currency_code = payload.currency_code
    receipt.tax_amount = payload.tax_amount
    receipt.tip_amount = payload.tip_amount
    receipt.discount_amount = payload.discount_amount
    for item in payload.items:
        existing_items[item.id].name = item.name.strip()
        existing_items[item.id].price = item.price


def _receipt_details_changed(receipt: domain.Receipt, payload: schemas.ReceiptUpdate) -> bool:
    existing_items = {item.id: item for item in receipt.items}
    return (
        receipt.title != payload.title.strip()
        or (payload.currency_code is not None and receipt.currency_code != payload.currency_code)
        or float(receipt.tax_amount) != payload.tax_amount
        or float(receipt.tip_amount) != payload.tip_amount
        or float(receipt.discount_amount) != payload.discount_amount
        or any(
            item.id not in existing_items
            or existing_items[item.id].name != item.name.strip()
            or float(existing_items[item.id].price) != item.price
            for item in payload.items
        )
    )


def _ensure_no_confirmed_payments(db: Session, receipt_id: str) -> None:
    confirmed = db.query(domain.Settlement.id).filter(
        domain.Settlement.receipt_id == receipt_id,
        domain.Settlement.status == "confirmed",
    ).first()
    if confirmed is not None:
        raise HTTPException(
            status_code=409,
            detail="Confirmed payments lock receipt amounts and allocations",
        )


def _invalidate_pending_payments(db: Session, receipt_id: str) -> None:
    db.query(domain.Settlement).filter(
        domain.Settlement.receipt_id == receipt_id,
        domain.Settlement.status == "pending",
    ).update(
        {
            domain.Settlement.status: "rejected",
            domain.Settlement.confirmed_at: None,
            domain.Settlement.reviewed_by: None,
        },
        synchronize_session=False,
    )


def _ensure_receipt_ready_for_payment(db: Session, receipt: domain.Receipt) -> None:
    if any(participant.status != "submitted" for participant in receipt.participants):
        raise HTTPException(status_code=409, detail="Everyone must finish choosing before payments begin")
    unclaimed = any(not item.assignments for item in receipt.items)
    if unclaimed:
        raise HTTPException(status_code=409, detail="Every receipt item must be claimed before payments begin")


def _reset_participant_confirmations(receipt: domain.Receipt) -> None:
    for participant in receipt.participants:
        participant.status = "pending"
        participant.submitted_at = None


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


@router.post("/profiles/bootstrap", response_model=schemas.PrivateProfile)
def bootstrap_profile(
    profile: schemas.ProfileBase,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    existing = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if user.email and profile.email.casefold() != user.email.casefold():
        raise HTTPException(status_code=403, detail="Email does not match authenticated user")
    username = profile.username.strip()
    display_name = (profile.display_name or username).strip()
    username_taken = (
        db.query(domain.Profile)
        .filter(domain.Profile.username == username, domain.Profile.id != user.id)
        .first()
        is not None
    )
    if username_taken:
        username = f"{username[:31]}-{user.id[:8]}"
    if existing:
        # Supabase's auth trigger creates a fallback profile before this route
        # runs. Replace that fallback with the username chosen in onboarding.
        if existing.username != username:
            existing.username = username
        existing.display_name = display_name
        if profile.age_band is not None:
            existing.age_band = profile.age_band
        db.commit()
        db.refresh(existing)
        return existing
    if os.environ.get("ENVIRONMENT", "").strip().lower() in {"production", "staging"}:
        # Supabase creates profiles with a database trigger. If an authenticated
        # identity no longer has a profile in a managed environment, the account
        # was deleted (or provisioning failed) and a still-valid access token
        # must not be allowed to silently recreate it.
        raise HTTPException(status_code=401, detail="Account is no longer available")
    created = domain.Profile(
        id=user.id,
        email=user.email or profile.email,
        username=username,
        display_name=display_name,
        age_band=profile.age_band,
    )
    db.add(created)
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        raise HTTPException(status_code=409, detail="A profile already exists for this account") from error
    db.refresh(created)
    return created


@router.get("/profiles/me", response_model=schemas.PrivateProfile)
def get_my_profile(
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    profile = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if profile is None:
        raise HTTPException(status_code=404, detail="Profile not found")
    return profile


@router.patch("/profiles/me", response_model=schemas.PrivateProfile)
def update_my_profile(
    payload: schemas.ProfileUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    profile = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if profile is None:
        raise HTTPException(status_code=404, detail="Profile not found")
    requested_username = payload.username.strip() if payload.username is not None else None
    existing = (
        db.query(domain.Profile)
        .filter(
            domain.Profile.username == requested_username,
            domain.Profile.id != user.id,
        )
        .first()
    ) if requested_username else None
    if existing:
        raise HTTPException(status_code=409, detail="That username is already taken")
    if requested_username is not None:
        profile.username = requested_username
    if payload.display_name is not None:
        profile.display_name = payload.display_name.strip()
    if payload.age_band is not None:
        profile.age_band = payload.age_band
    if payload.avatar_visibility is not None:
        profile.avatar_visibility = payload.avatar_visibility
    if payload.payment_visibility is not None:
        profile.payment_visibility = payload.payment_visibility
    db.commit()
    db.refresh(profile)
    return profile


@router.patch("/profiles/me/payment-details", response_model=schemas.PrivateProfile)
def update_my_payment_details(
    payload: schemas.PaymentDetailsUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    profile = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if profile is None:
        raise HTTPException(status_code=404, detail="Profile not found")
    profile.region_code = payload.region_code
    profile.venmo_username = payload.venmo_username
    profile.upi_id = payload.upi_id
    profile.aani_id = payload.aani_id
    db.commit()
    db.refresh(profile)
    return profile


@router.put("/profiles/me/settings", response_model=schemas.PrivateProfile)
def update_my_profile_settings(
    payload: schemas.ProfileSettingsUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    """Save the editable profile form in one database transaction."""
    profile = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if profile is None:
        raise HTTPException(status_code=404, detail="Profile not found")

    requested_username = (
        payload.profile.username.strip()
        if payload.profile.username is not None
        else profile.username
    )
    existing = db.query(domain.Profile).filter(
        domain.Profile.username == requested_username,
        domain.Profile.id != user.id,
    ).first()
    if existing:
        raise HTTPException(status_code=409, detail="That username is already taken")

    profile.username = requested_username
    if payload.profile.display_name is not None:
        profile.display_name = payload.profile.display_name.strip()
    if payload.profile.age_band is not None:
        profile.age_band = payload.profile.age_band
    if payload.profile.avatar_visibility is not None:
        profile.avatar_visibility = payload.profile.avatar_visibility
    if payload.profile.payment_visibility is not None:
        profile.payment_visibility = payload.profile.payment_visibility
    profile.region_code = payload.payment_details.region_code
    profile.venmo_username = payload.payment_details.venmo_username
    profile.upi_id = payload.payment_details.upi_id
    profile.aani_id = payload.payment_details.aani_id
    db.commit()
    db.refresh(profile)
    return profile


@router.post("/profiles/me/avatar", response_model=schemas.PrivateProfile)
@limiter.limit("10/minute")
async def update_my_avatar(
    request: Request,
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
    try:
        mime_type = validate_image_upload(image_bytes, file.content_type or "")
    except ValueError as error:
        raise HTTPException(status_code=415, detail="Choose a valid JPEG, PNG, or HEIC image") from error

    old_avatar = profile.avatar_url
    object_name = await run_in_threadpool(
        upload_image_to_gcs,
        image_bytes,
        mime_type,
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
    user: AuthenticatedUser = Depends(get_current_user),
):
    profile = db.query(domain.Profile).filter(domain.Profile.id == profile_id).first()
    if profile is None or not profile.avatar_url:
        raise HTTPException(status_code=404, detail="Profile photo not found")
    shares_group = _shares_collaborative_group(db, user.id, profile.id)
    if not (
        profile.id == user.id
        or profile.avatar_visibility == "everyone"
        or (profile.avatar_visibility == "shared_groups" and shares_group)
    ):
        raise HTTPException(status_code=404, detail="Profile photo not found")
    downloaded = download_image_from_gcs(profile.avatar_url)
    if downloaded is None:
        raise HTTPException(status_code=404, detail="Profile photo not found")
    content, content_type = downloaded
    return StreamingResponse(
        BytesIO(content),
        media_type=content_type,
        headers={"Cache-Control": "private, no-store"},
    )


@router.delete("/profiles/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_my_account(
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    secret_key = os.environ.get("SUPABASE_SECRET_KEY", "") or os.environ.get(
        "SUPABASE_SERVICE_ROLE_KEY", ""
    )
    if not supabase_url or not secret_key:
        raise HTTPException(
            status_code=503,
            detail="Account deletion is temporarily unavailable",
        )

    image_objects = _account_image_objects(db, user.id)

    try:
        response = httpx.delete(
            f"{supabase_url}/auth/v1/admin/users/{user.id}",
            headers={
                "Authorization": f"Bearer {secret_key}",
                "apikey": secret_key,
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
    query: str = Query(min_length=2, max_length=40),
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    profiles = db.query(domain.Profile).filter(domain.Profile.id != user.id)
    escaped = query.strip().replace("%", r"\%").replace("_", r"\_")
    if len(escaped) < 2:
        raise HTTPException(status_code=422, detail="Enter at least two username characters")
    profiles = profiles.filter(domain.Profile.username.ilike(f"%{escaped}%", escape="\\"))
    matches = profiles.order_by(domain.Profile.username.asc()).limit(20).all()
    return [_serialize_public_profile(db, profile, user.id) for profile in matches]


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
    profiles = db.query(domain.Profile).filter(domain.Profile.id.in_(friend_ids)).order_by(
        domain.Profile.display_name.asc(), domain.Profile.username.asc()
    ).all()
    return [_serialize_public_profile(db, profile, user.id) for profile in profiles]


@router.get("/friends/{profile_id}", response_model=schemas.FriendProfile)
def get_friend_profile(
    profile_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    if profile_id == user.id or not _shares_collaborative_group(db, user.id, profile_id):
        raise HTTPException(status_code=404, detail="Friend profile not found")
    profile = db.query(domain.Profile).filter(domain.Profile.id == profile_id).first()
    if profile is None:
        raise HTTPException(status_code=404, detail="Friend profile not found")
    public = _serialize_public_profile(db, profile, user.id)
    payment_visible = _payment_details_visible(profile, user.id, shares_group=True)
    public.update({
        "region_code": profile.region_code if payment_visible else None,
        "venmo_username": profile.venmo_username if payment_visible else None,
        "upi_id": profile.upi_id if payment_visible else None,
        "aani_id": profile.aani_id if payment_visible else None,
    })
    return public


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
    requested_ids = set(payload.member_ids)
    requested_ids.add(user.id)
    profiles = db.query(domain.Profile).filter(domain.Profile.id.in_(requested_ids)).all()
    if len(profiles) != len(requested_ids):
        raise HTTPException(status_code=400, detail="One or more selected members no longer exist")
    creator = next((profile for profile in profiles if profile.id == user.id), None)
    if creator is None:
        raise HTTPException(status_code=409, detail="Create your profile before creating a group")

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
    db.flush()
    response = _serialize_group_with_profiles(group, profiles, user.id)
    db.commit()
    return response


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
    return [_serialize_group(group, user.id) for group in groups]


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
    return _serialize_group(_group_query(db).filter(domain.Group.id == group_id).one(), user.id)


@router.post("/groups/{group_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
def leave_group(
    group_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    group = _require_group_access(db, group_id, user)
    membership = _membership(db, group_id, user.id)
    if membership is None:
        raise HTTPException(status_code=403, detail="You are not a member of this group")

    remaining_memberships = (
        db.query(domain.GroupMember)
        .filter(
            domain.GroupMember.group_id == group_id,
            domain.GroupMember.user_id != user.id,
        )
        .order_by(domain.GroupMember.joined_at.asc(), domain.GroupMember.user_id.asc())
        .all()
    )

    # A member who leaves before responding must not keep the receipt locked in
    # a permanent pending state. Existing claims remain part of the historical
    # split, while an unanswered participant becomes an explicit zero share.
    receipt_ids = db.query(domain.Receipt.id).filter(domain.Receipt.group_id == group_id)
    db.query(domain.ReceiptParticipant).filter(
        domain.ReceiptParticipant.receipt_id.in_(receipt_ids),
        domain.ReceiptParticipant.user_id == user.id,
        domain.ReceiptParticipant.status == "pending",
    ).update(
        {
            domain.ReceiptParticipant.status: "submitted",
            domain.ReceiptParticipant.submitted_at: datetime.now(timezone.utc),
        },
        synchronize_session=False,
    )

    db.query(domain.InboxItem).filter(
        domain.InboxItem.group_id == group_id,
        domain.InboxItem.user_id == user.id,
    ).delete(synchronize_session=False)

    image_objects: list[str] = []
    if remaining_memberships:
        if group.created_by == user.id:
            group.created_by = remaining_memberships[0].user_id
        db.delete(membership)
    else:
        # Empty groups are unreachable. Clean them up as a consequence of the
        # final member leaving, without exposing destructive group deletion.
        image_objects = _group_image_objects(db, group_id)
        db.delete(group)
    db.commit()
    if image_objects:
        delete_images_from_gcs(image_objects)


@router.delete("/groups/{group_id}", status_code=status.HTTP_405_METHOD_NOT_ALLOWED)
def delete_group_is_not_allowed(
    group_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_group_access(db, group_id, user)
    raise HTTPException(
        status_code=status.HTTP_405_METHOD_NOT_ALLOWED,
        detail="Groups cannot be deleted. Leave the group instead.",
    )


@router.post("/groups/{group_id}/members", response_model=schemas.Group)
def add_group_member(
    group_id: str,
    payload: schemas.MemberAdd,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    group = _require_group_access(db, group_id, user, require_owner=True)
    profiles = db.query(domain.Profile).filter(
        domain.Profile.id.in_({user.id, payload.user_id})
    ).all()
    profile_by_id = {profile.id: profile for profile in profiles}
    if payload.user_id not in profile_by_id:
        raise HTTPException(status_code=404, detail="Profile not found")
    existing = _membership(db, group_id, payload.user_id)
    if existing is None:
        db.add(domain.GroupMember(group_id=group_id, user_id=payload.user_id))
        actor = profile_by_id[user.id]
        db.add(domain.InboxItem(
            id=str(uuid.uuid4()),
            user_id=payload.user_id,
            actor_id=user.id,
            group_id=group_id,
            kind="group_added",
            title=f"You were added to {group.name}",
            body=f"{actor.username} added you to a collaborative group.",
        ))
        db.flush()
    member_profiles = (
        db.query(domain.Profile)
        .join(domain.GroupMember, domain.GroupMember.user_id == domain.Profile.id)
        .filter(domain.GroupMember.group_id == group_id)
        .all()
    )
    response = _serialize_group_with_profiles(group, member_profiles, user.id)
    if existing is None:
        db.commit()
    return response


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
            selectinload(domain.Receipt.items).selectinload(domain.ReceiptItem.assignments),
            selectinload(domain.Receipt.memories),
            selectinload(domain.Receipt.participants),
            selectinload(domain.Receipt.experiences),
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
    currency_code: str,
    items: list[schemas.ReceiptItemCreate],
    image_url: str | None = None,
    client_request_id: str | None = None,
) -> domain.Receipt:
    receipt = domain.Receipt(
        id=str(uuid.uuid4()),
        group_id=group_id,
        title=title,
        admin_id=user_id,
        currency_code=currency_code,
        tax_amount=tax,
        tip_amount=tip,
        discount_amount=discount,
        image_url=image_url,
        client_request_id=client_request_id,
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
    member_ids = [
        member_id
        for (member_id,) in db.query(domain.GroupMember.user_id)
        .filter(domain.GroupMember.group_id == group_id)
        .all()
    ]
    db.add_all(
        domain.ReceiptParticipant(receipt_id=receipt.id, user_id=member_id)
        for member_id in member_ids
    )
    try:
        db.commit()
    except IntegrityError as error:
        db.rollback()
        if client_request_id:
            existing = db.query(domain.Receipt).filter(
                domain.Receipt.client_request_id == client_request_id,
                domain.Receipt.group_id == group_id,
                domain.Receipt.admin_id == user_id,
            ).first()
            if existing is not None:
                receipt = existing
            else:
                raise HTTPException(status_code=409, detail="Receipt scan request already used") from error
        else:
            raise
    return (
        db.query(domain.Receipt)
        .options(
            selectinload(domain.Receipt.items).selectinload(domain.ReceiptItem.assignments),
            selectinload(domain.Receipt.memories),
            selectinload(domain.Receipt.participants),
            selectinload(domain.Receipt.experiences),
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
    profile = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    fallback_currency = {"IN": "INR", "AE": "AED"}.get(
        profile.region_code if profile else None,
        "USD",
    )
    return _create_receipt(
        db,
        group_id=group_id,
        user_id=user.id,
        title=payload.title.strip(),
        tax=payload.tax_amount,
        tip=payload.tip_amount,
        discount=payload.discount_amount,
        currency_code=payload.currency_code or fallback_currency,
        items=payload.items,
    )


@router.patch("/receipts/{receipt_id}", response_model=schemas.Receipt)
def update_receipt(
    receipt_id: str,
    payload: schemas.ReceiptUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_admin(db, receipt_id, user)
    _ensure_no_confirmed_payments(db, receipt_id)
    _apply_receipt_update(receipt, payload)
    _reset_participant_confirmations(receipt)
    _invalidate_pending_payments(db, receipt_id)
    db.commit()
    return _require_receipt_access(db, receipt_id, user)


@router.put("/receipts/{receipt_id}/claim", response_model=schemas.ReceiptReview)
def submit_my_receipt_claim(
    receipt_id: str,
    payload: schemas.ReceiptClaimUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_access(db, receipt_id, user)
    _ensure_no_confirmed_payments(db, receipt_id)
    participant = next(
        (value for value in receipt.participants if value.user_id == user.id),
        None,
    )
    if participant is None:
        raise HTTPException(status_code=403, detail="You were not a participant when this receipt was created")

    requested_item_ids = payload.item_ids
    if len(requested_item_ids) != len(set(requested_item_ids)):
        raise HTTPException(status_code=400, detail="A receipt item can only be selected once")
    valid_item_ids = {item.id for item in receipt.items}
    if not set(requested_item_ids).issubset(valid_item_ids):
        raise HTTPException(status_code=400, detail="Claims must reference this receipt's items")

    if payload.receipt is not None:
        if receipt.admin_id != user.id:
            raise HTTPException(status_code=403, detail="Only the receipt admin can edit scanned details")
        changed = _receipt_details_changed(receipt, payload.receipt)
        _apply_receipt_update(receipt, payload.receipt)
        if changed:
            _reset_participant_confirmations(receipt)

    existing_claims = [
        assignment
        for item in receipt.items
        for assignment in item.assignments
        if assignment.user_id == user.id
    ]
    existing_item_ids = {assignment.item_id for assignment in existing_claims}
    for assignment in existing_claims:
        if assignment.item_id not in requested_item_ids:
            db.delete(assignment)
    db.add_all(
        domain.ReceiptAssignment(item_id=item_id, user_id=user.id)
        for item_id in set(requested_item_ids) - existing_item_ids
    )
    participant.status = "submitted"
    participant.submitted_at = datetime.now(timezone.utc)
    _invalidate_pending_payments(db, receipt_id)
    db.commit()
    return get_receipt_review(receipt_id, db, user)


@router.put("/receipts/{receipt_id}/review", response_model=schemas.Receipt)
def save_admin_receipt_review(
    receipt_id: str,
    payload: schemas.ReceiptAdminUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_admin(db, receipt_id, user)
    _ensure_no_confirmed_payments(db, receipt_id)
    changed = _receipt_details_changed(receipt, payload.receipt)
    _apply_receipt_update(receipt, payload.receipt)
    if changed:
        _reset_participant_confirmations(receipt)
    _apply_assignments(db, receipt, payload.assignments)
    _invalidate_pending_payments(db, receipt_id)
    db.commit()
    return _require_receipt_access(db, receipt_id, user)


@router.delete("/receipts/{receipt_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_receipt(
    receipt_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_admin(db, receipt_id, user)
    image_objects = ([receipt.image_url] if receipt.image_url else []) + [
        memory.image_url for memory in receipt.memories
    ]
    db.delete(receipt)
    db.commit()
    if not delete_images_from_gcs(image_objects):
        logger.warning("Receipt %s deleted but one or more private images could not be removed", receipt_id)


@router.post("/receipts", response_model=schemas.Receipt)
@limiter.limit("5/minute")
async def upload_receipt(
    request: Request,
    group_id: str,
    file: UploadFile = File(...),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_group_access(db, group_id, user)
    if idempotency_key:
        try:
            idempotency_key = str(uuid.UUID(idempotency_key))
        except ValueError as error:
            raise HTTPException(status_code=400, detail="Invalid receipt request identifier") from error
        existing = db.query(domain.Receipt).filter(
            domain.Receipt.client_request_id == idempotency_key,
        ).first()
        if existing is not None:
            if existing.group_id != group_id or existing.admin_id != user.id:
                raise HTTPException(status_code=409, detail="Receipt request identifier already used")
            return _require_receipt_access(db, existing.id, user)
    mime_type = (file.content_type or "").lower()
    if mime_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=415, detail="Upload a JPEG, PNG, HEIC, or HEIF image")

    image_bytes = await file.read(MAX_RECEIPT_BYTES + 1)
    if not image_bytes:
        raise HTTPException(status_code=400, detail="The receipt image is empty")
    if len(image_bytes) > MAX_RECEIPT_BYTES:
        raise HTTPException(status_code=413, detail="Receipt images must be 10 MB or smaller")
    try:
        mime_type = validate_image_upload(image_bytes, mime_type)
    except ValueError as error:
        raise HTTPException(status_code=415, detail="Upload a valid JPEG, PNG, HEIC, or HEIF image") from error

    try:
        parsed = await run_in_threadpool(parseReceiptImage, image_bytes, mime_type)
    except ValueError as error:
        error_status = 503 if "temporarily unavailable" in str(error).lower() else 422
        raise HTTPException(status_code=error_status, detail=str(error)) from error

    image_url = await run_in_threadpool(upload_image_to_gcs, image_bytes, mime_type)
    if not image_url:
        # The source image is useful but not required after a valid structured
        # receipt has been extracted. Do not throw away a successful scan just
        # because optional image storage is temporarily unavailable.
        logger.warning("Receipt image storage unavailable; saving parsed receipt without source image")
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
        currency_code=parsed.currency_code or _currency_for_user(db, user.id),
        items=items,
        image_url=image_url,
        client_request_id=idempotency_key,
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
        mime_type = validate_image_upload(image_bytes, mime_type)
    except ValueError as error:
        raise HTTPException(status_code=415, detail="Upload a valid JPEG, PNG, HEIC, or HEIF image") from error
    try:
        return await run_in_threadpool(parseReceiptImage, image_bytes, mime_type)
    except ValueError as error:
        error_status = 503 if "temporarily unavailable" in str(error).lower() else 422
        raise HTTPException(status_code=error_status, detail=str(error)) from error


@router.patch("/receipts/{receipt_id}/items/{item_id}/assignments")
def assign_receipt_item(
    receipt_id: str,
    item_id: str,
    payload: schemas.AssignmentUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_admin(db, receipt_id, user)
    _ensure_no_confirmed_payments(db, receipt_id)
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
    _validate_participant_ids(receipt, payload.user_ids)

    db.query(domain.ReceiptAssignment).filter(
        domain.ReceiptAssignment.item_id == item_id
    ).delete(synchronize_session=False)
    db.add_all(
        [domain.ReceiptAssignment(item_id=item_id, user_id=user_id) for user_id in set(payload.user_ids)]
    )
    _invalidate_pending_payments(db, receipt_id)
    db.commit()
    return {"status": "ok"}


@router.patch("/receipts/{receipt_id}/assignments")
def assign_receipt_items(
    receipt_id: str,
    payload: schemas.AssignmentBatchUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_admin(db, receipt_id, user)
    _ensure_no_confirmed_payments(db, receipt_id)
    _apply_assignments(db, receipt, payload)
    _invalidate_pending_payments(db, receipt_id)
    db.commit()
    return {"status": "ok"}


@router.post(
    "/receipts/{receipt_id}/memories",
    response_model=schemas.ReceiptMemory,
    status_code=status.HTTP_201_CREATED,
)
@limiter.limit("10/minute")
async def upload_receipt_memory(
    receipt_id: str,
    request: Request,
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
    try:
        mime_type = validate_image_upload(image_bytes, mime_type)
    except ValueError as error:
        raise HTTPException(status_code=415, detail="Upload a valid JPEG, PNG, HEIC, or HEIF image") from error
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


@router.get(
    "/receipts/{receipt_id}/experience",
    response_model=schemas.ReceiptExperience | None,
)
def get_receipt_experience(
    receipt_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_receipt_access(db, receipt_id, user)
    return (
        db.query(domain.ReceiptExperience)
        .filter(
            domain.ReceiptExperience.receipt_id == receipt_id,
            domain.ReceiptExperience.user_id == user.id,
        )
        .first()
    )


@router.get("/receipts/{receipt_id}/balances", response_model=List[schemas.Balance])
def get_receipt_balances(
    receipt_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    _require_receipt_access(db, receipt_id, user)
    return calculate_balances(db, receipt_id)


@router.get("/receipts/{receipt_id}/review", response_model=schemas.ReceiptReview)
def get_receipt_review(
    receipt_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_access(db, receipt_id, user)
    payments = db.query(domain.Settlement).filter(
        domain.Settlement.receipt_id == receipt_id
    )
    if receipt.admin_id != user.id:
        payments = payments.filter(domain.Settlement.from_user_id == user.id)
    return {
        "receipt": receipt,
        "balances": calculate_balances(db, receipt_id),
        "payments": payments.order_by(domain.Settlement.settled_at.desc()).all(),
        "viewer_is_admin": receipt.admin_id == user.id,
    }


def _mark_current_user_paid(
    db: Session, receipt: domain.Receipt, user: AuthenticatedUser
) -> domain.Settlement:
    if receipt.admin_id == user.id:
        raise HTTPException(status_code=409, detail="The receipt admin does not pay themselves")
    _ensure_receipt_ready_for_payment(db, receipt)
    balance = next(
        (value for value in calculate_balances(db, receipt.id) if value.user_id == user.id),
        None,
    )
    if balance is None or balance.total_owed <= 0:
        raise HTTPException(status_code=409, detail="You do not have an outstanding balance on this receipt")
    settlement = db.query(domain.Settlement).filter(
        domain.Settlement.receipt_id == receipt.id,
        domain.Settlement.from_user_id == user.id,
        domain.Settlement.to_user_id == receipt.admin_id,
    ).first()
    if settlement is None:
        settlement = domain.Settlement(
            id=str(uuid.uuid4()),
            receipt_id=receipt.id,
            from_user_id=user.id,
            to_user_id=receipt.admin_id,
            amount=balance.total_owed,
        )
        try:
            # The database uniqueness constraint is the final guard when two
            # devices mark the same payment at nearly the same time.
            with db.begin_nested():
                db.add(settlement)
                db.flush()
        except IntegrityError:
            settlement = db.query(domain.Settlement).filter(
                domain.Settlement.receipt_id == receipt.id,
                domain.Settlement.from_user_id == user.id,
                domain.Settlement.to_user_id == receipt.admin_id,
            ).first()
            if settlement is None:
                raise HTTPException(status_code=409, detail="Payment status changed; refresh and try again")
    elif settlement.status != "confirmed":
        settlement.amount = balance.total_owed
        settlement.status = "pending"
        settlement.settled_at = datetime.now(timezone.utc)
        settlement.confirmed_at = None
        settlement.reviewed_by = None
    db.flush()
    return settlement


@router.put("/receipts/{receipt_id}/payment-status", response_model=schemas.Settlement)
def mark_my_receipt_payment_paid(
    receipt_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_access(db, receipt_id, user)
    payment = _mark_current_user_paid(db, receipt, user)
    admin_profile = db.query(domain.Profile).filter(domain.Profile.id == receipt.admin_id).first()
    payer_profile = db.query(domain.Profile).filter(domain.Profile.id == user.id).first()
    if payment.status == "pending" and admin_profile and payer_profile:
        existing_notice = db.query(domain.InboxItem).filter(
            domain.InboxItem.user_id == receipt.admin_id,
            domain.InboxItem.actor_id == user.id,
            domain.InboxItem.group_id == receipt.group_id,
            domain.InboxItem.kind == f"payment_marked:{receipt.id}",
            domain.InboxItem.is_read.is_(False),
        ).first()
        if existing_notice is None:
            db.add(domain.InboxItem(
                id=str(uuid.uuid4()),
                user_id=receipt.admin_id,
                actor_id=user.id,
                group_id=receipt.group_id,
                kind=f"payment_marked:{receipt.id}",
                title=f"Payment marked for {receipt.title}",
                body=f"{payer_profile.username} marked their payment as sent. Review it before confirming.",
            ))
    db.commit()
    db.refresh(payment)
    return payment


@router.delete("/receipts/{receipt_id}/payment-status", status_code=status.HTTP_204_NO_CONTENT)
def withdraw_my_receipt_payment_mark(
    receipt_id: str,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_access(db, receipt_id, user)
    payment = db.query(domain.Settlement).filter(
        domain.Settlement.receipt_id == receipt.id,
        domain.Settlement.from_user_id == user.id,
        domain.Settlement.to_user_id == receipt.admin_id,
    ).first()
    if payment is None:
        return
    if payment.status == "confirmed":
        raise HTTPException(status_code=409, detail="A confirmed payment cannot be withdrawn")
    db.delete(payment)
    db.commit()


@router.patch(
    "/receipts/{receipt_id}/payments/{payment_id}",
    response_model=schemas.Settlement,
)
def review_receipt_payment(
    receipt_id: str,
    payment_id: str,
    payload: schemas.PaymentReviewUpdate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_admin(db, receipt_id, user)
    payment = db.query(domain.Settlement).filter(
        domain.Settlement.id == payment_id,
        domain.Settlement.receipt_id == receipt.id,
        domain.Settlement.to_user_id == receipt.admin_id,
    ).first()
    if payment is None:
        raise HTTPException(status_code=404, detail="Payment mark not found")
    if payment.status == "confirmed" and payload.status != "confirmed":
        raise HTTPException(status_code=409, detail="A confirmed payment cannot be rejected")
    if payment.status == payload.status:
        return payment
    payment.status = payload.status
    payment.reviewed_by = user.id
    payment.confirmed_at = datetime.now(timezone.utc) if payload.status == "confirmed" else None
    db.add(domain.InboxItem(
        id=str(uuid.uuid4()),
        user_id=payment.from_user_id,
        actor_id=user.id,
        group_id=receipt.group_id,
        kind=f"payment_{payload.status}:{receipt.id}",
        title=f"Payment {payload.status}",
        body=f"Your payment mark for {receipt.title} was {payload.status} by the receipt admin.",
    ))
    db.commit()
    db.refresh(payment)
    return payment


@router.post("/settlements", response_model=schemas.Settlement)
def create_settlement(
    payload: schemas.SettlementCreate,
    db: Session = Depends(get_db),
    user: AuthenticatedUser = Depends(get_current_user),
):
    receipt = _require_receipt_access(db, payload.receipt_id, user)
    if payload.from_user_id != user.id or payload.to_user_id != receipt.admin_id:
        raise HTTPException(status_code=403, detail="You can only mark your own payment to the receipt admin")
    balance = next(
        (value for value in calculate_balances(db, receipt.id) if value.user_id == user.id),
        None,
    )
    if balance is None or abs(balance.total_owed - payload.amount) > 0.01:
        raise HTTPException(status_code=409, detail="Payment amount must match your current receipt balance")
    settlement = _mark_current_user_paid(db, receipt, user)
    db.commit()
    db.refresh(settlement)
    return settlement
