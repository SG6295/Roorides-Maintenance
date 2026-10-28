-- MAIN-99: one outsource invoice covering many vehicles, with no ticket or job card.
--
-- A vendor who greases fifteen buses at one parking location issues one invoice. Until
-- now an outsource invoice could only hang off one job card (outsource_invoices.job_card_id
-- is UNIQUE), so the work went unrecorded rather than being split into fifteen tickets,
-- fifteen job cards and fifteen invoice rows.
--
-- A batch service is the work itself (what, by whom, where, plus the invoice file — on a
-- job card the file lives on job_cards.invoice_url, so a batch needs its own), and its
-- vehicles are one line each with that vehicle's share of the approved amount. The
-- invoice is an ordinary outsource_invoices row pointing at the batch instead of a job
-- card, so payments, both statuses, the triggers and the history all work unchanged.
--
-- Both tables are written only through save_batch_service_invoice, which is what holds
-- the rules no row policy can: the lines add up to the approved amount, and nothing
-- changes once finance has recorded a payment. Batches are never deleted; a vehicle line
-- is removed only by that function, before any payment.

create table public.batch_services (
    id          uuid        default gen_random_uuid() not null primary key,
    description text        not null,
    supplier_id uuid        not null references public.suppliers(id),
    site        text        not null,
    invoice_url text        not null,
    created_by  uuid        default auth.uid(),
    created_at  timestamptz default now() not null,
    updated_at  timestamptz default now() not null,
    constraint batch_services_description_check check (btrim(description) <> '')
);

alter table public.batch_services owner to postgres;

create trigger batch_services_set_updated_at
    before update on public.batch_services
    for each row execute function public.set_updated_at();

create table public.batch_service_vehicles (
    id               uuid          default gen_random_uuid() not null primary key,
    batch_service_id uuid          not null references public.batch_services(id),
    vehicle_number   text          not null,
    amount           numeric(12,2) not null,
    created_at       timestamptz   default now() not null,
    constraint batch_service_vehicles_amount_check check (amount > 0),
    constraint batch_service_vehicles_vehicle_key unique (batch_service_id, vehicle_number)
);

alter table public.batch_service_vehicles owner to postgres;

-- Vehicle history looks lines up by registration.
create index batch_service_vehicles_vehicle_number_idx
    on public.batch_service_vehicles (vehicle_number);

alter table public.outsource_invoices
    add column batch_service_id uuid references public.batch_services(id);

alter table public.outsource_invoices
    add constraint outsource_invoices_batch_service_id_key unique (batch_service_id);

-- An invoice belongs to a job card or to a batch, never both and never neither.
alter table public.outsource_invoices
    add constraint outsource_invoices_one_owner_check
    check ((job_card_id is null) <> (batch_service_id is null));

-- ── RLS ─────────────────────────────────────────────────────────────────────────
-- Read: whoever can read job cards' invoices — exec, super_admin, finance. Supervisors
-- cannot read job_cards either, so the Outsource Invoices list already shows them nothing.
-- Write: no policy at all — only save_batch_service_invoice, which checks for exec or
-- super_admin itself (the same shape as the payment functions, MAIN-95).

alter table public.batch_services enable row level security;
alter table public.batch_service_vehicles enable row level security;

create policy "Exec and finance view batch services" on public.batch_services
    for select using (public.is_maintenance_exec() or public.is_finance());

create policy "Exec and finance view batch service vehicles" on public.batch_service_vehicles
    for select using (public.is_maintenance_exec() or public.is_finance());

grant all on table public.batch_services to authenticated, service_role;
grant all on table public.batch_service_vehicles to authenticated, service_role;

-- ── History ─────────────────────────────────────────────────────────────────────
-- Every change to a batch's header or vehicle lines goes to audit_logs under the batch's
-- id, so get_outsource_invoice_history can show it beside the invoice's own entries.
-- The save function writes lines by delete/update/insert, so all three are logged.

