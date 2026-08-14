-- Supabase Schema for Cleave Receipt Splitter

-- 1. Profiles Table (Automatically created when users sign up)
-- It's best practice to mirror the auth.users table in a public profiles table
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    username TEXT UNIQUE NOT NULL,
    avatar_url TEXT,
    region_code TEXT CHECK (region_code IS NULL OR region_code IN ('US', 'IN', 'AE')),
    venmo_username TEXT CHECK (venmo_username IS NULL OR char_length(venmo_username) BETWEEN 2 AND 64),
    upi_id TEXT CHECK (upi_id IS NULL OR char_length(upi_id) BETWEEN 4 AND 255),
    aani_id TEXT CHECK (aani_id IS NULL OR char_length(aani_id) BETWEEN 2 AND 128),
    age_band TEXT CHECK (age_band IS NULL OR age_band IN ('under_13', '13_15', '16_17', '18_plus')),
    avatar_visibility TEXT NOT NULL DEFAULT 'shared_groups'
        CHECK (avatar_visibility IN ('everyone', 'shared_groups', 'private')),
    payment_visibility TEXT NOT NULL DEFAULT 'shared_groups'
        CHECK (payment_visibility IN ('everyone', 'shared_groups', 'private')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Trigger to create a profile automatically on signup
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
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = '';

-- Only the auth.users trigger invokes this function.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- Drop trigger if exists, then recreate
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 2. Groups Table
CREATE TABLE IF NOT EXISTS public.groups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_by UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    is_collaborative BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.inbox_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    group_id UUID REFERENCES public.groups(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Group Members Table
CREATE TABLE IF NOT EXISTS public.group_members (
    group_id UUID REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (group_id, user_id)
);

-- 4. Receipts Table
CREATE TABLE IF NOT EXISTS public.receipts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id UUID REFERENCES public.groups(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    admin_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    tax_amount DECIMAL(10, 2) DEFAULT 0.0,
    tip_amount DECIMAL(10, 2) DEFAULT 0.0,
    discount_amount DECIMAL(10, 2) DEFAULT 0.0,
    image_url TEXT,
    client_request_id UUID UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 5. Receipt Items Table
CREATE TABLE IF NOT EXISTS public.receipt_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    receipt_id UUID REFERENCES public.receipts(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 6. Receipt Assignments Table (Who pays for what)
CREATE TABLE IF NOT EXISTS public.receipt_assignments (
    item_id UUID REFERENCES public.receipt_items(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, user_id)
);

-- Snapshot of the members who take part in each receipt. Each person confirms
-- their own claims independently; later group joins do not change old receipts.
CREATE TABLE IF NOT EXISTS public.receipt_participants (
    receipt_id UUID REFERENCES public.receipts(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'submitted')),
    submitted_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (receipt_id, user_id)
);
CREATE INDEX IF NOT EXISTS receipt_participants_status_idx
    ON public.receipt_participants (receipt_id, status, user_id);
CREATE INDEX IF NOT EXISTS receipt_participants_user_id_idx
    ON public.receipt_participants (user_id, receipt_id);

-- Uploaded memories are first-class receipt records, not orphaned storage objects.
CREATE TABLE IF NOT EXISTS public.receipt_memories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    receipt_id UUID REFERENCES public.receipts(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    image_url TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.receipt_experiences (
    receipt_id UUID REFERENCES public.receipts(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (receipt_id, user_id)
);

-- Application data is backend-only. RLS and revoked Data API grants provide two
-- independent barriers against clients bypassing backend authorization checks.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receipt_experiences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inbox_items ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE
    public.profiles,
    public.groups,
    public.group_members,
    public.receipts,
    public.receipt_items,
    public.receipt_assignments,
    public.receipt_participants,
    public.receipt_memories,
    public.receipt_experiences,
    public.inbox_items
FROM anon, authenticated;

-- 7. Settlements Table
CREATE TABLE IF NOT EXISTS public.settlements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    receipt_id UUID REFERENCES public.receipts(id) ON DELETE CASCADE,
    from_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    to_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'rejected')),
    settled_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    confirmed_at TIMESTAMP WITH TIME ZONE,
    reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    CONSTRAINT settlements_payment_claim_key UNIQUE (receipt_id, from_user_id, to_user_id)
);

ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;

REVOKE ALL PRIVILEGES ON TABLE public.settlements
FROM anon, authenticated;

-- Collaboration is served by the authorized backend API. Application tables
-- are intentionally not added to Supabase Realtime's publication.
