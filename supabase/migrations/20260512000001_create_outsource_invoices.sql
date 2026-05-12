BEGIN;

-- ── Outsource Invoices — Phase 1 (1/3) ───────────────────────────────────────
-- Creates outsource_invoices and outsource_invoice_payments tables.
--
-- All invoice fields are nullable so that partial drafts can be saved
-- incrementally during the job card workflow. Completeness is enforced
-- by the closure handler in the frontend, not by DB constraints.

-- ── Reusable updated_at trigger function ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- ── outsource_invoices ────────────────────────────────────────────────────────
-- One row per outsource job card. Created (as a draft) when the user first
-- saves any invoice field; finalized when the job card is completed.

CREATE TABLE public.outsource_invoices (
    id                  uuid            PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_card_id         uuid            UNIQUE REFERENCES public.job_cards(id) ON DELETE CASCADE,
    date_of_activity    date,
    invoice_no          text,
    paid_by             text            CHECK (paid_by IN ('Accounts', 'Nithin', 'Manjunath')),
    invoice_value       numeric(12,2),
    approved_amount     numeric(12,2),
    advance_amount      numeric(12,2),
    payment_status      text            CHECK (payment_status IN ('Approved', 'Hold', 'Reject')),
    payby_date          date,
    created_by          uuid            REFERENCES public.users(id),
    created_at          timestamptz     NOT NULL DEFAULT now(),
    updated_at          timestamptz     NOT NULL DEFAULT now()
);

CREATE INDEX outsource_invoices_job_card_id_idx   ON public.outsource_invoices(job_card_id);
CREATE INDEX outsource_invoices_payment_status_idx ON public.outsource_invoices(payment_status);
CREATE INDEX outsource_invoices_payby_date_idx     ON public.outsource_invoices(payby_date);
CREATE INDEX outsource_invoices_paid_by_idx        ON public.outsource_invoices(paid_by);

CREATE TRIGGER outsource_invoices_set_updated_at
    BEFORE UPDATE ON public.outsource_invoices
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.outsource_invoices ENABLE ROW LEVEL SECURITY;

-- SELECT: all authenticated roles (mechanic access blocked at route level)
CREATE POLICY "Authenticated view outsource invoices"
    ON public.outsource_invoices FOR SELECT
    USING (auth.role() = 'authenticated');

-- INSERT: exec, finance, supervisor can draft / create
CREATE POLICY "Exec finance supervisor insert outsource invoices"
    ON public.outsource_invoices FOR INSERT
    WITH CHECK (
        public.is_maintenance_exec()
        OR EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('finance', 'supervisor')
        )
    );

-- UPDATE: same roles can update (e.g. draft edits, reclose)
CREATE POLICY "Exec finance supervisor update outsource invoices"
    ON public.outsource_invoices FOR UPDATE
    USING (
        public.is_maintenance_exec()
        OR EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('finance', 'supervisor')
        )
    )
    WITH CHECK (
        public.is_maintenance_exec()
        OR EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role IN ('finance', 'supervisor')
        )
    );

-- ── outsource_invoice_payments ────────────────────────────────────────────────
-- Multiple payment events per invoice. attachment_urls stores Google Drive
-- URLs uploaded via the existing upload-to-drive edge function.

CREATE TABLE public.outsource_invoice_payments (
    id                      uuid        PRIMARY KEY DEFAULT uuid_generate_v4(),
    outsource_invoice_id    uuid        NOT NULL REFERENCES public.outsource_invoices(id) ON DELETE CASCADE,
    paid_on                 date        NOT NULL,
    amount_paid             numeric(12,2) NOT NULL,
    notes                   text,
    attachment_urls         text[]      NOT NULL DEFAULT '{}',
    recorded_by             uuid        REFERENCES public.users(id),
    created_at              timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX outsource_invoice_payments_invoice_id_idx
    ON public.outsource_invoice_payments(outsource_invoice_id);

ALTER TABLE public.outsource_invoice_payments ENABLE ROW LEVEL SECURITY;

-- SELECT: all authenticated
CREATE POLICY "Authenticated view invoice payments"
    ON public.outsource_invoice_payments FOR SELECT
    USING (auth.role() = 'authenticated');

-- INSERT: exec and finance only (not supervisor)
CREATE POLICY "Exec finance insert invoice payments"
    ON public.outsource_invoice_payments FOR INSERT
    WITH CHECK (
        public.is_maintenance_exec()
        OR EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'finance'
        )
    );

-- ── Verification ──────────────────────────────────────────────────────────────

SELECT table_name, (SELECT count(*) FROM information_schema.columns c
                    WHERE c.table_name = t.table_name AND c.table_schema = 'public') AS col_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_name IN ('outsource_invoices', 'outsource_invoice_payments')
ORDER BY table_name;

ROLLBACK; -- change to COMMIT once output looks correct
