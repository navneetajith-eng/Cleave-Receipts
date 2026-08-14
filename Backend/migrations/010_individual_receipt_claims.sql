-- Snapshot receipt participants so each member can submit their own item claims.
-- The table stays backend-only, matching migration 004.

CREATE TABLE IF NOT EXISTS public.receipt_participants (
    receipt_id UUID NOT NULL REFERENCES public.receipts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (receipt_id, user_id),
    CONSTRAINT receipt_participants_status_check
        CHECK (status IN ('pending', 'submitted'))
);

-- Existing receipts inherit the group membership that exists at migration time.
-- Existing assigned users are treated as submitted so released receipts do not
-- regress to a wholly pending state.
INSERT INTO public.receipt_participants (receipt_id, user_id, status, submitted_at)
SELECT r.id,
       gm.user_id,
       CASE WHEN EXISTS (
           SELECT 1
           FROM public.receipt_items ri
           JOIN public.receipt_assignments ra ON ra.item_id = ri.id
           WHERE ri.receipt_id = r.id AND ra.user_id = gm.user_id
       ) THEN 'submitted' ELSE 'pending' END,
       CASE WHEN EXISTS (
           SELECT 1
           FROM public.receipt_items ri
           JOIN public.receipt_assignments ra ON ra.item_id = ri.id
           WHERE ri.receipt_id = r.id AND ra.user_id = gm.user_id
       ) THEN now() ELSE NULL END
FROM public.receipts r
JOIN public.group_members gm ON gm.group_id = r.group_id
ON CONFLICT (receipt_id, user_id) DO NOTHING;

CREATE INDEX IF NOT EXISTS receipt_participants_status_idx
    ON public.receipt_participants (receipt_id, status, user_id);
CREATE INDEX IF NOT EXISTS receipt_participants_user_id_idx
    ON public.receipt_participants (user_id, receipt_id);

ALTER TABLE public.receipt_participants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.receipt_participants FROM anon, authenticated, PUBLIC;
