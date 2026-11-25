-- MAIN-156 Company ledgers (epic MAIN-154).
--
-- Each company's ledger is derived, never stored: every line is read from records that
-- already carry their company — purchases (`purchase_invoices.billed_to`, MAIN-157),
-- invoices (`outsource_invoices.company`, MAIN-161) and vehicle sales
-- (`vehicle_company_changes`, MAIN-155). Nothing can be edited by hand because there is
-- nothing to edit, and the prod→staging seed needs no change.
--
-- Two running columns, kept apart because they mean different things:
--   * spent            — purchases and invoices billed to the company (incl. GST);
--   * owed             — between the two companies. Positive = the other company owes
--                        this one. A vehicle sold to the other company is +, a vehicle
--                        bought from it is −, and the purchase of a vehicle is not spend.
-- Spare transfers between the companies join `owed` in MAIN-159.
--
-- Rules:
--   * An invoice enters when finance accepts it (Accepted or either GST close), as in the
--     supplier ledger; moving it back to Hold or on to Reject takes it out again.
--   * A purchase counts once. Since MAIN-129 a purchase also has a finance invoice; the
--     ledger shows the purchase and takes its GST status from that invoice. A purchase
--     with no finance invoice was recorded before MAIN-129 (kept in Google Sheets): it
--     counts from when it was recorded, with GST status unknown.
--   * Job card and multi-vehicle invoices store no GST yet, so their `gst` is NULL
--     ("not recorded"). Purchases take GST from their lines; a vehicle sale from the
--     GST % finance entered with its value (the value includes GST).
--   * PI-176, PI-180, PI-183 and PI-185 ("Bannerghatta Hub", ₹192 in all) were stock moved
--     between workshops, recorded as purchases before Move Stock existed. They are not
--     spend and are left out.
--   * Spares used on an in-house job card are not an entry: that stock was counted when
--     it was bought.

CREATE OR REPLACE FUNCTION public.company_ledger_lines(p_company text)
RETURNS TABLE(
    entry_at   timestamptz,
    seq        integer,
    line_id    uuid,
    kind       text,
    doc_date   date,
    spend      numeric,
    owed       numeric,
    gst        numeric,
    gst_status text,
    detail     jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  -- Purchases and refurbishments billed to the company.
  select coalesce(oi.accepted_at, oi.updated_at, pi.created_at at time zone 'UTC'),
         1, pi.id, pi.kind, pi.invoice_date,
         pi.total_amount, 0::numeric,
         g.gst,
         case when oi.id is null then 'unknown'
              when oi.finance_payment_status = 'GST reconciled & closed'     then 'claimed'
              when oi.finance_payment_status = 'GST not applicable & closed' then 'no_gst'
              else 'not_reconciled' end,
         jsonb_build_object(
             'purchase_number', pi.purchase_number,
             'invoice_no',      pi.invoice_number,
             'supplier',        coalesce(s.entity_name, pi.supplier_name),
             'finance_status',  oi.finance_payment_status,
             'invoice_id',      oi.id)
  from   public.purchase_invoices pi
  left join public.outsource_invoices oi on oi.purchase_invoice_id = pi.id
  left join public.suppliers s on s.id = pi.supplier_id
  cross join lateral (
      select coalesce(sum(i.line_total - round(i.quantity * i.unit_price - i.discount_amount, 2)), 0) as gst
      from   public.purchase_invoice_items i
      where  i.invoice_id = pi.id) g
  where  pi.billed_to = p_company
    and  pi.purchase_number not in (176, 180, 183, 185)
    and  (oi.id is null
          or oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed'))

  union all

  -- Job card and multi-vehicle invoices of the company, once finance has accepted them.
  select coalesce(oi.accepted_at, oi.updated_at), 2, oi.id,
         case when oi.job_card_id is not null then 'job_card' else 'multi_vehicle' end,
         oi.date_of_activity,
         oi.approved_amount, 0::numeric,
         null::numeric,
         case oi.finance_payment_status
              when 'GST reconciled & closed'     then 'claimed'
              when 'GST not applicable & closed' then 'no_gst'
              else 'not_reconciled' end,
         jsonb_build_object(
             'invoice_no',      oi.invoice_no,
             'supplier',        s.entity_name,
             'finance_status',  oi.finance_payment_status,
             'job_card_number', jc.job_card_number,
             'vehicle',         jc.vehicle_number,
             'batch_number',    bs.batch_number,
             'vehicle_count',   (select count(distinct v.vehicle_number)
                                 from public.batch_service_vehicles v
                                 where v.batch_service_id = bs.id))
  from   public.outsource_invoices oi
  left join public.job_cards      jc on jc.id = oi.job_card_id
  left join public.batch_services bs on bs.id = oi.batch_service_id
  left join public.suppliers      s  on s.id  = coalesce(jc.supplier_id, bs.supplier_id)
  where  oi.company = p_company
    and  oi.purchase_invoice_id is null
    and  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
    and  (bs.id is null or bs.status = 'Active')

  union all

  -- Vehicles sold between the companies: in both ledgers, opposite ways round.
  select c.created_at, 3, c.id,
         case when c.old_company = p_company then 'vehicle_sold' else 'vehicle_bought' end,
         (c.created_at at time zone 'Asia/Kolkata')::date,
         0::numeric,
         case when c.old_company = p_company then c.sale_value else -c.sale_value end,
         round(c.sale_value * c.gst_percent / (100 + c.gst_percent), 2),
         'inter_company',
         jsonb_build_object(
             'vehicle',      c.registration_number,
             'other_company', case when c.old_company = p_company then c.new_company else c.old_company end,
             'gst_percent',  c.gst_percent,
             'performed_by', c.performed_by_name)
  from   public.vehicle_company_changes c
  where  c.kind = 'sale'
    and  p_company in (c.old_company, c.new_company)
$$;

REVOKE ALL ON FUNCTION public.company_ledger_lines(text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.company_ledger_lines(text) TO service_role;

COMMENT ON FUNCTION public.company_ledger_lines(text) IS
  'MAIN-156: every line of one company''s ledger, derived from purchases, accepted invoices and vehicle sales. Internal; read through get_company_ledger.';


-- The statement: every line in recording order, with both running columns.
CREATE OR REPLACE FUNCTION public.get_company_ledger(p_company text)
RETURNS TABLE(
    entry_at   timestamptz,
    kind       text,
    line_id    uuid,
    doc_date   date,
    spend      numeric,
    owed       numeric,
    gst        numeric,
    gst_status text,
    spent_to_date numeric,
    owed_balance  numeric,
    detail     jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the company ledgers.' USING ERRCODE = '42501';
    END IF;
    IF p_company IS NULL OR p_company NOT IN ('nvs_travels', 'nvs_travel_solutions') THEN
        RAISE EXCEPTION 'Unknown company %.', p_company USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT l.entry_at, l.kind, l.line_id, l.doc_date, l.spend, l.owed, l.gst, l.gst_status,
           sum(l.spend) OVER w,
           sum(l.owed)  OVER w,
           l.detail
    FROM   public.company_ledger_lines(p_company) l
    WINDOW w AS (ORDER BY l.entry_at, l.seq, l.line_id ROWS UNBOUNDED PRECEDING)
    ORDER  BY l.entry_at, l.seq, l.line_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_company_ledger(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_company_ledger(text) TO authenticated, service_role;

COMMENT ON FUNCTION public.get_company_ledger(text) IS
  'MAIN-156: one company''s ledger for exec, super_admin and finance — spent to date and owed between the companies as two running columns.';
