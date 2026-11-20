-- MAIN-143: readable page addresses for tickets, purchase invoices, suppliers and mechanics.
-- Tickets open by ticket_number, purchase invoices by a new running number (PI-257),
-- suppliers by a new running number (SUP-5), mechanics by their employee ID (NVS-1234).
-- The pages turn the readable value into the row's id once and load as before, so
-- every function keeps taking ids; the readers below only return the numbers too.

-- ── 1. Running numbers for purchase invoices and suppliers ─────────────────────────
-- Added as a plain column, filled in created_at order, then made an identity like
-- job_cards.job_card_number and batch_services.batch_number. Adding the identity
-- straight away would number rows in physical order, not creation order.
-- GENERATED ALWAYS keeps the prod→staging seed working: seed_get_table_columns skips
-- such columns, so staging renumbers rather than collides.

-- The backfill must not trip the invoice guards (MAIN-120 lock, refurbishment header)
-- or move stock; it changes nothing but the new column.
ALTER TABLE public.purchase_invoices DISABLE TRIGGER USER;

ALTER TABLE public.purchase_invoices ADD COLUMN purchase_number integer;
UPDATE public.purchase_invoices p
SET    purchase_number = n.rn
FROM  (SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn FROM public.purchase_invoices) n
WHERE  n.id = p.id;

ALTER TABLE public.purchase_invoices ENABLE TRIGGER USER;

ALTER TABLE public.purchase_invoices ALTER COLUMN purchase_number SET NOT NULL;
ALTER TABLE public.purchase_invoices ALTER COLUMN purchase_number ADD GENERATED ALWAYS AS IDENTITY;
SELECT setval(pg_get_serial_sequence('public.purchase_invoices', 'purchase_number'),
              coalesce(max(purchase_number), 1), max(purchase_number) IS NOT NULL)
FROM   public.purchase_invoices;
ALTER TABLE public.purchase_invoices ADD CONSTRAINT purchase_invoices_purchase_number_key UNIQUE (purchase_number);

COMMENT ON COLUMN public.purchase_invoices.purchase_number IS
  'Running number shown as PI-<n> and used in the invoice''s address (MAIN-143). Purchases and refurbishments share it; suppliers reuse their own invoice numbers, so this is ours.';

ALTER TABLE public.suppliers ADD COLUMN supplier_number integer;
UPDATE public.suppliers s
SET    supplier_number = n.rn
FROM  (SELECT id, row_number() OVER (ORDER BY created_at, id) AS rn FROM public.suppliers) n
WHERE  n.id = s.id;

ALTER TABLE public.suppliers ALTER COLUMN supplier_number SET NOT NULL;
ALTER TABLE public.suppliers ALTER COLUMN supplier_number ADD GENERATED ALWAYS AS IDENTITY;
SELECT setval(pg_get_serial_sequence('public.suppliers', 'supplier_number'),
              coalesce(max(supplier_number), 1), max(supplier_number) IS NOT NULL)
FROM   public.suppliers;
ALTER TABLE public.suppliers ADD CONSTRAINT suppliers_supplier_number_key UNIQUE (supplier_number);

COMMENT ON COLUMN public.suppliers.supplier_number IS
  'Running number shown as SUP-<n> and used in /suppliers/SUP-<n> and /supplier-ledger/SUP-<n> (MAIN-143).';

-- ── 2. Tickets ─────────────────────────────────────────────────────────────────────
-- ticket_number is an identity but nothing enforced uniqueness; the page now looks
-- a ticket up by it.
ALTER TABLE public.tickets ADD CONSTRAINT tickets_ticket_number_key UNIQUE (ticket_number);