create function public.log_batch_service_change() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_fields  text[];
    v_new     jsonb;
    v_old     jsonb;
    v_changed text[];
    v_batch   uuid;
BEGIN
    IF TG_TABLE_NAME = 'batch_services' THEN
        v_fields := array['description', 'supplier_id', 'site', 'invoice_url'];
        v_batch  := coalesce(NEW.id, OLD.id);
    ELSE
        v_fields := array['vehicle_number', 'amount'];
        v_batch  := coalesce(NEW.batch_service_id, OLD.batch_service_id);
    END IF;

    IF TG_OP = 'INSERT' THEN
        v_new := to_jsonb(NEW);
        INSERT INTO public.audit_logs (table_name, record_id, action, new_data, performed_by)
        VALUES (TG_TABLE_NAME, v_batch, 'INSERT',
                (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_fields) f),
                auth.uid());
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_old := to_jsonb(OLD);
        INSERT INTO public.audit_logs (table_name, record_id, action, old_data, performed_by)
        VALUES (TG_TABLE_NAME, v_batch, 'DELETE',
                (SELECT jsonb_object_agg(f, v_old->f) FROM unnest(v_fields) f),
                auth.uid());
        RETURN OLD;
    END IF;

    v_new := to_jsonb(NEW);
    v_old := to_jsonb(OLD);
    SELECT array_agg(f) INTO v_changed
    FROM   unnest(v_fields) f
    WHERE  v_new->f IS DISTINCT FROM v_old->f;

    IF v_changed IS NULL THEN
        RETURN NEW;
    END IF;

    -- A line update logs its vehicle too, so the entry says which bus changed.
    IF TG_TABLE_NAME = 'batch_service_vehicles' AND NOT 'vehicle_number' = any (v_changed) THEN
        v_old := v_old || jsonb_build_object('vehicle_number', OLD.vehicle_number);
        v_new := v_new || jsonb_build_object('vehicle_number', NEW.vehicle_number);
        INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
        VALUES (TG_TABLE_NAME, v_batch, 'UPDATE',
                (SELECT jsonb_object_agg(f, v_old->f) FROM unnest(v_changed || 'vehicle_number'::text) f),
                (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_changed || 'vehicle_number'::text) f),
                v_changed,
                auth.uid());
        RETURN NEW;
    END IF;

    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
    VALUES (TG_TABLE_NAME, v_batch, 'UPDATE',
            (SELECT jsonb_object_agg(f, v_old->f) FROM unnest(v_changed) f),
            (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_changed) f),
            v_changed,
            auth.uid());
    RETURN NEW;
END;
$$;

alter function public.log_batch_service_change() owner to postgres;

create trigger batch_services_audit
    after insert or update on public.batch_services
    for each row execute function public.log_batch_service_change();

create trigger batch_service_vehicles_audit
    after insert or update or delete on public.batch_service_vehicles
    for each row execute function public.log_batch_service_change();

