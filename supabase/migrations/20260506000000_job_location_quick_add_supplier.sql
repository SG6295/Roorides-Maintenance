BEGIN;

-- ── 1. SUPPLIERS: drop NOT NULL on 15 columns ─────────────────────────────
--    Allows quick-add rows that only collect the 5 core fields.

ALTER TABLE suppliers
  ALTER COLUMN email                   DROP NOT NULL,
  ALTER COLUMN entity_type             DROP NOT NULL,
  ALTER COLUMN accounts_contact_number DROP NOT NULL,
  ALTER COLUMN pan_number              DROP NOT NULL,
  ALTER COLUMN pan_copy_url            DROP NOT NULL,
  ALTER COLUMN gstin                   DROP NOT NULL,
  ALTER COLUMN gst_registration_type   DROP NOT NULL,
  ALTER COLUMN bank_name               DROP NOT NULL,
  ALTER COLUMN bank_branch             DROP NOT NULL,
  ALTER COLUMN account_holder_name     DROP NOT NULL,
  ALTER COLUMN account_number          DROP NOT NULL,
  ALTER COLUMN ifsc_code               DROP NOT NULL,
  ALTER COLUMN cancelled_cheque_url    DROP NOT NULL,
  ALTER COLUMN years_of_experience     DROP NOT NULL,
  ALTER COLUMN payment_terms_days      DROP NOT NULL,
  ALTER COLUMN submitted_by            DROP NOT NULL;

-- ── 2. SUPPLIERS: add audit columns ───────────────────────────────────────

ALTER TABLE suppliers
  ADD COLUMN created_via text NOT NULL DEFAULT 'registration'
    CONSTRAINT suppliers_created_via_check
    CHECK (created_via IN ('registration', 'quick_add')),
  ADD COLUMN created_by uuid NULL REFERENCES users(id);

-- ── 3. BACKFILL existing supplier row ─────────────────────────────────────

UPDATE suppliers
  SET created_via = 'registration'
  WHERE created_via IS DISTINCT FROM 'registration';

-- ── 4. JOB_CARDS: add supplier_id + invoice_url, drop vendor_name ─────────

ALTER TABLE job_cards
  ADD COLUMN supplier_id uuid NULL REFERENCES suppliers(id) ON DELETE SET NULL,
  ADD COLUMN invoice_url text NULL;

ALTER TABLE job_cards
  DROP COLUMN vendor_name;

-- ── 5. JOB_CARDS: enforce invoice upload at DB level ──────────────────────
--    An Outsource job card cannot be marked Completed without an invoice URL.

ALTER TABLE job_cards
  ADD CONSTRAINT outsource_completion_requires_invoice
  CHECK (
    status != 'Completed'
    OR type != 'Outsource'
    OR invoice_url IS NOT NULL
  );

-- ── Verification (runs inside transaction so you see the effect) ───────────

SELECT 'suppliers columns' AS check_name,
  column_name, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'suppliers'
ORDER BY ordinal_position;

SELECT 'job_cards columns' AS check_name,
  column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'job_cards'
ORDER BY ordinal_position;

SELECT 'supplier backfill' AS check_name,
  id, entity_name, created_via, created_by
FROM suppliers;

ROLLBACK; -- swap to COMMIT once output looks correct