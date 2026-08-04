import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.db.database import Base
from app.models import domain
from app.services.balance_calculator import calculate_balances
import uuid

SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"

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
    user1 = domain.User(id="u1", display_name="Alice")
    user2 = domain.User(id="u2", display_name="Bob")
    db_session.add_all([user1, user2])
    
    group = domain.Group(id="g1", name="Test Group")
    db_session.add(group)
    
    receipt = domain.Receipt(id="r1", group_id="g1", tax=10.0, tip=20.0, total=130.0)
    db_session.add(receipt)
    
    item1 = domain.LineItem(id="i1", receipt_id="r1", price=40.0) # Alice only
    item2 = domain.LineItem(id="i2", receipt_id="r1", price=60.0) # Split by Alice and Bob
    db_session.add_all([item1, item2])
    
    assign1 = domain.LineItemAssignment(line_item_id="i1", user_id="u1")
    assign2 = domain.LineItemAssignment(line_item_id="i2", user_id="u1")
    assign3 = domain.LineItemAssignment(line_item_id="i2", user_id="u2")
    db_session.add_all([assign1, assign2, assign3])
    
    db_session.commit()
    
    balances = calculate_balances(db_session, "r1")
    
    assert len(balances) == 2
    
    # Alice items: 40 + 30 = 70
    # Bob items: 30
    # Subtotal = 100
    # Alice proportion: 70/100 = 0.7
    # Bob proportion: 30/100 = 0.3
    
    # Alice tax: 0.7 * 10 = 7
    # Alice tip: 0.7 * 20 = 14
    # Alice total: 70 + 7 + 14 = 91
    
    # Bob tax: 0.3 * 10 = 3
    # Bob tip: 0.3 * 20 = 6
    # Bob total: 30 + 3 + 6 = 39
    
    balances_by_user = {b.user_id: b for b in balances}
    
    assert balances_by_user["u1"].items_total == 70.0
    assert balances_by_user["u1"].tax_share == 7.0
    assert balances_by_user["u1"].tip_share == 14.0
    assert balances_by_user["u1"].total_owed == 91.0
    
    assert balances_by_user["u2"].items_total == 30.0
    assert balances_by_user["u2"].tax_share == 3.0
    assert balances_by_user["u2"].tip_share == 6.0
    assert balances_by_user["u2"].total_owed == 39.0
