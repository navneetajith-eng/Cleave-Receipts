-- Makes receipt image retries safe. A device reuses its locally generated
-- request UUID, so a lost response cannot create a duplicate receipt.

ALTER TABLE public.receipts
    ADD COLUMN IF NOT EXISTS client_request_id UUID;

CREATE UNIQUE INDEX IF NOT EXISTS receipts_client_request_id_key
    ON public.receipts (client_request_id)
    WHERE client_request_id IS NOT NULL;