-- Same signature, so CREATE OR REPLACE replaces it. Adds the batch's own entries; a
-- job-card invoice has no batch_service_id and the new branch returns nothing for it.
create or replace function public.get_outsource_invoice_history(p_invoice_id uuid)
    returns table(performed_at timestamp with time zone, performed_by_name text, source text, action text, changed_fields text[], old_data jsonb, new_data jsonb)
    language sql stable security definer
    set search_path to 'public'
    as $$
  select a.performed_at, u.name, 'invoice', a.action, a.changed_fields, a.old_data, a.new_data
  from   public.audit_logs a
  left join public.users u on u.id = a.performed_by
  where  a.table_name = 'outsource_invoices'
    and  a.record_id  = p_invoice_id
    and  auth.uid() is not null

  union all

  select a.performed_at, u.name, 'payment', a.action, a.changed_fields, a.old_data, a.new_data
  from   public.outsource_invoice_payments p
  join   public.audit_logs a
         on a.table_name = 'outsource_invoice_payments' and a.record_id = p.id
  left join public.users u on u.id = a.performed_by
  where  p.outsource_invoice_id = p_invoice_id
    and  auth.uid() is not null

  union all

  select a.performed_at, u.name,
         case a.table_name when 'batch_services' then 'batch' else 'batch_vehicle' end,
         a.action, a.changed_fields, a.old_data, a.new_data
  from   public.outsource_invoices oi
  join   public.audit_logs a
         on a.table_name in ('batch_services', 'batch_service_vehicles')
        and a.record_id = oi.batch_service_id
  left join public.users u on u.id = a.performed_by
  where  oi.id = p_invoice_id
    and  auth.uid() is not null

  union all

  select oi.created_at, u.name, 'created', 'INSERT', null, null,
         jsonb_build_object('maintenance_payment_status', coalesce(
             (select a.old_data->>'maintenance_payment_status'
              from   public.audit_logs a
              where  a.table_name = 'outsource_invoices'
                and  a.record_id  = oi.id
                and  'maintenance_payment_status' = any (a.changed_fields)
              order  by a.performed_at
              limit  1),
             oi.maintenance_payment_status))
  from   public.outsource_invoices oi
  left join public.users u on u.id = oi.created_by
  where  oi.id = p_invoice_id
    and  auth.uid() is not null
    and  not exists (
           select 1 from public.audit_logs a
           where  a.table_name = 'outsource_invoices'
             and  a.record_id  = oi.id
             and  a.action     = 'INSERT')

  order by 1 desc
$$;

-- ── Summary tiles ───────────────────────────────────────────────────────────────
-- Same signature. A batch invoice has no job card and is complete by construction (the
-- invoice is mandatory at save), so it counts alongside completed job cards.
create or replace function public.get_outsource_invoice_summary(
    p_maintenance_payment_status text[] default null,
    p_paid_by                    text[] default null,
    p_date_from                  date   default null,
    p_date_to                    date   default null,
    p_finance_payment_status     text[] default null
) returns table(total_unpaid_payable numeric, overdue_count bigint, pending_approval_count bigint)
    language sql stable security definer
    set search_path to 'public'
    as $$
    WITH paid_sums AS (
        SELECT outsource_invoice_id,
               SUM(amount_paid + tds_amount + round_off) AS total_settled
        FROM   outsource_invoice_payments
        WHERE  status = 'Active'
        GROUP  BY outsource_invoice_id
    )
    SELECT
        COALESCE(SUM(
            GREATEST(0,
                (oi.approved_amount - oi.advance_amount) - COALESCE(ps.total_settled, 0)
            )
        ), 0)                                                    AS total_unpaid_payable,

        COUNT(*) FILTER (WHERE
            oi.payby_date < CURRENT_DATE
            AND oi.finance_payment_status <> 'Paid'
        )                                                        AS overdue_count,

        COUNT(*) FILTER (WHERE oi.maintenance_payment_status = 'Hold') AS pending_approval_count

    FROM  outsource_invoices     oi
    LEFT JOIN job_cards          jc ON jc.id = oi.job_card_id
    LEFT JOIN paid_sums          ps ON ps.outsource_invoice_id = oi.id
    WHERE (oi.batch_service_id IS NOT NULL OR jc.status = 'Completed')
      AND (p_maintenance_payment_status IS NULL OR oi.maintenance_payment_status = ANY(p_maintenance_payment_status))
      AND (p_finance_payment_status     IS NULL OR oi.finance_payment_status     = ANY(p_finance_payment_status))
      AND (p_paid_by                    IS NULL OR oi.paid_by                    = ANY(p_paid_by))
      AND (p_date_from                  IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to                    IS NULL OR oi.date_of_activity <= p_date_to)
$$;

