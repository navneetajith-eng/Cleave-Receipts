-- Phase 2 migration: make the FastAPI service the only data authority.
-- Run once against the existing Supabase Postgres database before deploying the API.

BEGIN;

ALTER TABLE public.receipts
    ADD COLUMN IF NOT EXISTS discount_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.0;

UPDATE public.profiles
SET username = 'user-' || left(id::text, 8)
WHERE username IS NULL OR btrim(username) = '';

ALTER TABLE public.profiles
    ALTER COLUMN username SET NOT NULL;

CREATE TABLE IF NOT EXISTS public.receipt_memories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    receipt_id UUID REFERENCES public.receipts(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    image_url TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.receipt_memories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated read/write on profiles" ON public.profiles;
DROP POLICY IF EXISTS "Allow authenticated read/write on groups" ON public.groups;
DROP POLICY IF EXISTS "Allow authenticated read/write on group_members" ON public.group_members;
DROP POLICY IF EXISTS "Allow authenticated read/write on receipts" ON public.receipts;
DROP POLICY IF EXISTS "Allow authenticated read/write on receipt_items" ON public.receipt_items;
DROP POLICY IF EXISTS "Allow authenticated read/write on receipt_assignments" ON public.receipt_assignments;
DROP POLICY IF EXISTS "Allow authenticated read/write on settlements" ON public.settlements;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, username)
  VALUES (
    new.id,
    new.email,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE username = split_part(new.email, '@', 1)
      ) THEN left(split_part(new.email, '@', 1), 31) || '-' || left(new.id::text, 8)
      ELSE split_part(new.email, '@', 1)
    END
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

COMMIT;
