from typing import List, Dict
from sqlalchemy.orm import Session
from app.models import domain, schemas

def calculate_balances(db: Session, receipt_id: str) -> List[schemas.Balance]:
    receipt = db.query(domain.Receipt).filter(domain.Receipt.id == receipt_id).first()
    if not receipt:
        return []

    line_items = db.query(domain.LineItem).filter(domain.LineItem.receipt_id == receipt_id).all()
    
    # Pre-calculate subtotal
    subtotal = sum(item.price for item in line_items)
    if subtotal == 0:
        return []

    # Map user_id to their items total
    user_item_totals: Dict[str, float] = {}
    
    for item in line_items:
        # Get assignments for this item
        assignments = db.query(domain.LineItemAssignment).filter(domain.LineItemAssignment.line_item_id == item.id).all()
        if not assignments:
            continue
            
        split_price = item.price / len(assignments)
        
        for assignment in assignments:
            user_id = assignment.user_id
            user_item_totals[user_id] = user_item_totals.get(user_id, 0.0) + split_price

    balances = []
    for user_id, items_total in user_item_totals.items():
        proportion = items_total / subtotal
        tax_share = receipt.tax * proportion
        tip_share = receipt.tip * proportion
        total_owed = items_total + tax_share + tip_share
        
        # Rounding to 2 decimal places for money
        balances.append(schemas.Balance(
            user_id=user_id,
            items_total=round(items_total, 2),
            tax_share=round(tax_share, 2),
            tip_share=round(tip_share, 2),
            total_owed=round(total_owed, 2)
        ))
        
    return balances
