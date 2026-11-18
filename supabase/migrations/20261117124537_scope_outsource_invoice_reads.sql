-- MAIN-141: every signed-in user could read every outsource invoice — mechanics,
-- electricians and supervisors of other sites included — through the table, the
-- summary tiles and the history drawer.
--
-- Decided (17 Nov 2026): exec, super_admin and finance see every invoice; a
-- supervisor sees the invoices of their own sites (user_sites), with every detail
-- and the history; mechanics and electricians see none. An invoice has no site of
-- its own:
--   job card invoice      → job_cards.site
--   multi-vehicle invoice → any line's batch_service_vehicles.site (the whole
--                           invoice and all its lines are then shown)
--   purchase invoice      → never, it belongs to a workshop, not a site
-- Site names match exactly, case included, as in every other supervisor policy.
--
-- Supervisors cannot read job_cards, batch_services, batch_service_vehicles or
-- suppliers, and must not: suppliers holds bank and PAN details, and opening
-- job_cards would also fill the job_card embed on their ticket screens. So the
-- Outsource Invoices list is served by get_outsource_invoice_rows, which returns
-- only what the page shows, for every role, under the same rule as the tiles.

-- ── The one rule ────────────────────────────────────────────────────────────
-- Takes the owner columns rather than the invoice id, so the policy on
-- outsource_invoices never queries outsource_invoices.
CREATE FUNCTION public.can_read_outsource_invoice(p_job_card_id uuid, p_batch_service_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  select public.is_maintenance_exec()
      or public.is_finance()
      or (exists (select 1 from public.users
                  where id = auth.uid() and role = 'supervisor')
          and exists (
            select 1
            from   public.user_sites us
            join   public.sites s on s.id = us.site_id
            where  us.user_id = auth.uid()
              and (s.name = (select jc.site from public.job_cards jc where jc.id = p_job_card_id)
                   or s.name in (select bsv.site from public.batch_service_vehicles bsv
                                 where bsv.batch_service_id = p_batch_service_id))))
$$;

REVOKE EXECUTE ON FUNCTION public.can_read_outsource_invoice(uuid, uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.can_read_outsource_invoice(uuid, uuid) TO authenticated, service_role;

-- ── Table policy ────────────────────────────────────────────────────────────
DROP POLICY "Authenticated view outsource invoices" ON public.outsource_invoices;

CREATE POLICY "Readers view their outsource invoices" ON public.outsource_invoices
  FOR SELECT USING (public.can_read_outsource_invoice(job_card_id, batch_service_id));

-- ── The list ────────────────────────────────────────────────────────────────
-- What the Outsource Invoices page shows, in the shape its PostgREST query used to
-- return: the invoice row plus job_card / batch_service / purchase_invoice, each
-- with its supplier's id and name only. Same rows as before for exec and finance:
-- invoices of Completed job cards, every multi-vehicle invoice (cancelled ones
-- greyed by the page) and every purchase invoice's finance invoice.
--
-- p_filters: maintenance_payment_status, finance_payment_status, paid_by (text
-- arrays), date_from, date_to (dates on date_of_activity), page (0-based; absent
-- or null = every row, for the page's search mode), page_size (default 50).
-- Returns { rows: [...], total }. jsonb so the filters can grow without a new
-- overload.
CREATE FUNCTION public.get_outsource_invoice_rows(p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  with f as (
    select
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'maintenance_payment_status', 'null')) x) as ps,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'finance_payment_status', 'null')) x)     as fs,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'paid_by', 'null')) x)                    as pb,
      nullif(p_filters->>'date_from', '')::date as date_from,
      nullif(p_filters->>'date_to', '')::date   as date_to,
      (p_filters->>'page')::int                 as page,
      coalesce((p_filters->>'page_size')::int, 50) as page_size
  ),
  visible as (
    select oi.*, jc.id as jc_id
    from   public.outsource_invoices oi
    left join public.job_cards jc on jc.id = oi.job_card_id and jc.status = 'Completed'
    cross join f
    where (oi.batch_service_id is not null or oi.purchase_invoice_id is not null or jc.id is not null)
      and public.can_read_outsource_invoice(oi.job_card_id, oi.batch_service_id)
      and (f.ps is null        or oi.maintenance_payment_status = any (f.ps))
      and (f.fs is null        or oi.finance_payment_status     = any (f.fs))
      and (f.pb is null        or oi.paid_by                    = any (f.pb))
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
                   'id', pi.id, 'kind', pi.kind, 'invoice_number', pi.invoice_number,
                   'invoice_file_url', pi.invoice_file_url,
                   'supplier', (select jsonb_build_object('id', s.id, 'entity_name', s.entity_name)
                                from public.suppliers s where s.id = pi.supplier_id))
          from public.purchase_invoices pi where pi.id = p.purchase_invoice_id)
      )
      order by p.submitted_on desc nulls last, p.created_at desc, p.id), '[]'::jsonb)
  )
  from page p