-- ── Save ────────────────────────────────────────────────────────────────────────
-- Creates (p_batch_id null) or edits a batch, its invoice and its vehicle lines in one
-- transaction, like save_purchase_invoice (MAIN-97).
--
-- SECURITY DEFINER, because the batch tables have no write policies: the role check
-- below is the only gate, so it must stay the first statement. auth.uid() still names
-- the caller, so created_by, the status-owner guard and the history are unaffected.
-- Every argument after
-- the id is jsonb so the signature never has to grow — adding a parameter under
-- CREATE OR REPLACE creates a second overload instead of replacing this one.
--
-- p_batch:   { description, supplier_id, site, invoice_url }
-- p_invoice: { date_of_activity, invoice_no, paid_by, invoice_value, approved_amount,
--              advance_amount, maintenance_payment_status, payby_date }
-- p_lines:   [{ vehicle_number, amount }, ...]  — the full set. Lines are matched on
--            vehicle_number: absent ones are deleted, changed amounts updated, new ones
--            inserted, so an unchanged line writes no history.
--
-- Errors are json text with an error_code, like finalize_outsource_invoice:
--   UNAUTHORIZED, BATCH_NOT_FOUND, BATCH_LOCKED (an active payment exists),
--   INVOICE_DETAILS_INCOMPLETE, NO_VEHICLES, DUPLICATE_VEHICLE, LINES_MISMATCH.

