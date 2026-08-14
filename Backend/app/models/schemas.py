from datetime import datetime
import re
from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ProfileBase(BaseModel):
    username: str = Field(min_length=1, max_length=40)
    display_name: Optional[str] = Field(default=None, min_length=1, max_length=80)
    email: str
    age_band: Optional[Literal["under_13", "13_15", "16_17", "18_plus"]] = None

    @field_validator("age_band")
    @classmethod
    def enforce_minimum_age(cls, value: Optional[str]) -> Optional[str]:
        if value == "under_13":
            raise ValueError("Cleave is available only to people age 13 or older")
        return value


class ProfileCreate(ProfileBase):
    id: str


class ProfileUpdate(BaseModel):
    username: Optional[str] = Field(default=None, min_length=1, max_length=40)
    display_name: Optional[str] = Field(default=None, min_length=1, max_length=80)
    age_band: Optional[Literal["under_13", "13_15", "16_17", "18_plus"]] = None
    avatar_visibility: Optional[Literal["everyone", "shared_groups", "private"]] = None
    payment_visibility: Optional[Literal["everyone", "shared_groups", "private"]] = None

    @field_validator("age_band")
    @classmethod
    def enforce_minimum_age(cls, value: Optional[str]) -> Optional[str]:
        if value == "under_13":
            raise ValueError("Cleave is available only to people age 13 or older")
        return value


