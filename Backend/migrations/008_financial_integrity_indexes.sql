-- Cover the remaining foreign keys reported by the database advisor.
CREATE INDEX IF NOT EXISTS line_item_assignments_user_id_idx
    ON public.line_item_assignments (user_id);
CREATE INDEX IF NOT EXISTS line_items_receipt_id_idx
    ON public.line_items (receipt_id);

-- A debtor can have at most one active settlement per receipt and payee. This
-- protects against duplicate records from concurrent payment initiation calls.
CREATE UNIQUE INDEX IF NOT EXISTS settlements_one_active_per_debt_idx
    ON public.settlements (receipt_id, from_user_id, to_user_id)
    WHERE status IN ('initiated', 'confirmed');
