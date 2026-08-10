from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


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


class Member(BaseModel):
    id: str
    username: str


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
    tax_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    tip_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    discount_amount: float = Field(default=0.0, ge=0, le=1_000_000)
    items: List[ReceiptItemCreate] = Field(min_length=1, max_length=250)


class ReceiptUpdate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
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
    tax_amount: float = 0.0
    tip_amount: float = 0.0
    discount_amount: float = 0.0
    image_url: Optional[str] = None
    created_at: datetime
    items: List[ReceiptItem] = Field(default_factory=list)
    memories: List[ReceiptMemory] = Field(default_factory=list)


class LineItemBase(BaseModel):
    description: str = Field(min_length=1, max_length=200)
    price: float = Field(ge=0, le=1_000_000)


class ParsedReceipt(BaseModel):
    vendor_name: str = Field(min_length=1, max_length=120)
    tax: float = Field(ge=0, le=1_000_000)
    tip: float = Field(ge=0, le=1_000_000)
    discount: float = Field(ge=0, le=1_000_000)
    total: float = Field(ge=0, le=1_000_000)
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
    from_user_id: str
    to_user_id: str
    amount: float = Field(gt=0, le=1_000_000)


class Settlement(SettlementCreate):
    model_config = ConfigDict(from_attributes=True)

    id: str
    settled_at: datetime


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
