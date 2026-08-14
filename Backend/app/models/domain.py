from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, Numeric, String, UniqueConstraint, Uuid, func
from sqlalchemy.orm import relationship

from app.db.database import Base


class Profile(Base):
    __tablename__ = "profiles"

    id = Column(Uuid(as_uuid=False), primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    username = Column(String, unique=True, index=True, nullable=False)
    display_name = Column(String(80), nullable=True)
    avatar_url = Column(String, nullable=True)
    region_code = Column(String(2), nullable=True)
    venmo_username = Column(String(64), nullable=True)
    upi_id = Column(String(255), nullable=True)
    aani_id = Column(String(128), nullable=True)
    age_band = Column(String(16), nullable=True)
    avatar_visibility = Column(String(20), default="shared_groups", nullable=False)
    payment_visibility = Column(String(20), default="shared_groups", nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)


class Group(Base):
    __tablename__ = "groups"

    id = Column(Uuid(as_uuid=False), primary_key=True, index=True)
    name = Column(String, index=True, nullable=False)
    created_by = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False)
    is_collaborative = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)

    members = relationship(
        "GroupMember",
        back_populates="group",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    receipts = relationship(
        "Receipt",
        back_populates="group",
        cascade="all, delete-orphan",
    )


class GroupMember(Base):
    __tablename__ = "group_members"

    group_id = Column(Uuid(as_uuid=False), ForeignKey("groups.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True, index=True)
    joined_at = Column(DateTime, default=func.now(), nullable=False)

    group = relationship("Group", back_populates="members")
    user = relationship("Profile", lazy="joined")


class Receipt(Base):
    __tablename__ = "receipts"

    id = Column(Uuid(as_uuid=False), primary_key=True, index=True)
    group_id = Column(Uuid(as_uuid=False), ForeignKey("groups.id", ondelete="CASCADE"), nullable=False)
    title = Column(String, nullable=False)
    admin_id = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False)
    currency_code = Column(String(3), default="USD", nullable=False)
    tax_amount = Column(Numeric(12, 2), default=0, nullable=False)
    tip_amount = Column(Numeric(12, 2), default=0, nullable=False)
    discount_amount = Column(Numeric(12, 2), default=0, nullable=False)
    image_url = Column(String, nullable=True)
    client_request_id = Column(Uuid(as_uuid=False), unique=True, nullable=True, index=True)
    created_at = Column(DateTime, default=func.now(), nullable=False)

    group = relationship("Group", back_populates="receipts")
    items = relationship(
        "ReceiptItem",
        back_populates="receipt",
        cascade="all, delete-orphan",
        lazy="selectin",
    )
    memories = relationship(
        "ReceiptMemory",
        back_populates="receipt",
        cascade="all, delete-orphan",
    )
    experiences = relationship(
        "ReceiptExperience",
        back_populates="receipt",
        cascade="all, delete-orphan",
    )
    participants = relationship(
        "ReceiptParticipant",
        back_populates="receipt",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class ReceiptItem(Base):
    __tablename__ = "receipt_items"

    id = Column(Uuid(as_uuid=False), primary_key=True, index=True)
    receipt_id = Column(Uuid(as_uuid=False), ForeignKey("receipts.id", ondelete="CASCADE"), nullable=False)
    name = Column(String, nullable=False)
    price = Column(Numeric(12, 2), nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)

    receipt = relationship("Receipt", back_populates="items")
    assignments = relationship(
        "ReceiptAssignment",
        back_populates="item",
        cascade="all, delete-orphan",
    )

    @property
    def assigned_user_ids(self) -> list[str]:
        return sorted(assignment.user_id for assignment in self.assignments)


class ReceiptAssignment(Base):
    __tablename__ = "receipt_assignments"

    item_id = Column(Uuid(as_uuid=False), ForeignKey("receipt_items.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True)

    item = relationship("ReceiptItem", back_populates="assignments")
    user = relationship("Profile")


class ReceiptParticipant(Base):
    __tablename__ = "receipt_participants"

    receipt_id = Column(Uuid(as_uuid=False), ForeignKey("receipts.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True, index=True)
    status = Column(String(16), default="pending", nullable=False)
    submitted_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=func.now(), nullable=False)

    receipt = relationship("Receipt", back_populates="participants")
    user = relationship("Profile", lazy="joined")


class ReceiptMemory(Base):
    __tablename__ = "receipt_memories"

    id = Column(Uuid(as_uuid=False), primary_key=True, index=True)
    receipt_id = Column(Uuid(as_uuid=False), ForeignKey("receipts.id", ondelete="CASCADE"), nullable=False)
    user_id = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False)
    image_url = Column(String, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)

    receipt = relationship("Receipt", back_populates="memories")
    user = relationship("Profile")


class ReceiptExperience(Base):
    __tablename__ = "receipt_experiences"

    receipt_id = Column(Uuid(as_uuid=False), ForeignKey("receipts.id", ondelete="CASCADE"), primary_key=True)
    user_id = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="CASCADE"), primary_key=True)
    rating = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now(), nullable=False)

    receipt = relationship("Receipt", back_populates="experiences")
    user = relationship("Profile")


class Settlement(Base):
    __tablename__ = "settlements"
    __table_args__ = (
        UniqueConstraint("receipt_id", "from_user_id", "to_user_id", name="settlements_payment_claim_key"),
    )

    id = Column(Uuid(as_uuid=False), primary_key=True, index=True)
    receipt_id = Column(Uuid(as_uuid=False), ForeignKey("receipts.id", ondelete="CASCADE"), nullable=False)
    from_user_id = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False)
    to_user_id = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    status = Column(String(16), default="pending", nullable=False)
    settled_at = Column(DateTime, default=func.now(), nullable=False)
    confirmed_at = Column(DateTime, nullable=True)
    reviewed_by = Column(
        Uuid(as_uuid=False),
        ForeignKey("profiles.id", ondelete="SET NULL"),
        nullable=True,
    )


class InboxItem(Base):
    __tablename__ = "inbox_items"

    id = Column(Uuid(as_uuid=False), primary_key=True, index=True)
    user_id = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="CASCADE"), nullable=False, index=True)
    actor_id = Column(Uuid(as_uuid=False), ForeignKey("profiles.id", ondelete="SET NULL"), nullable=True)
    group_id = Column(Uuid(as_uuid=False), ForeignKey("groups.id", ondelete="CASCADE"), nullable=True)
    kind = Column(String, nullable=False)
    title = Column(String, nullable=False)
    body = Column(String, nullable=False)
    is_read = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=func.now(), nullable=False)
