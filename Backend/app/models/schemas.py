from datetime import datetime
import re
from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


CurrencyCode = Literal["USD", "INR", "AED"]


class ProfileBase(BaseModel):
    username: str = Field(min_length=1, max_length=40)
    email: str


class ProfileCreate(ProfileBase):
    id: str


class ProfileUpdate(BaseModel):
    username: str = Field(min_length=1, max_length=40)


class Profile(ProfileBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    avatar_url: Optional[str] = None
    created_at: datetime


class PrivateProfile(Profile):
    region_code: Optional[Literal["US", "IN", "AE"]] = None
    venmo_username: Optional[str] = None
    upi_id: Optional[str] = None


class PaymentDetailsUpdate(BaseModel):
    region_code: Literal["US", "IN", "AE"]
    venmo_username: Optional[str] = Field(default=None, max_length=64)
    upi_id: Optional[str] = Field(default=None, max_length=255)

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

    def validate_required_detail(self) -> None:
        if self.region_code == "US" and not self.venmo_username:
            raise ValueError("A Venmo username is required for the United States")
        if self.region_code == "IN" and not self.upi_id:
            raise ValueError("A UPI ID is required for India")


class Member(BaseModel):
    id: str
    username: str
    region_code: Optional[Literal["US", "IN", "AE"]] = None
    venmo_username: Optional[str] = None
    upi_id: Optional[str] = None


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
    price: float = Field(gt=0, le=1_000_000)


class ReceiptItemUpdate(ReceiptItemCreate):
    id: str


class ManualReceiptCreate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    currency_code: CurrencyCode
    tax_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    tip_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    discount_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    items: List[ReceiptItemCreate] = Field(min_length=1, max_length=250)

    @model_validator(mode="after")
    def validate_total(self):
        _validate_receipt_total(
            self.items,
            self.tax_amount,
            self.tip_amount,
            self.discount_amount,
        )
        return self


class ReceiptUpdate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    tax_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    tip_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    discount_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    items: List[ReceiptItemUpdate] = Field(min_length=1, max_length=250)

    @model_validator(mode="after")
    def validate_total(self):
        _validate_receipt_total(
            self.items,
            self.tax_amount,
            self.tip_amount,
            self.discount_amount,
        )
        return self


def _validate_receipt_total(items, tax_amount: float, tip_amount: float, discount_amount: float) -> None:
    from decimal import Decimal

    gross = sum((Decimal(str(item.price)) for item in items), Decimal("0"))
    gross += Decimal(str(tax_amount)) + Decimal(str(tip_amount))
    total = gross - Decimal(str(discount_amount))
    if total <= 0:
        raise ValueError("Receipt total must be greater than zero")
    if total > Decimal("1000000"):
        raise ValueError("Receipt total cannot exceed 1,000,000")


class ReceiptItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    receipt_id: str
    name: str
    price: float
    created_at: datetime


class ReceiptMemory(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    receipt_id: str
    user_id: str
    created_at: datetime


class Receipt(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    group_id: str
    title: str
    admin_id: str
    currency_code: CurrencyCode
    tax_amount: float = 0.0
    tip_amount: float = 0.0
    discount_amount: float = 0.0
    image_url: Optional[str] = None
    created_at: datetime
    items: List[ReceiptItem] = Field(default_factory=list)
    memories: List[ReceiptMemory] = Field(default_factory=list)


class LineItemBase(BaseModel):
    description: str = Field(min_length=1, max_length=200)
    # Gemini structured output accepts `minimum`, but rejects JSON Schema's
    # `exclusiveMinimum`. Currency values use two decimal places in Cleave.
    price: float = Field(ge=0.01, le=1_000_000)


class ParsedReceipt(BaseModel):
    vendor_name: str = Field(min_length=1, max_length=120)
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


class ReceiptExperienceUpdate(BaseModel):
    rating: int = Field(ge=1, le=5)


class ReceiptExperience(ReceiptExperienceUpdate):
    model_config = ConfigDict(from_attributes=True)

    receipt_id: str
    user_id: str
    created_at: datetime
    updated_at: datetime


class Balance(BaseModel):
    user_id: str
    items_total: float
    tax_share: float
    tip_share: float
    discount_share: float = 0.0
    total_owed: float


class SettlementCreate(BaseModel):
    receipt_id: str
    to_user_id: str


class Settlement(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    receipt_id: str
    from_user_id: str
    to_user_id: str
    amount: float
    currency_code: CurrencyCode
    status: Literal["initiated", "confirmed", "cancelled"]
    initiated_at: datetime
    confirmed_at: Optional[datetime] = None


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