class Profile(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    username: str
    display_name: Optional[str] = None
    avatar_url: Optional[str] = None
    created_at: datetime


class PrivateProfile(Profile):
    email: str
    region_code: Optional[Literal["US", "IN", "AE"]] = None
    venmo_username: Optional[str] = None
    upi_id: Optional[str] = None
    aani_id: Optional[str] = None
    age_band: Optional[Literal["under_13", "13_15", "16_17", "18_plus"]] = None
    avatar_visibility: Literal["everyone", "shared_groups", "private"] = "shared_groups"
    payment_visibility: Literal["everyone", "shared_groups", "private"] = "shared_groups"


class PaymentDetailsUpdate(BaseModel):
    region_code: Literal["US", "IN", "AE"]
    venmo_username: Optional[str] = Field(default=None, max_length=64)
    upi_id: Optional[str] = Field(default=None, max_length=255)
    aani_id: Optional[str] = Field(default=None, max_length=128)

    @field_validator("venmo_username")
    @classmethod
    def validate_venmo_username(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip().removeprefix("@").strip()
        if not normalized:
            return None
        if not re.fullmatch(r"[A-Za-z0-9_-]{2,64}", normalized):
            raise ValueError("Enter a valid Venmo username")
        return normalized

    @field_validator("upi_id")
    @classmethod
    def validate_upi_id(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip().lower()
        if not normalized:
            return None
        if not re.fullmatch(r"[A-Za-z0-9._-]{2,191}@[A-Za-z][A-Za-z0-9.-]{1,62}", normalized):
            raise ValueError("Enter a valid UPI ID")
        return normalized

    @field_validator("aani_id")
    @classmethod
    def validate_aani_id(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = value.strip()
        if not normalized:
            return None
        if not re.fullmatch(r"[A-Za-z0-9@+._-]{2,128}", normalized):
            raise ValueError("Enter a valid Aani ID or mobile number")
        return normalized


class Member(BaseModel):
    id: str
    username: str
    display_name: Optional[str] = None
    region_code: Optional[Literal["US", "IN", "AE"]] = None
    venmo_username: Optional[str] = None
    upi_id: Optional[str] = None
    aani_id: Optional[str] = None


class GroupCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    is_collaborative: bool = False
    member_ids: List[str] = Field(default_factory=list, max_length=50)


class GroupUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=80)


class MemberAdd(BaseModel):
    user_id: str


class Group(BaseModel):
    id: str
    name: str
    created_by: str
    is_collaborative: bool
    created_at: datetime
    members: List[Member] = Field(default_factory=list)


class ReceiptItemCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    price: float = Field(ge=0, le=1_000_000)


class ReceiptItemUpdate(ReceiptItemCreate):
    id: str


class ManualReceiptCreate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    currency_code: Optional[Literal["USD", "INR", "AED"]] = None
    tax_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    tip_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    discount_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    items: List[ReceiptItemCreate] = Field(min_length=1, max_length=250)


class ReceiptUpdate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    currency_code: Optional[Literal["USD", "INR", "AED"]] = None
    tax_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    tip_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    discount_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    items: List[ReceiptItemUpdate] = Field(min_length=1, max_length=250)


class ReceiptItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    receipt_id: str
    name: str
    price: float
    created_at: datetime
    assigned_user_ids: List[str] = Field(default_factory=list)


class ReceiptMemory(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    receipt_id: str
    user_id: str
    created_at: datetime


class ReceiptParticipant(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    receipt_id: str
    user_id: str
    status: Literal["pending", "submitted"] = "pending"
    submitted_at: Optional[datetime] = None


class Receipt(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    group_id: str
    title: str
    admin_id: str
    currency_code: Literal["USD", "INR", "AED"] = "USD"
    tax_amount: float = 0.0
    tip_amount: float = 0.0
    discount_amount: float = 0.0
    image_url: Optional[str] = None
    created_at: datetime
    items: List[ReceiptItem] = Field(default_factory=list)
    memories: List[ReceiptMemory] = Field(default_factory=list)
    participants: List[ReceiptParticipant] = Field(default_factory=list)
    experiences: List["ReceiptExperience"] = Field(default_factory=list)


class LineItemBase(BaseModel):
    description: str = Field(min_length=1, max_length=200)
    price: float = Field(ge=0, le=1_000_000)


class ParsedReceipt(BaseModel):
    vendor_name: str = Field(min_length=1, max_length=120)
    currency_code: Optional[Literal["USD", "INR", "AED"]] = None
    tax: float = Field(ge=0, le=1_000_000)
    tip: float = Field(ge=0, le=1_000_000)
    discount: float = Field(ge=0, le=1_000_000)
    total: float = Field(ge=0.01, le=1_000_000)
    line_items: List[LineItemBase]


class AssignmentUpdate(BaseModel):
    user_ids: List[str] = Field(max_length=50)


class ItemAssignmentUpdate(AssignmentUpdate):
    item_id: str
    user_ids: List[str] = Field(min_length=1, max_length=50)


class AssignmentBatchUpdate(BaseModel):
    items: List[ItemAssignmentUpdate] = Field(min_length=1, max_length=250)


class ReceiptAdminUpdate(BaseModel):
    receipt: ReceiptUpdate
    assignments: AssignmentBatchUpdate


class ReceiptClaimUpdate(BaseModel):
    item_ids: List[str] = Field(default_factory=list, max_length=250)
    receipt: Optional[ReceiptUpdate] = None


class ProfileSettingsUpdate(BaseModel):
    profile: ProfileUpdate
    payment_details: PaymentDetailsUpdate


class ReceiptExperienceUpdate(BaseModel):
    rating: int = Field(ge=1, le=5)


class ReceiptExperience(ReceiptExperienceUpdate):
    model_config = ConfigDict(from_attributes=True)

    receipt_id: str
    user_id: str
    created_at: datetime
    updated_at: datetime


class BalanceItem(BaseModel):
    item_id: str
    name: str
    amount: float


class Balance(BaseModel):
    user_id: str
    items: List[BalanceItem] = Field(default_factory=list)
    items_total: float
    tax_share: float
    tip_share: float
    discount_share: float = 0.0
    total_owed: float


class SettlementCreate(BaseModel):
    receipt_id: str
    from_user_id: str
    to_user_id: str
    amount: float = Field(gt=0, le=1_000_000)


class Settlement(SettlementCreate):
    model_config = ConfigDict(from_attributes=True)

    id: str
    status: Literal["pending", "confirmed", "rejected"] = "pending"
    settled_at: datetime
    confirmed_at: Optional[datetime] = None
    reviewed_by: Optional[str] = None


class PaymentReviewUpdate(BaseModel):
    status: Literal["confirmed", "rejected"]


class ReceiptReview(BaseModel):
    receipt: Receipt
    balances: List[Balance]
    payments: List[Settlement]
    viewer_is_admin: bool


class InboxItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_id: str
    actor_id: Optional[str] = None
    group_id: Optional[str] = None
    kind: str
    title: str
    body: str
    is_read: bool
    created_at: datetime


class FriendProfile(Profile):
    region_code: Optional[Literal["US", "IN", "AE"]] = None
    venmo_username: Optional[str] = None
    upi_id: Optional[str] = None
    aani_id: Optional[str] = None