-- ── 3. Employee ID: mandatory, trimmed, unique ignoring case, spaces and hyphens ──
-- Trim (3 prod IDs start with a tab), then fill the blanks as AUTO-1 … in created_at
-- order. Both are logged to user_audit_logs so Edit User's history explains them.
WITH changed AS (
    SELECT id, name, email, employee_id AS old_id,
           regexp_replace(employee_id, '^[[:space:]]+|[[:space:]]+$', '', 'g') AS new_id
    FROM   public.users
    WHERE  employee_id IS NOT NULL
      AND  employee_id <> regexp_replace(employee_id, '^[[:space:]]+|[[:space:]]+$', '', 'g')
),
upd AS (
    UPDATE public.users u SET employee_id = c.new_id FROM changed c WHERE c.id = u.id
)
INSERT INTO public.user_audit_logs (target_user_id, target_name, target_email, action, changed_fields, old_data, new_data, performed_by_name)
SELECT id, coalesce(name, ''), coalesce(email, ''), 'UPDATE', ARRAY['employee_id'],
       jsonb_build_object('employee_id', old_id), jsonb_build_object('employee_id', new_id),
       'System (MAIN-143)'
FROM   changed;

WITH blank AS (
    SELECT id, name, email, employee_id AS old_id,
           'AUTO-' || row_number() OVER (ORDER BY created_at, id) AS new_id
    FROM   public.users
    WHERE  employee_id IS NULL OR employee_id = ''
),
upd AS (
    UPDATE public.users u SET employee_id = b.new_id FROM blank b WHERE b.id = u.id
)
INSERT INTO public.user_audit_logs (target_user_id, target_name, target_email, action, changed_fields, old_data, new_data, performed_by_name)
SELECT id, coalesce(name, ''), coalesce(email, ''), 'UPDATE', ARRAY['employee_id'],
       jsonb_build_object('employee_id', old_id), jsonb_build_object('employee_id', new_id),
       'System (MAIN-143)'
FROM   blank;

-- NOT NULL without a DEFAULT, deliberately: the column already exists in prod and this
-- migration fills every row first, so the prod→staging seed always supplies a value.
-- A default would quietly fill the blank the app must refuse.
ALTER TABLE public.users ALTER COLUMN employee_id SET NOT NULL;
ALTER TABLE public.users ADD CONSTRAINT users_employee_id_trimmed_check
  CHECK (employee_id <> '' AND employee_id = regexp_replace(employee_id, '^[[:space:]]+|[[:space:]]+$', '', 'g'));

-- One key for uniqueness and for the /mechanics/NVS-1234 lookup: "NVS 1234",
-- "nvs-1234" and "NVS1234" are the same ID. Generated, so the seed skips it.
ALTER TABLE public.users ADD COLUMN employee_key text
  GENERATED ALWAYS AS (lower(regexp_replace(employee_id, '[[:space:]-]', '', 'g'))) STORED;
CREATE UNIQUE INDEX users_employee_key_key ON public.users (employee_key);

COMMENT ON COLUMN public.users.employee_key IS
  'employee_id in lower case with spaces and hyphens removed — what uniqueness and the /mechanics/<employee ID> address match on (MAIN-143).';

-- ── 4. Readers return the new numbers ──────────────────────────────────────────────
-- Same signatures (CREATE OR REPLACE); only a jsonb key is added.

