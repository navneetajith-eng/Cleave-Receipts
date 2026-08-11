-- Cover the foreign-key and list queries used by the authoritative API.

BEGIN;

CREATE INDEX IF NOT EXISTS group_members_user_group_idx
    ON public.group_members (user_id, group_id);
CREATE INDEX IF NOT EXISTS groups_created_by_idx
    ON public.groups (created_by);
CREATE INDEX IF NOT EXISTS inbox_items_actor_id_idx
    ON public.inbox_items (actor_id);
CREATE INDEX IF NOT EXISTS inbox_items_group_id_idx
    ON public.inbox_items (group_id);
CREATE INDEX IF NOT EXISTS receipts_group_created_idx
    ON public.receipts (group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS receipts_admin_id_idx
    ON public.receipts (admin_id);
CREATE INDEX IF NOT EXISTS receipt_items_receipt_id_idx
    ON public.receipt_items (receipt_id);
CREATE INDEX IF NOT EXISTS receipt_assignments_user_id_idx
    ON public.receipt_assignments (user_id);
CREATE INDEX IF NOT EXISTS receipt_memories_receipt_id_idx
    ON public.receipt_memories (receipt_id);
CREATE INDEX IF NOT EXISTS receipt_memories_user_id_idx
    ON public.receipt_memories (user_id);
CREATE INDEX IF NOT EXISTS receipt_experiences_user_id_idx
    ON public.receipt_experiences (user_id);
CREATE INDEX IF NOT EXISTS settlements_receipt_id_idx
    ON public.settlements (receipt_id);
CREATE INDEX IF NOT EXISTS settlements_from_user_id_idx
    ON public.settlements (from_user_id);
CREATE INDEX IF NOT EXISTS settlements_to_user_id_idx
    ON public.settlements (to_user_id);

COMMIT;
