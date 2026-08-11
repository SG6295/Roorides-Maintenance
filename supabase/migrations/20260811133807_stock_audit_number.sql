-- A human-readable reference for each stock audit (MAIN-30 follow-up).
--
-- An audit is a document people refer to after the fact — "the August Mahadevpura count"
-- — and a uuid is useless for that. Numbering is sequential across all workshops, matching
-- job_cards.job_card_number rather than restarting per location, so a reference is
-- unambiguous on its own. Displayed as AUD-<n>.

ALTER TABLE public.stock_audits ADD COLUMN IF NOT EXISTS audit_number integer;

-- Backfill in the order audits were started so the numbering reads chronologically
-- rather than in whatever order the rows happen to sit on disk.
WITH numbered AS (
    SELECT id, row_number() OVER (ORDER BY started_at, id) AS n
    FROM   public.stock_audits
    WHERE  audit_number IS NULL
)
UPDATE public.stock_audits a
SET    audit_number = numbered.n
FROM   numbered
WHERE  numbered.id = a.id;

CREATE SEQUENCE IF NOT EXISTS public.stock_audits_audit_number_seq
    OWNED BY public.stock_audits.audit_number;

-- Start the sequence past anything the backfill just assigned. On a fresh database the
-- backfill is a no-op and this simply starts at 1.
SELECT setval(
    'public.stock_audits_audit_number_seq',
    COALESCE((SELECT max(audit_number) FROM public.stock_audits), 0) + 1,
    false
);

ALTER TABLE public.stock_audits
    ALTER COLUMN audit_number SET DEFAULT nextval('public.stock_audits_audit_number_seq');

ALTER TABLE public.stock_audits
    ALTER COLUMN audit_number SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS stock_audits_number_key
    ON public.stock_audits (audit_number);

COMMENT ON COLUMN public.stock_audits.audit_number IS
    'Human-readable reference, shown in the app as AUD-<n>. Sequential across all workshops.';