CREATE OR REPLACE FUNCTION public.get_outsource_invoice_rows(p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with f as (
    select
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'maintenance_payment_status', 'null')) x) as ps,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'finance_payment_status', 'null')) x)     as fs,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'paid_by', 'null')) x)                    as pb,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'type', 'null')) x)                       as ty,
      nullif(p_filters->>'date_from', '')::date as date_from,
      nullif(p_filters->>'date_to', '')::date   as date_to,
      (p_filters->>'page')::int                 as page,
      coalesce((p_filters->>'page_size')::int, 50) as page_size
  ),
  visible as (
    select oi.*, jc.id as jc_id,
           public.outsource_invoice_type(oi.job_card_id, oi.batch_service_id, pi.kind) as invoice_type
    from   public.outsource_invoices oi
    left join public.job_cards jc on jc.id = oi.job_card_id and jc.status = 'Completed'
    left join public.purchase_invoices pi on pi.id = oi.purchase_invoice_id
    cross join f
    where (oi.batch_service_id is not null or oi.purchase_invoice_id is not null or jc.id is not null)
      and public.can_read_outsource_invoice(oi.job_card_id, oi.batch_service_id)
      and (f.ps is null        or oi.maintenance_payment_status = any (f.ps))
      and (f.fs is null        or oi.finance_payment_status     = any (f.fs))
      and (f.pb is null        or oi.paid_by                    = any (f.pb))
      and (f.ty is null        or public.outsource_invoice_type(oi.job_card_id, oi.batch_service_id, pi.kind) = any (f.ty))
      and (f.date_from is null or oi.date_of_activity >= f.date_from)
      and (f.date_to is null   or oi.date_of_activity <= f.date_to)
  ),
  page as (
    select v.*
    from   visible v
    -- Newest submitted first: finance's review queue (MAIN-119).
    order  by v.submitted_on desc nulls last, v.created_at desc, v.id
    offset (select coalesce(f.page * f.page_size, 0) from f)
    limit  (select case when f.page is null then null else f.page_size end from f)
  )
  select jsonb_build_object(
    'total', (select count(*) from visible),
    'rows',  coalesce(jsonb_agg(
      (to_jsonb(p) - 'jc_id') || jsonb_build_object(
        'job_card', (
          select jsonb_build_object(
                   'id', jc.id, 'job_card_number', jc.job_card_number,
                   'vehicle_number', jc.vehicle_number, 'status', jc.status,
                   'completed_at', jc.completed_at, 'invoice_url', jc.invoice_url,
                   'supplier', (select jsonb_build_object('id', s.id, 'entity_name', s.entity_name)
                                from public.suppliers s where s.id = jc.supplier_id))
          from public.job_cards jc where jc.id = p.jc_id),
        'batch_service', (
          select jsonb_build_object(
                   'id', bs.id, 'batch_number', bs.batch_number, 'invoice_url', bs.invoice_url,
                   'status', bs.status, 'cancel_reason', bs.cancel_reason, 'cancelled_at', bs.cancelled_at,
                   'supplier', (select jsonb_build_object('id', s.id, 'entity_name', s.entity_name)
                                from public.suppliers s where s.id = bs.supplier_id),
                   'vehicles', (
                     select coalesce(jsonb_agg(jsonb_build_object(
                              'id', bsv.id, 'vehicle_number', bsv.vehicle_number, 'site', bsv.site,
                              'work_type', bsv.work_type, 'work_type_other', bsv.work_type_other,
                              'rate', bsv.rate, 'quantity', bsv.quantity, 'amount', bsv.amount,
                              'linked_job_card', (select jsonb_build_object('job_card_number', ljc.job_card_number)
                                                  from public.job_cards ljc where ljc.id = bsv.job_card_id))
                            order by bsv.vehicle_number, bsv.created_at), '[]'::jsonb)
                     from public.batch_service_vehicles bsv
                     where bsv.batch_service_id = bs.id))
          from public.batch_services bs where bs.id = p.batch_service_id),
        'purchase_invoice', (
          select jsonb_build_object(
                   'id', pi.id, 'purchase_number', pi.purchase_number,
                   'kind', pi.kind, 'invoice_number', pi.invoice_number,
                   'invoice_file_url', pi.invoice_file_url, 'total_amount', pi.total_amount,
                   'supplier', (select jsonb_build_object('id', s.id, 'entity_name', s.entity_name)
                                from public.suppliers s where s.id = pi.supplier_id))
          from public.purchase_invoices pi where pi.id = p.purchase_invoice_id)
      )
      order by p.submitted_on desc nulls last, p.created_at desc, p.id), '[]'::jsonb)
  )
  from page p
$$;

