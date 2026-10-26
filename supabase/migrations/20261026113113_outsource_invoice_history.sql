-- MAIN-96: a dated "who changed what" history for each outsource invoice.
--
-- Triggers write to the existing audit_logs table, so nothing a caller does can skip
-- them — the exec's closure form, finance's drawer, the payment RPCs and direct API
-- calls are all captured the same way. SECURITY DEFINER because audit_logs' INSERT
-- policy only admits rows a client writes about itself.
--
-- Payments are logged under their own id (table_name = 'outsource_invoice_payments');
-- get_outsource_invoice_history joins them back to their invoice. A status change made
-- by the payment recalculation lands as an invoice UPDATE in the same transaction, so
-- it carries the same performed_at and performer as the payment that caused it, which
-- is how the drawer shows the two as one line.

create index if not exists audit_logs_table_record_idx
  on public.audit_logs using btree (table_name, record_id);

-- ── Invoice changes ──────────────────────────────────────────────────────────────
-- Only the fields a person decides; timestamps and bookkeeping columns are left out.

create function public.log_outsource_invoice_change() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_fields  text[] := array[
        'maintenance_payment_status', 'finance_payment_status', 'finance_remark', 'paid_by',
        'invoice_value', 'approved_amount', 'advance_amount', 'payby_date'
    ];
    v_new     jsonb := to_jsonb(NEW);
    v_old     jsonb;
    v_changed text[];
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_logs (table_name, record_id, action, new_data, performed_by)
        VALUES ('outsource_invoices', NEW.id, 'INSERT',
                (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_fields) f),
                auth.uid());
        RETURN NEW;
    END IF;

    v_old := to_jsonb(OLD);
    SELECT array_agg(f) INTO v_changed
    FROM   unnest(v_fields) f
    WHERE  v_new->f IS DISTINCT FROM v_old->f;

    IF v_changed IS NULL THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
    VALUES ('outsource_invoices', NEW.id, 'UPDATE',
            (SELECT jsonb_object_agg(f, v_old->f) FROM unnest(v_changed) f),
            (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_changed) f),
            v_changed,
            auth.uid());
    RETURN NEW;
END;
$$;

create trigger outsource_invoices_audit
  after insert or update on public.outsource_invoices
  for each row execute function public.log_outsource_invoice_change();

-- ── Payment changes ──────────────────────────────────────────────────────────────
-- A payment is recorded once and can only change by being cancelled.

create function public.log_outsource_invoice_payment_change() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_logs (table_name, record_id, action, new_data, performed_by)
        VALUES ('outsource_invoice_payments', NEW.id, 'INSERT', to_jsonb(NEW), auth.uid());
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
        VALUES ('outsource_invoice_payments', NEW.id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW),
                array['status'], auth.uid());
    END IF;
    RETURN NEW;
END;
$$;

create trigger outsource_invoice_payments_audit
  after insert or update on public.outsource_invoice_payments
  for each row execute function public.log_outsource_invoice_payment_change();

alter function public.log_outsource_invoice_change() owner to postgres;
alter function public.log_outsource_invoice_payment_change() owner to postgres;

-- ── Reading the history ──────────────────────────────────────────────────────────
-- Returns each entry with the performer's name. Finance cannot read exec or other
-- finance profiles under RLS, so a client-side join would show blank names; this
-- returns names only, nothing else from users.
--
-- History starts when this migration runs. So that every invoice still shows the
-- exec's original decision, a 'created' entry is built from the invoice row itself
-- when no INSERT was logged. Its maintenance status is the earliest one on record:
-- the old value of the first logged change to it, or else the current value.

create function public.get_outsource_invoice_history(p_invoice_id uuid)
returns table(
    performed_at      timestamptz,
    performed_by_name text,
    source            text,
    action            text,
    changed_fields    text[],
    old_data          jsonb,
    new_data          jsonb
)
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

alter function public.get_outsource_invoice_history(uuid) owner to postgres;
grant all on function public.get_outsource_invoice_history(uuid) to authenticated, service_role;
