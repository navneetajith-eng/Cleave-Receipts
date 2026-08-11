-- Repair legacy timestamp columns that predate the authoritative API schema.
-- Existing naive values were written as UTC by the original application.

BEGIN;

UPDATE public.profiles
SET created_at = timezone('utc'::text, now())
WHERE created_at IS NULL;

ALTER TABLE public.profiles
    ALTER COLUMN created_at TYPE TIMESTAMPTZ
        USING created_at AT TIME ZONE 'UTC',
    ALTER COLUMN created_at SET DEFAULT timezone('utc'::text, now()),
    ALTER COLUMN created_at SET NOT NULL;

UPDATE public.receipts
SET created_at = timezone('utc'::text, now())
WHERE created_at IS NULL;

ALTER TABLE public.receipts
    ALTER COLUMN created_at TYPE TIMESTAMPTZ
        USING created_at AT TIME ZONE 'UTC',
    ALTER COLUMN created_at SET DEFAULT timezone('utc'::text, now()),
    ALTER COLUMN created_at SET NOT NULL;

UPDATE public.receipt_items
SET created_at = timezone('utc'::text, now())
WHERE created_at IS NULL;

ALTER TABLE public.receipt_items
    ALTER COLUMN created_at TYPE TIMESTAMPTZ
        USING created_at AT TIME ZONE 'UTC',
    ALTER COLUMN created_at SET DEFAULT timezone('utc'::text, now()),
    ALTER COLUMN created_at SET NOT NULL;

UPDATE public.settlements
SET settled_at = timezone('utc'::text, now())
WHERE settled_at IS NULL;

ALTER TABLE public.settlements
    ALTER COLUMN settled_at TYPE TIMESTAMPTZ
        USING settled_at AT TIME ZONE 'UTC',
    ALTER COLUMN settled_at SET DEFAULT timezone('utc'::text, now()),
    ALTER COLUMN settled_at SET NOT NULL;

COMMIT;