CREATE OR REPLACE FUNCTION public.supplier_ledger_lines() RETURNS TABLE(supplier_id uuid, entry_at timestamp with time zone, seq integer, line_id uuid, kind text, amount numeric, counts boolean, due_date date, invoice_id uuid, invoice_no text, job_card_number integer, batch_number integer, detail jsonb)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with inv as (
      select oi.*,
             coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id) as sup_id,
             public.invoice_submitted_day(oi)               as submitted_day,
             coalesce(oi.accepted_at, oi.updated_at)        as entered_at,
             oi.paid_by = any(public.advance_people()) as by_person,
             jc.job_card_number, bs.batch_number,
             pi.kind as purchase_invoice_kind,
             pi.purchase_number as purchase_invoice_number
      from   public.outsource_invoices oi
      left join public.job_cards         jc on jc.id = oi.job_card_id
      left join public.batch_services    bs on bs.id = oi.batch_service_id
      left join public.purchase_invoices pi on pi.id = oi.purchase_invoice_id
      where  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
        and  (bs.id is null or bs.status = 'Active')
  )
  select inv.sup_id, inv.entered_at, 1, inv.id, 'invoice',
         inv.approved_amount, true,
         inv.submitted_day + coalesce(s.payment_terms_days, 0),
         inv.id, inv.invoice_no, inv.job_card_number, inv.batch_number,
         jsonb_build_object(
             'finance_status',  inv.finance_payment_status,
             'submitted_on',    inv.submitted_day,
             'paid_by',         inv.paid_by,
             'advance',         inv.advance_amount,
             'to_supplier',     inv.approved_amount - inv.advance_amount,
             'advance_by_person', inv.by_person,
             'purchase_invoice_id', inv.purchase_invoice_id,
             'purchase_invoice_number', inv.purchase_invoice_number,
             'purchase_invoice_kind', inv.purchase_invoice_kind)
  from   inv join public.suppliers s on s.id = inv.sup_id

  union all

  select inv.sup_id, inv.entered_at, 2, inv.id, 'advance',
         -inv.advance_amount, true, null,
         inv.id, inv.invoice_no, inv.job_card_number, inv.batch_number,
         jsonb_build_object('paid_by', inv.paid_by, 'advance_by_person', inv.by_person,
                            'purchase_invoice_id', inv.purchase_invoice_id,
                            'purchase_invoice_number', inv.purchase_invoice_number,
                            'purchase_invoice_kind', inv.purchase_invoice_kind)
  from   inv
  where  inv.advance_amount > 0

  union all

  select p.supplier_id, p.created_at, 3, p.id,
         case when p.status = 'Cancelled' then 'cancelled' else 'payment' end,
         -(p.amount_paid + p.tds_amount),
         p.status = 'Active',
         null, null, null, null, null,
         jsonb_build_object(
             'paid_on', p.paid_on, 'amount_paid', p.amount_paid, 'tds_amount', p.tds_amount,
             'payment_method', p.payment_method, 'bank', p.bank, 'utr', p.utr,
             'recorded_by', ru.name, 'cancelled_at', p.cancelled_at,
             'cancelled_by', cu.name, 'cancel_reason', p.cancel_reason)
  from   public.supplier_payments p
  left join public.users ru on ru.id = p.recorded_by
  left join public.users cu on cu.id = p.cancelled_by

  union all

  select a.supplier_id, least(public.end_of_ist_day(a.as_of), a.created_at), 4, a.id,
         case when a.status = 'Reversed' then 'reversed' else 'adjustment' end,
         a.amount, a.status = 'Active', a.as_of, null, null, null, null,
         jsonb_build_object(
             'as_of', a.as_of, 'confirmed_against', a.confirmed_against,
             'system_balance', a.system_balance, 'confirmed_balance', a.confirmed_balance,
             'reason', a.reason, 'created_by', u.name, 'created_at', a.created_at,
             'reversed_at', a.reversed_at, 'reversed_by', ru.name, 'reverse_reason', a.reverse_reason)
  from   public.supplier_ledger_adjustments a
  left join public.users u  on u.id  = a.created_by
  left join public.users ru on ru.id = a.reversed_by
