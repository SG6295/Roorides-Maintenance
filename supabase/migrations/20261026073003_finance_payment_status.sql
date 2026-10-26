-- MAIN-90: finance gets its own payment status on outsource invoices.
--
-- The one status an invoice carried (Approved / Hold / Reject) is the maintenance
-- exec's decision at job card closure. Finance had nowhere to record its own. The
-- existing column is renamed to say whose it is, and finance gets a separate status
-- and remark that only finance (and super_admin) may set.

-- ── A. Rename the maintenance status ─────────────────────────────────────────────
-- RENAME COLUMN rewrites the CHECK expression itself; the constraint and index names
-- are renamed to match.

alter table public.outsource_invoices
  rename column payment_status to maintenance_payment_status;

alter table public.outsource_invoices
  rename constraint outsource_invoices_payment_status_check
  to outsource_invoices_maintenance_payment_status_check;

alter index public.outsource_invoices_payment_status_idx
  rename to outsource_invoices_maintenance_payment_status_idx;

-- ── B. The finance status ────────────────────────────────────────────────────────
-- Mirrors FINANCE_PAYMENT_STATUSES in src/constants/outsourceInvoices.js — keep in step.

alter table public.outsource_invoices
  add column finance_payment_status text not null default 'Due',
  add column finance_remark text;

alter table public.outsource_invoices
  add constraint outsource_invoices_finance_payment_status_check
  check (finance_payment_status = any (array[
    'Due'::text,
    'Paid'::text,
    'Hold - on request'::text,
    'Hold - further details required'::text,
    'Reject - duplicate'::text,
    'Reject - incorrect/insufficient details'::text,
    'Reject - other'::text
  ]));

create index outsource_invoices_finance_payment_status_idx
  on public.outsource_invoices using btree (finance_payment_status);

-- ── C. Only finance (and super_admin) can set it ─────────────────────────────────
-- RLS gates rows, not columns, and maintenance_exec, finance and supervisor all hold
-- UPDATE on this table — so the ownership of each status is enforced here.
--
-- maintenance_exec is named explicitly rather than via is_maintenance_exec(), which is
-- also true for super_admin, and super_admin may change both statuses.
--
-- A NULL auth.uid() is a service-role or direct database write (backups, the staging
-- seed, migrations) and passes untouched.
--
-- The closure form's upsert names only the maintenance columns, so its ON CONFLICT
-- update never touches the finance ones and passes this check.

create function public.guard_outsource_invoice_status_owners() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_role text;
    v_finance_changed boolean;
    v_maintenance_changed boolean;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();

    IF TG_OP = 'INSERT' THEN
        v_finance_changed     := NEW.finance_payment_status <> 'Due' OR NEW.finance_remark IS NOT NULL;
        v_maintenance_changed := NEW.maintenance_payment_status IS NOT NULL;
    ELSE
        v_finance_changed     := NEW.finance_payment_status IS DISTINCT FROM OLD.finance_payment_status
                              OR NEW.finance_remark         IS DISTINCT FROM OLD.finance_remark;
        v_maintenance_changed := NEW.maintenance_payment_status IS DISTINCT FROM OLD.maintenance_payment_status;
    END IF;

    IF v_finance_changed AND v_role IS DISTINCT FROM 'finance' AND v_role IS DISTINCT FROM 'super_admin' THEN
        RAISE EXCEPTION 'Only finance can change the payment status reported by finance.'
            USING ERRCODE = '42501';
    END IF;

    IF v_maintenance_changed AND v_role = 'finance' THEN
        RAISE EXCEPTION 'Finance cannot change the payment status reported by maintenance.'
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

alter function public.guard_outsource_invoice_status_owners() owner to postgres;

create trigger outsource_invoices_guard_status_owners
  before insert or update on public.outsource_invoices
  for each row execute function public.guard_outsource_invoice_status_owners();

-- ── Summary RPC ──────────────────────────────────────────────────────────────────
-- Postgres will not rename a parameter under CREATE OR REPLACE — it would create a
-- second overload beside the first. DROP + CREATE runs atomically inside this
-- migration; DROP discards ownership and grants, so both are restated.
--
-- p_finance_payment_status is new, so the summary tiles follow the list's new
-- Finance Status filter. It goes last, with a default, like the others.

drop function if exists public.get_outsource_invoice_summary(text[], text[], date, date);

