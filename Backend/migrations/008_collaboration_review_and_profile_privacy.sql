-- Receipt-scoped administration, reviewable payment marks, and complete
-- profile preferences. Application tables remain backend-only (migration 004).

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS aani_id TEXT,
    ADD COLUMN IF NOT EXISTS age_band TEXT,
    ADD COLUMN IF NOT EXISTS avatar_visibility TEXT NOT NULL DEFAULT 'shared_groups',
    ADD COLUMN IF NOT EXISTS payment_visibility TEXT NOT NULL DEFAULT 'shared_groups';

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_aani_id_length_check;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_aani_id_length_check
    CHECK (aani_id IS NULL OR char_length(aani_id) BETWEEN 2 AND 128);

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_age_band_check;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_age_band_check
    CHECK (age_band IS NULL OR age_band IN ('under_13', '13_15', '16_17', '18_plus'));

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_avatar_visibility_check;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_avatar_visibility_check
    CHECK (avatar_visibility IN ('everyone', 'shared_groups', 'private'));

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_payment_visibility_check;
ALTER TABLE public.profiles
    ADD CONSTRAINT profiles_payment_visibility_check
    CHECK (payment_visibility IN ('everyone', 'shared_groups', 'private'));

ALTER TABLE public.settlements
    ADD COLUMN IF NOT EXISTS status TEXT,
    ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- Records created before this review workflow represented completed payments.
UPDATE public.settlements
SET status = 'confirmed', confirmed_at = COALESCE(confirmed_at, settled_at)
WHERE status IS NULL;

ALTER TABLE public.settlements
    ALTER COLUMN status SET DEFAULT 'pending',
    ALTER COLUMN status SET NOT NULL;

ALTER TABLE public.settlements
    DROP CONSTRAINT IF EXISTS settlements_status_check;
ALTER TABLE public.settlements
    ADD CONSTRAINT settlements_status_check
    CHECK (status IN ('pending', 'confirmed', 'rejected'));

-- Keep the newest historical record before enforcing idempotent payment marks.
WITH ranked AS (
    SELECT id,
           row_number() OVER (
               PARTITION BY receipt_id, from_user_id, to_user_id
               ORDER BY settled_at DESC, id DESC
           ) AS duplicate_rank
    FROM public.settlements
)
DELETE FROM public.settlements
WHERE id IN (SELECT id FROM ranked WHERE duplicate_rank > 1);

ALTER TABLE public.settlements
    DROP CONSTRAINT IF EXISTS settlements_payment_claim_key;
ALTER TABLE public.settlements
    ADD CONSTRAINT settlements_payment_claim_key
    UNIQUE (receipt_id, from_user_id, to_user_id);

CREATE INDEX IF NOT EXISTS settlements_status_idx
    ON public.settlements (receipt_id, status, settled_at DESC);

