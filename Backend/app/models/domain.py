from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship
from app.db.database import Base

class User(Base):
    __tablename__ = "users"
    id = Column(String, primary_key=True, index=True) # Using UUIDs or simple string IDs
    display_name = Column(String, index=True)
    venmo_or_cashapp_handle = Column(String, nullable=True)

class Group(Base):
    __tablename__ = "groups"
    id = Column(String, primary_key=True, index=True)
    name = Column(String, index=True)
    members = relationship("GroupMember", back_populates="group")

class GroupMember(Base):
    __tablename__ = "group_members"
    group_id = Column(String, ForeignKey("groups.id"), primary_key=True)
    user_id = Column(String, ForeignKey("users.id"), primary_key=True)
    group = relationship("Group", back_populates="members")
    user = relationship("User")

class Receipt(Base):
    __tablename__ = "receipts"
    id = Column(String, primary_key=True, index=True)
    group_id = Column(String, ForeignKey("groups.id"))
    vendor_name = Column(String)
    tax = Column(Float, default=0.0)
    tip = Column(Float, default=0.0)
    total = Column(Float, default=0.0)
    image_reference = Column(String, nullable=True)
    created_at = Column(DateTime, default=func.now())
    
    line_items = relationship("LineItem", back_populates="receipt")

class LineItem(Base):
    __tablename__ = "line_items"
    id = Column(String, primary_key=True, index=True)
    receipt_id = Column(String, ForeignKey("receipts.id"))
    description = Column(String)
    price = Column(Float)
    
    receipt = relationship("Receipt", back_populates="line_items")
    assignments = relationship("LineItemAssignment", back_populates="line_item")

class LineItemAssignment(Base):
    __tablename__ = "line_item_assignments"
    line_item_id = Column(String, ForeignKey("line_items.id"), primary_key=True)
    user_id = Column(String, ForeignKey("users.id"), primary_key=True)
    
    line_item = relationship("LineItem", back_populates="assignments")
    user = relationship("User")

class Settlement(Base):
    __tablename__ = "settlements"
    id = Column(String, primary_key=True, index=True)
    receipt_id = Column(String, ForeignKey("receipts.id"))
    from_user_id = Column(String, ForeignKey("users.id"))
    to_user_id = Column(String, ForeignKey("users.id"))
    amount = Column(Float)
    settled_at = Column(DateTime, default=func.now())
