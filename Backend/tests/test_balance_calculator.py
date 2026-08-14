import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from app.db.database import Base
from app.models import domain
from app.services.balance_calculator import calculate_balances
import uuid

SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"
USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
GROUP_1 = "00000000-0000-0000-0000-000000000101"
RECEIPT_1 = "00000000-0000-0000-0000-000000000201"
ITEM_1 = "00000000-0000-0000-0000-000000000301"
ITEM_2 = "00000000-0000-0000-0000-000000000302"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

@pytest.fixture()
def db_session():
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)

def test_calculate_balances(db_session):
    # Setup test data
    user1 = domain.Profile(id=USER_1, email="alice@example.com", username="alice")
    user2 = domain.Profile(id=USER_2, email="bob@example.com", username="bob")
    db_session.add_all([user1, user2])

    group = domain.Group(id=GROUP_1, name="Test Group", created_by=USER_1)
    db_session.add(group)

    receipt = domain.Receipt(id=RECEIPT_1, group_id=GROUP_1, title="Test Receipt", admin_id=USER_1,
                             tax_amount=10.0, tip_amount=20.0, discount_amount=5.0)
    db_session.add(receipt)

    item1 = domain.ReceiptItem(id=ITEM_1, receipt_id=RECEIPT_1, name="Burger", price=40.0)  # Alice only
    item2 = domain.ReceiptItem(id=ITEM_2, receipt_id=RECEIPT_1, name="Pizza", price=60.0)   # Split by Alice and Bob
    db_session.add_all([item1, item2])

    assign1 = domain.ReceiptAssignment(item_id=ITEM_1, user_id=USER_1)
    assign2 = domain.ReceiptAssignment(item_id=ITEM_2, user_id=USER_1)
    assign3 = domain.ReceiptAssignment(item_id=ITEM_2, user_id=USER_2)
    db_session.add_all([assign1, assign2, assign3])

    db_session.commit()

    balances = calculate_balances(db_session, RECEIPT_1)

    assert len(balances) == 2

    # Alice items: 40 + 30 = 70
    # Bob items: 30
    # Subtotal = 100
    # Alice proportion: 70/100 = 0.7
    # Bob proportion: 30/100 = 0.3

    # Alice tax: 0.7 * 10 = 7
    # Alice tip: 0.7 * 20 = 14
    # Alice discount: 0.7 * 5 = 3.5
    # Alice total: 70 + 7 + 14 - 3.5 = 87.5

    # Bob tax: 0.3 * 10 = 3
    # Bob tip: 0.3 * 20 = 6
    # Bob discount: 0.3 * 5 = 1.5
    # Bob total: 30 + 3 + 6 - 1.5 = 37.5

    balances_by_user = {b.user_id: b for b in balances}

    assert balances_by_user[USER_1].items_total == 70.0
    assert balances_by_user[USER_1].tax_share == 7.0
    assert balances_by_user[USER_1].tip_share == 14.0
    assert balances_by_user[USER_1].discount_share == 3.5
    assert balances_by_user[USER_1].total_owed == 87.5

    assert balances_by_user[USER_2].items_total == 30.0
    assert balances_by_user[USER_2].tax_share == 3.0
    assert balances_by_user[USER_2].tip_share == 6.0
    assert balances_by_user[USER_2].discount_share == 1.5
    assert balances_by_user[USER_2].total_owed == 37.5

def test_calculate_balances_without_discount(db_session):
    user1 = domain.Profile(id=USER_1, email="alice@example.com", username="alice")
    db_session.add(user1)

    group = domain.Group(id=GROUP_1, name="Test Group", created_by=USER_1)
    db_session.add(group)

    receipt = domain.Receipt(id=RECEIPT_1, group_id=GROUP_1, title="Test Receipt", admin_id=USER_1,
                             tax_amount=10.0, tip_amount=0.0, discount_amount=0.0)
    db_session.add(receipt)

    item1 = domain.ReceiptItem(id=ITEM_1, receipt_id=RECEIPT_1, name="Burger", price=100.0)
    db_session.add(item1)

    db_session.add(domain.ReceiptAssignment(item_id=ITEM_1, user_id=USER_1))

    db_session.commit()

    balances = calculate_balances(db_session, RECEIPT_1)

    assert len(balances) == 1
    b = balances[0]
    assert b.items_total == 100.0
    assert b.tax_share == 10.0
    assert b.discount_share == 0.0
    assert b.total_owed == 110.0

def test_calculate_balances_returns_empty_for_unknown_receipt(db_session):
    assert calculate_balances(db_session, str(uuid.uuid4())) == []


def test_calculate_balances_preserves_every_cent(db_session):
    users = [
        domain.Profile(id=USER_1, email="one@example.com", username="one"),
        domain.Profile(id=USER_2, email="two@example.com", username="two"),
        domain.Profile(id=USER_3, email="three@example.com", username="three"),
    ]
    db_session.add_all(users)
    db_session.add(domain.Group(id=GROUP_1, name="Penny", created_by=USER_1))
    db_session.add(
        domain.Receipt(
            id=RECEIPT_1,
            group_id=GROUP_1,
            title="Penny split",
            admin_id=USER_1,
            tax_amount=0.01,
            tip_amount=0.01,
            discount_amount=0,
        )
    )
    db_session.add(
        domain.ReceiptItem(
            id=ITEM_1,
            receipt_id=RECEIPT_1,
            name="Shared",
            price=10.00,
        )
    )
    db_session.add_all(
        domain.ReceiptAssignment(item_id=ITEM_1, user_id=user_id)
        for user_id in (USER_1, USER_2, USER_3)
    )
    db_session.commit()

    balances = calculate_balances(db_session, RECEIPT_1)

    assert round(sum(balance.items_total for balance in balances), 2) == 10.00
    assert round(sum(balance.tax_share for balance in balances), 2) == 0.01
    assert round(sum(balance.tip_share for balance in balances), 2) == 0.01
    assert round(sum(balance.total_owed for balance in balances), 2) == 10.02


def test_balance_query_count_does_not_grow_with_item_count(db_session):
    db_session.add(domain.Profile(id=USER_1, email="bounded@example.com", username="bounded"))
    db_session.add(domain.Group(id=GROUP_1, name="Bounded", created_by=USER_1))
    db_session.add(
        domain.Receipt(
            id=RECEIPT_1,
            group_id=GROUP_1,
            title="Many items",
            admin_id=USER_1,
            tax_amount=1,
            tip_amount=1,
            discount_amount=0,
        )
    )
    for index in range(12):
        item_id = f"00000000-0000-0000-0000-{index + 400:012d}"
        db_session.add(
            domain.ReceiptItem(
                id=item_id,
                receipt_id=RECEIPT_1,
                name=f"Item {index}",
                price=1,
            )
        )
        db_session.add(domain.ReceiptAssignment(item_id=item_id, user_id=USER_1))
    db_session.commit()
    db_session.expire_all()

    query_count = 0

    def count_query(*_args):
        nonlocal query_count
        query_count += 1

    event.listen(engine, "before_cursor_execute", count_query)
    try:
        balances = calculate_balances(db_session, RECEIPT_1)
    finally:
        event.remove(engine, "before_cursor_execute", count_query)

    assert balances[0].items_total == 12
    assert query_count <= 3
