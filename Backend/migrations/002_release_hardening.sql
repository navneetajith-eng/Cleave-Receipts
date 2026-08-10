-- Phase 3 migration: private receipt media, per-user experiences, and
-- account-deletion cascades. Run after 001_authoritative_api.sql.

BEGIN;

CREATE TABLE IF NOT EXISTS public.receipt_experiences (
    receipt_id UUID REFERENCES public.receipts(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (receipt_id, user_id)
);

ALTER TABLE public.receipt_experiences ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.groups DROP CONSTRAINT IF EXISTS groups_created_by_fkey;
ALTER TABLE public.groups
    ADD CONSTRAINT groups_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.receipts DROP CONSTRAINT IF EXISTS receipts_admin_id_fkey;
ALTER TABLE public.receipts
    ADD CONSTRAINT receipts_admin_id_fkey
    FOREIGN KEY (admin_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_from_user_id_fkey;
ALTER TABLE public.settlements
    ADD CONSTRAINT settlements_from_user_id_fkey
    FOREIGN KEY (from_user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_to_user_id_fkey;
ALTER TABLE public.settlements
    ADD CONSTRAINT settlements_to_user_id_fkey
    FOREIGN KEY (to_user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

COMMIT;