$$;

CREATE OR REPLACE FUNCTION public.advance_ledger_lines() RETURNS TABLE(person text, entry_at timestamp with time zone, line_id uuid, kind text, amount numeric, counts boolean, due_date date, invoice_no text, job_card_number integer, batch_number integer, detail jsonb)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select oi.paid_by, coalesce(oi.accepted_at, oi.updated_at), oi.id, 'advance',
         oi.advance_amount, true, public.invoice_submitted_day(oi),
         oi.invoice_no, jc.job_card_number, bs.batch_number,
         jsonb_build_object(
             'supplier', s.entity_name, 'supplier_id', s.id,
             'approved', oi.approved_amount, 'to_supplier', oi.approved_amount - oi.advance_amount,
             'purchase_invoice_id', oi.purchase_invoice_id,
             'purchase_invoice_number', pi.purchase_number,
             'purchase_invoice_kind', pi.kind)
  from   public.outsource_invoices oi
  left join public.job_cards         jc on jc.id = oi.job_card_id
  left join public.batch_services    bs on bs.id = oi.batch_service_id
  left join public.purchase_invoices pi on pi.id = oi.purchase_invoice_id
  left join public.suppliers         s  on s.id  = coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id)
  where  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
    and  (bs.id is null or bs.status = 'Active')
    and  oi.advance_amount > 0
    and  oi.paid_by = any(public.advance_people())

  union all

  select r.person, r.created_at, r.id,
         case when r.status = 'Cancelled' then 'cancelled' else 'repayment' end,
         -r.amount, r.status = 'Active', null, null, null, null,
         jsonb_build_object(
             'paid_on', r.paid_on, 'payment_method', r.payment_method, 'bank', r.bank, 'utr', r.utr,
             'recorded_by', ru.name, 'cancelled_at', r.cancelled_at,
             'cancelled_by', cu.name, 'cancel_reason', r.cancel_reason)
  from   public.advance_repayments r
  left join public.users ru on ru.id = r.recorded_by
  left join public.users cu on cu.id = r.cancelled_by
$$;

-- ── 5. Readers whose return columns change: DROP + CREATE ──────────────────────────
-- CREATE OR REPLACE cannot change a function's result columns. Restating
-- SECURITY DEFINER, search_path, the comment and the MAIN-127 grants (signed-in only).

