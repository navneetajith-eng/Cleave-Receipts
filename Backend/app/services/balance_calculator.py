from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP

from sqlalchemy.orm import Session, selectinload

from app.models import domain, schemas


CENT = Decimal("0.01")


def _cents(value: object) -> int:
    return int((Decimal(str(value)) / CENT).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def _money(cents: int) -> float:
    return float(Decimal(cents) * CENT)


def _allocate_cents(total_cents: int, weights: dict[str, int]) -> dict[str, int]:
    """Allocate an amount by weight without creating or losing a cent."""
    positive_weights = {key: value for key, value in weights.items() if value > 0}
    weight_total = sum(positive_weights.values())
    if total_cents <= 0 or weight_total <= 0:
        return {key: 0 for key in weights}

    allocation: dict[str, int] = {}
    remainders: list[tuple[int, str]] = []
    for user_id, weight in positive_weights.items():
        numerator = total_cents * weight
        allocation[user_id] = numerator // weight_total
        remainders.append((numerator % weight_total, user_id))

    cents_left = total_cents - sum(allocation.values())
    for _, user_id in sorted(remainders, key=lambda pair: (-pair[0], pair[1]))[:cents_left]:
        allocation[user_id] += 1

    return {key: allocation.get(key, 0) for key in weights}


def calculate_balances(db: Session, receipt_id: str) -> list[schemas.Balance]:
    receipt_amounts = (
        db.query(
            domain.Receipt.tax_amount,
            domain.Receipt.tip_amount,
            domain.Receipt.discount_amount,
        )
        .filter(domain.Receipt.id == receipt_id)
        .first()
    )
    if receipt_amounts is None:
        return []
    tax_amount, tip_amount, discount_amount = receipt_amounts

    line_items = (
        db.query(domain.ReceiptItem)
        .options(selectinload(domain.ReceiptItem.assignments))
        .filter(domain.ReceiptItem.receipt_id == receipt_id)
        .all()
    )
    if not line_items:
        return []

    user_item_cents: dict[str, int] = {}
    user_items: dict[str, list[schemas.BalanceItem]] = {}
    for item in line_items:
        user_ids = sorted(
            assignment.user_id
            for assignment in item.assignments
        )
        if not user_ids:
            continue
        item_cents = _cents(item.price)
        base, remainder = divmod(item_cents, len(user_ids))
        for index, user_id in enumerate(user_ids):
            share = base + (1 if index < remainder else 0)
            user_item_cents[user_id] = user_item_cents.get(user_id, 0) + share
            user_items.setdefault(user_id, []).append(
                schemas.BalanceItem(item_id=item.id, name=item.name, amount=_money(share))
            )

    if not user_item_cents:
        return []

    tax = _allocate_cents(_cents(tax_amount), user_item_cents)
    tip = _allocate_cents(_cents(tip_amount), user_item_cents)
    discount = _allocate_cents(_cents(discount_amount), user_item_cents)

    return [
        schemas.Balance(
            user_id=user_id,
            items=user_items.get(user_id, []),
            items_total=_money(items_total),
            tax_share=_money(tax[user_id]),
            tip_share=_money(tip[user_id]),
            discount_share=_money(discount[user_id]),
            total_owed=_money(
                items_total + tax[user_id] + tip[user_id] - discount[user_id]
            ),
        )
        for user_id, items_total in sorted(user_item_cents.items())
    ]
