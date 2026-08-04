from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

class UserBase(BaseModel):
    display_name: str
    venmo_or_cashapp_handle: Optional[str] = None

class UserCreate(UserBase):
    id: str

class User(UserBase):
    id: str
    class Config:
        from_attributes = True

class GroupBase(BaseModel):
    name: str

class GroupCreate(GroupBase):
    id: str

class Group(GroupBase):
    id: str
    members: List[User] = []
    class Config:
        from_attributes = True

class LineItemBase(BaseModel):
    description: str
    price: float

class LineItem(LineItemBase):
    id: str
    receipt_id: str
    class Config:
        from_attributes = True

class ReceiptBase(BaseModel):
    vendor_name: str
    tax: float
    tip: float
    total: float
    image_reference: Optional[str] = None

class ReceiptCreate(ReceiptBase):
    id: str
    group_id: str

class Receipt(ReceiptBase):
    id: str
    group_id: str
    created_at: datetime
    line_items: List[LineItem] = []
    class Config:
        from_attributes = True

class ParsedReceipt(BaseModel):
    vendor_name: str
    tax: float
    tip: float
    total: float
    line_items: List[LineItemBase]

class AssignmentUpdate(BaseModel):
    user_ids: List[str]

class Balance(BaseModel):
    user_id: str
    items_total: float
    tax_share: float
    tip_share: float
    total_owed: float

class SettlementCreate(BaseModel):
    id: str
    receipt_id: str
    from_user_id: str
    to_user_id: str
    amount: float

class Settlement(SettlementCreate):
    settled_at: datetime
    class Config:
        from_attributes = True