-- The ledger list links each supplier as /supplier-ledger/SUP-<n>.
DROP FUNCTION public.get_supplier_balances(uuid);
CREATE FUNCTION public.get_supplier_balances(p_supplier_id uuid DEFAULT NULL::uuid) RETURNS TABLE(supplier_id uuid, supplier_number integer, entity_name text, credit_days integer, outstanding numeric, overdue numeric, due_this_wednesday numeric, due_next_wednesday numeric, later numeric, this_wednesday date, last_payment_on date, last_reconciled_on date, awaiting_acceptance bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
#variable_conflict use_column
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH bal AS (
        SELECT l.supplier_id AS sid, sum(l.amount) FILTER (WHERE l.counts) AS total
        FROM   public.supplier_ledger_lines() l
        GROUP  BY l.supplier_id
    ),
    open_items AS (
        SELECT o.supplier_id AS sid,
               sum(o.remaining) FILTER (WHERE o.bucket = 'overdue')        AS overdue,
               sum(o.remaining) FILTER (WHERE o.bucket = 'this_wednesday') AS this_wed,
               sum(o.remaining) FILTER (WHERE o.bucket = 'next_wednesday') AS next_wed,
               sum(o.remaining) FILTER (WHERE o.bucket = 'later')          AS later
        FROM   public.supplier_open_items(v_today) o
        GROUP  BY o.supplier_id
    ),
    pending AS (
        SELECT coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id) AS sid, count(*) AS n
        FROM   public.outsource_invoices oi
        LEFT JOIN public.job_cards         jc ON jc.id = oi.job_card_id
        LEFT JOIN public.batch_services    bs ON bs.id = oi.batch_service_id
        LEFT JOIN public.purchase_invoices pi ON pi.id = oi.purchase_invoice_id
        WHERE  oi.submitted_on IS NOT NULL
          AND  oi.finance_payment_status IN ('New', 'New (invoice pending)', 'Resubmitted', 'Hold')
          AND  (bs.id IS NULL OR bs.status = 'Active')
        GROUP  BY 1
    )
    SELECT s.id, s.supplier_number, s.entity_name, s.payment_terms_days,
           coalesce(bal.total, 0),
           coalesce(oi.overdue, 0), coalesce(oi.this_wed, 0),
           coalesce(oi.next_wed, 0), coalesce(oi.later, 0),
           public.payment_run_for(v_today),
           (SELECT max(p.paid_on) FROM public.supplier_payments p
            WHERE p.supplier_id = s.id AND p.status = 'Active'),
           (SELECT max(a.as_of) FROM public.supplier_ledger_adjustments a
            WHERE a.supplier_id = s.id AND a.status = 'Active'),
           coalesce(pending.n, 0)
    FROM   public.suppliers s
    LEFT JOIN bal        ON bal.sid     = s.id
    LEFT JOIN open_items oi ON oi.sid   = s.id
    LEFT JOIN pending    ON pending.sid = s.id
    WHERE  (p_supplier_id IS NULL OR s.id = p_supplier_id)
      AND  (s.status = 'approved' OR bal.sid IS NOT NULL OR pending.sid IS NOT NULL)
    ORDER  BY s.entity_name;
END;
$$;
ALTER FUNCTION public.get_supplier_balances(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_supplier_balances(uuid) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.get_supplier_balances(uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_supplier_balances(uuid) TO service_role;

-- Labour utilisation links each technician as /mechanics/<employee ID>.
DROP FUNCTION public.get_labour_report(date, date);
CREATE FUNCTION public.get_labour_report(p_from date, p_to date) RETURNS TABLE(issue_id uuid, issue_number text, description text, category text, completed_on date, site text, vehicle_number text, job_card_number integer, technician_id uuid, technician_employee_id text, technician_name text, technician_role text, hours numeric, attributed boolean)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
    SELECT i.id, i.issue_number, i.description, i.category::text, i.completed_on,
           jc.site, jc.vehicle_number, jc.job_card_number,
           il.technician_id, u.employee_id, u.name, u.role, il.hours, true
    FROM   public.issue_labour il
    JOIN   public.issues    i  ON i.id  = il.issue_id
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    LEFT JOIN public.users  u  ON u.id  = il.technician_id
    WHERE  jc.type = 'InHouse'
    AND    (i.completed_on BETWEEN p_from AND p_to OR i.completed_on IS NULL)

    UNION ALL

    SELECT i.id, i.issue_number, i.description, i.category::text, i.completed_on,
           jc.site, jc.vehicle_number, jc.job_card_number,
           NULL, NULL, NULL, NULL, i.labour_hours, false
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  jc.type = 'InHouse'
    AND    i.labour_hours > 0
    AND    i.completed_on BETWEEN p_from AND p_to
    AND    NOT EXISTS (SELECT 1 FROM public.issue_labour il WHERE il.issue_id = i.id);
$$;
ALTER FUNCTION public.get_labour_report(date, date) OWNER TO postgres;
COMMENT ON FUNCTION public.get_labour_report(p_from date, p_to date) IS 'Rows behind Analytics › Labour utilisation (MAIN-117): per-technician labour (attributed) and pre-MAIN-116 hours with no person (unattributed) on in-house work items, by activity complete date.';
REVOKE ALL ON FUNCTION public.get_labour_report(date, date) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.get_labour_report(date, date) TO authenticated;
GRANT ALL ON FUNCTION public.get_labour_report(date, date) TO service_role;