$$;

REVOKE EXECUTE ON FUNCTION public.get_outsource_invoice_rows(jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_outsource_invoice_rows(jsonb) TO authenticated, service_role;

-- ── Summary tiles: count only what the caller can see ───────────────────────
-- Same signature, so CREATE OR REPLACE replaces it rather than adding an overload.
CREATE OR REPLACE FUNCTION public.get_outsource_invoice_summary(p_maintenance_payment_status text[] DEFAULT NULL::text[], p_paid_by text[] DEFAULT NULL::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_finance_payment_status text[] DEFAULT NULL::text[])
RETURNS TABLE(new_count bigint, hold_count bigint, reject_count bigint, accepted_count bigint, pending_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
    SELECT
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'New')      AS new_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Hold')     AS hold_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Reject')   AS reject_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Accepted') AS accepted_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'New (invoice pending)') AS pending_count
    FROM  outsource_invoices     oi
    LEFT JOIN job_cards          jc ON jc.id = oi.job_card_id
    LEFT JOIN batch_services     bs ON bs.id = oi.batch_service_id
    WHERE (bs.status = 'Active' OR jc.status = 'Completed' OR oi.purchase_invoice_id IS NOT NULL)
      AND public.can_read_outsource_invoice(oi.job_card_id, oi.batch_service_id)
      AND (p_maintenance_payment_status IS NULL OR oi.maintenance_payment_status = ANY(p_maintenance_payment_status))
      AND (p_finance_payment_status     IS NULL OR oi.finance_payment_status     = ANY(p_finance_payment_status))
      AND (p_paid_by                    IS NULL OR oi.paid_by                    = ANY(p_paid_by))
      AND (p_date_from                  IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to                    IS NULL OR oi.date_of_activity <= p_date_to)
$$;

-- ── History: follows the invoice ────────────────────────────────────────────
-- Was gated only on auth.uid() being set. Same signature, so it is replaced.
CREATE OR REPLACE FUNCTION public.get_outsource_invoice_history(p_invoice_id uuid)
RETURNS TABLE(performed_at timestamp with time zone, performed_by_name text, source text, action text, changed_fields text[], old_data jsonb, new_data jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  with allowed as (
    select oi.*
    from   public.outsource_invoices oi
    where  oi.id = p_invoice_id
      and  public.can_read_outsource_invoice(oi.job_card_id, oi.batch_service_id)
  )
  select a.performed_at, u.name, 'invoice', a.action, a.changed_fields, a.old_data, a.new_data
  from   allowed oi
  join   public.audit_logs a
         on a.table_name = 'outsource_invoices'
        and a.record_id  = oi.id
  left join public.users u on u.id = a.performed_by

  union all

  select a.performed_at, u.name,
         case a.table_name when 'batch_services' then 'batch' else 'batch_vehicle' end,
         a.action, a.changed_fields, a.old_data, a.new_data
  from   allowed oi
  join   public.audit_logs a
         on a.table_name in ('batch_services', 'batch_service_vehicles')
        and a.record_id = oi.batch_service_id
  left join public.users u on u.id = a.performed_by

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
  from   allowed oi
  left join public.users u on u.id = oi.created_by
  where  not exists (
           select 1 from public.audit_logs a
           where  a.table_name = 'outsource_invoices'
             and  a.record_id  = oi.id
             and  a.action     = 'INSERT')

  order by 1 desc
$$;

-- The app calls it signed in; anon had kept its grant after MAIN-127.
REVOKE EXECUTE ON FUNCTION public.get_outsource_invoice_history(uuid) FROM PUBLIC, anon;