create function public.get_outsource_invoice_summary(
    p_maintenance_payment_status text[] default null::text[],
    p_paid_by                    text[] default null::text[],
    p_date_from                  date   default null::date,
    p_date_to                    date   default null::date,
    p_finance_payment_status     text[] default null::text[]
) returns table(total_unpaid_payable numeric, overdue_count bigint, pending_approval_count bigint)
    language sql stable security definer
    set search_path to 'public'
    as $$
    WITH paid_sums AS (
        SELECT outsource_invoice_id,
               SUM(amount_paid) AS total_paid
        FROM   outsource_invoice_payments
        GROUP  BY outsource_invoice_id
    )
    SELECT
        COALESCE(SUM(
            GREATEST(0,
                (oi.approved_amount - oi.advance_amount) - COALESCE(ps.total_paid, 0)
            )
        ) FILTER (WHERE
            COALESCE(ps.total_paid, 0) < (oi.approved_amount - oi.advance_amount)
        ), 0)                                                    AS total_unpaid_payable,

        COUNT(*) FILTER (WHERE
            oi.payby_date < CURRENT_DATE
            AND COALESCE(ps.total_paid, 0) < (oi.approved_amount - oi.advance_amount)
        )                                                        AS overdue_count,

        COUNT(*) FILTER (WHERE oi.maintenance_payment_status = 'Hold') AS pending_approval_count

    FROM  outsource_invoices     oi
    JOIN  job_cards              jc ON jc.id = oi.job_card_id
    LEFT JOIN paid_sums          ps ON ps.outsource_invoice_id = oi.id
    WHERE jc.status = 'Completed'
      AND (p_maintenance_payment_status IS NULL OR oi.maintenance_payment_status = ANY(p_maintenance_payment_status))
      AND (p_finance_payment_status     IS NULL OR oi.finance_payment_status     = ANY(p_finance_payment_status))
      AND (p_paid_by                    IS NULL OR oi.paid_by                    = ANY(p_paid_by))
      AND (p_date_from                  IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to                    IS NULL OR oi.date_of_activity <= p_date_to)
$$;

alter function public.get_outsource_invoice_summary(text[], text[], date, date, text[]) owner to postgres;
grant all on function public.get_outsource_invoice_summary(text[], text[], date, date, text[])
  to anon, authenticated, service_role;

-- ── finalize_outsource_invoice ───────────────────────────────────────────────────
-- plpgsql bodies are stored as text, so the rename above does not reach them: this
-- function would fail at run time on v_invoice.payment_status. Body update only — the
-- signature is unchanged, so CREATE OR REPLACE replaces it in place and keeps its grants.

create or replace function public.finalize_outsource_invoice(p_job_card_id uuid, p_remarks text default null::text) returns jsonb
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_job_card job_cards%ROWTYPE;
    v_invoice  outsource_invoices%ROWTYPE;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can finalize outsource invoices.',
            'details',       null
        )::text;
    END IF;

    SELECT * INTO v_job_card
    FROM   public.job_cards
    WHERE  id     = p_job_card_id
      AND  status = 'Completed - Invoice Pending'
      AND  type   = 'Outsource';

    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'JOB_CARD_NOT_ELIGIBLE',
            'error_message', 'Job card not found or is not an Outsource card with status "Completed - Invoice Pending".',
            'details',       null
        )::text;
    END IF;

    IF v_job_card.invoice_url IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_FILE_REQUIRED',
            'error_message', 'An invoice file must be uploaded before finalizing.',
            'details',       null
        )::text;
    END IF;

    SELECT * INTO v_invoice
    FROM   public.outsource_invoices
    WHERE  job_card_id = p_job_card_id;

    IF NOT FOUND
       OR v_invoice.invoice_no                 IS NULL
       OR v_invoice.invoice_value              IS NULL
       OR v_invoice.approved_amount            IS NULL
       OR v_invoice.advance_amount             IS NULL
       OR v_invoice.date_of_activity           IS NULL
       OR v_invoice.payby_date                 IS NULL
       OR v_invoice.maintenance_payment_status IS NULL
       OR v_invoice.paid_by                    IS NULL
    THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_DETAILS_INCOMPLETE',
            'error_message', 'Invoice details are incomplete. Please fill in all required fields before finalizing.',
            'details',       null
        )::text;
    END IF;

    UPDATE public.job_cards
    SET    status  = 'Completed',
           remarks = coalesce(p_remarks, remarks)
    WHERE  id = p_job_card_id;

    RETURN json_build_object(
        'success',     true,
        'job_card_id', p_job_card_id
    );
END;
$$;
