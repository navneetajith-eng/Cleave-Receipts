-- Region-aware payment handoff preferences. These columns remain behind the
-- authoritative backend API; migration 004 revokes Data API table access.
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS region_code TEXT,
    ADD COLUMN IF NOT EXISTS venmo_username TEXT,
    ADD COLUMN IF NOT EXISTS upi_id TEXT;

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_region_code_check;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_region_code_check
    CHECK (region_code IS NULL OR region_code IN ('US', 'IN', 'AE'));

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_venmo_username_length_check;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_venmo_username_length_check
    CHECK (venmo_username IS NULL OR char_length(venmo_username) BETWEEN 2 AND 64);

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_upi_id_length_check;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_upi_id_length_check
    CHECK (upi_id IS NULL OR char_length(upi_id) BETWEEN 4 AND 255);