create function public.save_batch_service_invoice(
    p_batch_id uuid,
    p_batch    jsonb,
    p_invoice  jsonb,
    p_lines    jsonb
) returns uuid
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_batch_id   uuid := p_batch_id;
    v_invoice_id uuid;
    v_approved   numeric;
    v_lines_sum  numeric;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can save a multi-vehicle invoice.'
        )::text;
    END IF;

    IF nullif(btrim(p_batch->>'description'), '') IS NULL
       OR nullif(p_batch->>'supplier_id', '') IS NULL
       OR nullif(btrim(p_batch->>'site'), '') IS NULL
       OR nullif(btrim(p_batch->>'invoice_url'), '') IS NULL
       OR nullif(btrim(p_invoice->>'invoice_no'), '') IS NULL
       OR nullif(p_invoice->>'date_of_activity', '') IS NULL
       OR nullif(p_invoice->>'paid_by', '') IS NULL
       OR nullif(p_invoice->>'invoice_value', '') IS NULL
       OR nullif(p_invoice->>'approved_amount', '') IS NULL
       OR nullif(p_invoice->>'advance_amount', '') IS NULL
       OR nullif(p_invoice->>'maintenance_payment_status', '') IS NULL
       OR nullif(p_invoice->>'payby_date', '') IS NULL
    THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_DETAILS_INCOMPLETE',
            'error_message', 'Fill in the work details, every invoice field and the invoice file.'
        )::text;
    END IF;

    IF jsonb_array_length(coalesce(p_lines, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_VEHICLES',
            'error_message', 'Add at least one vehicle.'
        )::text;
    END IF;

    IF (SELECT count(*) <> count(DISTINCT l->>'vehicle_number')
        FROM jsonb_array_elements(p_lines) l) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DUPLICATE_VEHICLE',
            'error_message', 'A vehicle appears on more than one line.'
        )::text;
    END IF;

    v_approved := (p_invoice->>'approved_amount')::numeric;
    SELECT sum((l->>'amount')::numeric) INTO v_lines_sum FROM jsonb_array_elements(p_lines) l;

    IF v_lines_sum IS DISTINCT FROM v_approved THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'LINES_MISMATCH',
            'error_message', format('Vehicle amounts add up to %s but the approved amount is %s.',
                                    v_lines_sum, v_approved)
        )::text;
    END IF;

    IF v_batch_id IS NULL THEN
        INSERT INTO public.batch_services (description, supplier_id, site, invoice_url)
        VALUES (
            btrim(p_batch->>'description'),
            (p_batch->>'supplier_id')::uuid,
            btrim(p_batch->>'site'),
            btrim(p_batch->>'invoice_url')
        )
        RETURNING id INTO v_batch_id;

        INSERT INTO public.outsource_invoices
            (batch_service_id, date_of_activity, invoice_no, paid_by, invoice_value,
             approved_amount, advance_amount, maintenance_payment_status, payby_date, created_by)
        VALUES (
            v_batch_id,
            (p_invoice->>'date_of_activity')::date,
            btrim(p_invoice->>'invoice_no'),
            p_invoice->>'paid_by',
            (p_invoice->>'invoice_value')::numeric,
            v_approved,
            (p_invoice->>'advance_amount')::numeric,
            p_invoice->>'maintenance_payment_status',
            (p_invoice->>'payby_date')::date,
            auth.uid()
        );
    ELSE
        -- Lock the invoice first so a payment cannot be recorded between the check and
        -- the edit; record_outsource_invoice_payment takes the same lock.
        SELECT id INTO v_invoice_id
        FROM   public.outsource_invoices
        WHERE  batch_service_id = v_batch_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'BATCH_NOT_FOUND',
                'error_message', 'Multi-vehicle invoice not found.'
            )::text;
        END IF;

        IF EXISTS (SELECT 1 FROM public.outsource_invoice_payments
                   WHERE outsource_invoice_id = v_invoice_id AND status = 'Active') THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'BATCH_LOCKED',
                'error_message', 'Finance has recorded a payment against this invoice, so it can no longer be edited.'
            )::text;
        END IF;

        UPDATE public.batch_services
        SET    description = btrim(p_batch->>'description'),
               supplier_id = (p_batch->>'supplier_id')::uuid,
               site        = btrim(p_batch->>'site'),
               invoice_url = btrim(p_batch->>'invoice_url')
        WHERE  id = v_batch_id;

        UPDATE public.outsource_invoices
        SET    date_of_activity           = (p_invoice->>'date_of_activity')::date,
               invoice_no                 = btrim(p_invoice->>'invoice_no'),
               paid_by                    = p_invoice->>'paid_by',
               invoice_value              = (p_invoice->>'invoice_value')::numeric,
               approved_amount            = v_approved,
               advance_amount             = (p_invoice->>'advance_amount')::numeric,
               maintenance_payment_status = p_invoice->>'maintenance_payment_status',
               payby_date                 = (p_invoice->>'payby_date')::date
        WHERE  id = v_invoice_id;

        DELETE FROM public.batch_service_vehicles
        WHERE  batch_service_id = v_batch_id
          AND  vehicle_number NOT IN (
                   SELECT l->>'vehicle_number' FROM jsonb_array_elements(p_lines) l
               );

        UPDATE public.batch_service_vehicles v
        SET    amount = (l->>'amount')::numeric
        FROM   jsonb_array_elements(p_lines) l
        WHERE  v.batch_service_id = v_batch_id
          AND  v.vehicle_number   = l->>'vehicle_number'
          AND  v.amount IS DISTINCT FROM (l->>'amount')::numeric;
    END IF;

    INSERT INTO public.batch_service_vehicles (batch_service_id, vehicle_number, amount)
    SELECT v_batch_id, l->>'vehicle_number', (l->>'amount')::numeric
    FROM   jsonb_array_elements(p_lines) l
    WHERE  NOT EXISTS (
               SELECT 1 FROM public.batch_service_vehicles v
               WHERE  v.batch_service_id = v_batch_id
                 AND  v.vehicle_number   = l->>'vehicle_number'
           );

    RETURN v_batch_id;
END;
$$;

alter function public.save_batch_service_invoice(uuid, jsonb, jsonb, jsonb) owner to postgres;
grant all on function public.save_batch_service_invoice(uuid, jsonb, jsonb, jsonb) to authenticated, service_role;
