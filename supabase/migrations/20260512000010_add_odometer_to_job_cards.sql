BEGIN;

  ALTER TABLE public.job_cards
    ADD COLUMN odometer integer CHECK (odometer IS NULL OR odometer >= 0);

  -- Verify
  SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'job_cards'
    AND column_name = 'odometer';

COMMIT;
