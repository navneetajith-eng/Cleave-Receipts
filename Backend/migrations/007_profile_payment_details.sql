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

-- A receipt's currency is immutable financial context. It must never be inferred
-- from whichever region a user currently has selected in the iOS app.
ALTER TABLE public.receipts
    ADD COLUMN IF NOT EXISTS currency_code TEXT NOT NULL DEFAULT 'USD';
ALTER TABLE public.receipts
    DROP CONSTRAINT IF EXISTS receipts_currency_code_check;
ALTER TABLE public.receipts
    ADD CONSTRAINT receipts_currency_code_check
    CHECK (currency_code IN ('USD', 'INR', 'AED'));

-- External payment apps cannot prove completion to Cleave. New settlements start
-- as initiated and become confirmed only after an explicit user confirmation.
ALTER TABLE public.settlements
    ADD COLUMN IF NOT EXISTS currency_code TEXT NOT NULL DEFAULT 'USD',
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'initiated',
    ADD COLUMN IF NOT EXISTS initiated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMPTZ;
UPDATE public.settlements
SET status = 'confirmed',
    initiated_at = COALESCE(settled_at, initiated_at),
    confirmed_at = COALESCE(confirmed_at, settled_at)
WHERE settled_at IS NOT NULL AND confirmed_at IS NULL;
ALTER TABLE public.settlements
    DROP CONSTRAINT IF EXISTS settlements_currency_code_check;
ALTER TABLE public.settlements
    ADD CONSTRAINT settlements_currency_code_check
    CHECK (currency_code IN ('USD', 'INR', 'AED'));
ALTER TABLE public.settlements
    DROP CONSTRAINT IF EXISTS settlements_status_check;
ALTER TABLE public.settlements
    ADD CONSTRAINT settlements_status_check
    CHECK (status IN ('initiated', 'confirmed', 'cancelled'));
