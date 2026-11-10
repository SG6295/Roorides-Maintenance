-- MAIN-123 group B: a refurbishment's invoice names an approved supplier, carries the
-- outsource invoice details and goes to finance, then into the supplier ledger once
-- accepted. Group D reuses purchase_invoices.supplier_id and the third invoice owner
-- for every purchase.

ALTER TABLE public.purchase_invoices
    ADD COLUMN supplier_id uuid REFERENCES public.suppliers(id);

CREATE INDEX idx_purchase_invoices_supplier ON public.purchase_invoices (supplier_id);

COMMENT ON COLUMN public.purchase_invoices.supplier_id IS 'The supplier, where one was chosen from the list. supplier_name holds its name at the time, so Purchase History reads the same either way.';

ALTER TABLE public.outsource_invoices
    ADD COLUMN purchase_invoice_id uuid UNIQUE REFERENCES public.purchase_invoices(id);

ALTER TABLE public.outsource_invoices DROP CONSTRAINT outsource_invoices_one_owner_check;
ALTER TABLE public.outsource_invoices ADD CONSTRAINT outsource_invoices_one_owner_check
    CHECK (num_nonnulls(job_card_id, batch_service_id, purchase_invoice_id) = 1);

-- A purchase invoice's finance invoice reaches finance as soon as it is saved, like a
-- multi-vehicle invoice.
CREATE OR REPLACE FUNCTION public.submit_invoice_on_insert() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    IF NEW.batch_service_id IS NOT NULL
       OR NEW.purchase_invoice_id IS NOT NULL
       OR EXISTS (SELECT 1 FROM public.job_cards WHERE id = NEW.job_card_id AND status = 'Completed') THEN
        PERFORM public.submit_outsource_invoice_to_finance(NEW.id);
    END IF;
    RETURN NULL;
END;
$$;

-- p_invoice takes save_purchase_invoice's keys, with supplier_id in place of
-- supplier_name, plus the outsource invoice details: paid_by,
-- maintenance_payment_status, invoice_value, approved_amount, advance_amount,
-- payby_date. p_lines is
-- [{ scrap_inventory_id, original_part_id, quantity, unit_price, gst_rate, comment }]:
-- scrap_inventory_id for a part picked from scrap, or original_part_id + comment when it
-- could not be found there.
CREATE OR REPLACE FUNCTION public.record_refurbishment(p_invoice jsonb, p_lines jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_location    uuid := NULLIF(p_invoice->>'location_id', '')::uuid;
    v_supplier_id uuid := NULLIF(p_invoice->>'supplier_id', '')::uuid;
    v_supplier    text;
    v_inv_date    date := NULLIF(p_invoice->>'invoice_date', '')::date;
    v_inv_value   numeric := NULLIF(p_invoice->>'invoice_value', '')::numeric;
    v_approved    numeric := NULLIF(p_invoice->>'approved_amount', '')::numeric;
    v_advance     numeric := NULLIF(p_invoice->>'advance_amount', '')::numeric;
    v_payby       date := NULLIF(p_invoice->>'payby_date', '')::date;
    v_total       numeric;
    v_invoice_id  uuid;
    v_line        jsonb;
    v_scrap_id    uuid;
    v_scrap       public.scrap_inventory%ROWTYPE;
    v_final_scrap uuid;
    v_part_id     uuid;
    v_part_name   text;
    v_part_number text;
    v_part_unit   text;
    v_refurb_id   uuid;
    v_item_id     uuid;
    v_quantity    numeric;
    v_unit_price  numeric;
    v_comment     text;
    v_seen        uuid[] := '{}';
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can record a refurbishment.',
            'details',       null
        )::text;
    END IF;

    IF NULLIF(btrim(COALESCE(p_invoice->>'invoice_number', '')), '') IS NULL
       OR v_supplier_id IS NULL
       OR v_inv_date IS NULL
       OR v_location IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_INCOMPLETE',
            'error_message', 'Supplier, invoice number, invoice date and workshop are required.',
            'details',       null
        )::text;
    END IF;

    SELECT entity_name INTO v_supplier
    FROM   public.suppliers
    WHERE  id = v_supplier_id AND status = 'approved';

    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'SUPPLIER_NOT_APPROVED',
            'error_message', 'Choose an approved supplier.',
            'details',       null
        )::text;
    END IF;

    IF NULLIF(btrim(COALESCE(p_invoice->>'invoice_file_url', '')), '') IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_FILE_REQUIRED',
            'error_message', 'Attach the invoice file.',
            'details',       null
        )::text;
    END IF;

    -- The same rules as the invoice form on a job card or multi-vehicle invoice.
    IF v_inv_date > (now() AT TIME ZONE 'Asia/Kolkata')::date
       OR NULLIF(p_invoice->>'paid_by', '') IS NULL
       OR NULLIF(p_invoice->>'maintenance_payment_status', '') IS NULL
       OR v_inv_value IS NULL OR v_inv_value <= 0
       OR v_approved  IS NULL OR v_approved  < 0 OR v_approved > v_inv_value
       OR v_advance   IS NULL OR v_advance   < 0 OR v_advance  > v_approved
       OR v_payby     IS NULL OR v_payby < v_inv_date THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_DETAILS_INVALID',
            'error_message', 'Check the invoice details.',
            'details',       null
        )::text;
    END IF;

    IF jsonb_array_length(COALESCE(p_lines, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_LINES',
            'error_message', 'Add at least one refurbished part.',
            'details',       null
        )::text;
    END IF;

    -- In id order, so two invoices touching the same rows cannot deadlock.
    PERFORM 1
    FROM    public.scrap_inventory
    WHERE   id IN (SELECT (l->>'scrap_inventory_id')::uuid
                   FROM   jsonb_array_elements(p_lines) l
                   WHERE  l->>'scrap_inventory_id' IS NOT NULL)
    ORDER   BY id
    FOR UPDATE;

    v_invoice_id := public.save_purchase_invoice(
        NULL, p_invoice || jsonb_build_object('supplier_name', v_supplier), '[]'::jsonb);

    UPDATE public.purchase_invoices SET supplier_id = v_supplier_id WHERE id = v_invoice_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_scrap_id   := NULLIF(v_line->>'scrap_inventory_id', '')::uuid;
        v_quantity   := round((v_line->>'quantity')::numeric, 2);
        v_unit_price := (v_line->>'unit_price')::numeric;
        v_comment    := NULLIF(btrim(COALESCE(v_line->>'comment', '')), '');

        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVALID_QUANTITY',
                'error_message', 'Every line needs a quantity above zero.',
                'details',       null
            )::text;
        END IF;
        IF v_unit_price IS NULL OR v_unit_price < 0 THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVALID_PRICE',
                'error_message', 'Every line needs a unit price.',
                'details',       null
            )::text;
        END IF;

        IF v_scrap_id IS NOT NULL THEN
            IF v_scrap_id = ANY(v_seen) THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'DUPLICATE_SCRAP_ITEM',
                    'error_message', 'The same scrap item appears more than once.',
                    'details',       json_build_object('duplicate_id', v_scrap_id)
                )::text;
            END IF;
            v_seen := v_seen || v_scrap_id;

            SELECT * INTO v_scrap FROM public.scrap_inventory WHERE id = v_scrap_id;

            IF NOT FOUND OR v_scrap.status <> 'in_storage' THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'INVALID_SCRAP_ITEM',
                    'error_message', 'One of those scrap items is no longer in storage. Refresh and try again.',
                    'details',       json_build_object('scrap_inventory_id', v_scrap_id)
                )::text;
            END IF;
            IF v_scrap.location_id <> v_location THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'WRONG_WORKSHOP',
                    'error_message', format('"%s" is held at another workshop.', v_scrap.part_name_snapshot),
                    'details',       null
                )::text;
            END IF;
            IF v_quantity > v_scrap.quantity_snapshot THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'QUANTITY_EXCEEDS_SCRAP',
                    'error_message', format('Only %s of "%s" is in scrap.', v_scrap.quantity_snapshot, v_scrap.part_name_snapshot),
                    'details',       null
                )::text;
            END IF;

            v_part_id := v_scrap.part_id_snapshot;
        ELSE
            v_part_id := NULLIF(v_line->>'original_part_id', '')::uuid;

            IF v_comment IS NULL THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'MISSING_COMMENT',
                    'error_message', 'A comment is required for a part that is not in the scrap list.',
                    'details',       null
                )::text;
            END IF;
        END IF;

        -- Locked so two invoices cannot each create a refurbished part for one original.
        SELECT name, part_number, unit INTO v_part_name, v_part_number, v_part_unit
        FROM   public.parts WHERE id = v_part_id FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVALID_PART',
                'error_message', 'Choose the original part for every line.',
                'details',       null
            )::text;
        END IF;

        -- Matching on either side means a refurbished part that is scrapped and
        -- refurbished again goes back to the same part.
        v_refurb_id := NULL;
        SELECT refurbished_part_id INTO v_refurb_id
        FROM   public.refurbished_part_links
        WHERE  original_part_id = v_part_id OR refurbished_part_id = v_part_id;

        IF v_refurb_id IS NULL THEN
            INSERT INTO public.parts (name, part_number, unit, quantity_in_stock)
            VALUES (v_part_name || ' (Refurbished)', v_part_number, v_part_unit, 0)
            RETURNING id INTO v_refurb_id;

            INSERT INTO public.refurbished_part_links (refurbished_part_id, original_part_id)
            VALUES (v_refurb_id, v_part_id);
        END IF;

        -- The insert trigger adds the stock at the invoice's workshop.
        INSERT INTO public.purchase_invoice_items (invoice_id, part_id, quantity, unit_price, gst_rate)
        VALUES (v_invoice_id, v_refurb_id, v_quantity, v_unit_price, COALESCE((v_line->>'gst_rate')::numeric, 0))
        RETURNING id INTO v_item_id;

        v_final_scrap := NULL;
        IF v_scrap_id IS NOT NULL THEN
            IF v_quantity = v_scrap.quantity_snapshot THEN
                UPDATE public.scrap_inventory
                SET    status = 'refurbished', updated_at = now(), updated_by = auth.uid()
                WHERE  id = v_scrap_id;

                v_final_scrap := v_scrap_id;
            ELSE
                -- The original row keeps the remainder, so a sale or write-off of it
                -- still takes a whole row.
                UPDATE public.scrap_inventory
                SET    quantity_snapshot = quantity_snapshot - v_quantity,
                       updated_at = now(), updated_by = auth.uid()
                WHERE  id = v_scrap_id;

                INSERT INTO public.scrap_inventory (
                    source_ticket_id, source_job_card_id, source_issue_id,
                    source_issue_part_id, source_vehicle_number, source_audit_reason_id,
                    part_id_snapshot, part_name_snapshot, part_number_snapshot,
                    quantity_snapshot, unit_snapshot, description, notes, photos, status,
                    received_by, received_at, current_location,
                    outsource_part_disposition_snapshot,
                    outsource_vendor_credit_amount_snapshot,
                    location_id, created_by, updated_by
                ) VALUES (
                    v_scrap.source_ticket_id, v_scrap.source_job_card_id, v_scrap.source_issue_id,
                    v_scrap.source_issue_part_id, v_scrap.source_vehicle_number, v_scrap.source_audit_reason_id,
                    v_scrap.part_id_snapshot, v_scrap.part_name_snapshot, v_scrap.part_number_snapshot,
                    v_quantity, v_scrap.unit_snapshot, v_scrap.description, v_scrap.notes, v_scrap.photos, 'refurbished',
                    v_scrap.received_by, v_scrap.received_at, v_scrap.current_location,
                    v_scrap.outsource_part_disposition_snapshot,
                    v_scrap.outsource_vendor_credit_amount_snapshot,
                    v_scrap.location_id, v_scrap.created_by, auth.uid()
                )
                RETURNING id INTO v_final_scrap;

                -- The insert trigger re-derives the workshop from the job card.
                UPDATE public.scrap_inventory
                SET    location_id = v_scrap.location_id
                WHERE  id = v_final_scrap;
            END IF;
        END IF;

        INSERT INTO public.scrap_refurbishments (
            purchase_invoice_item_id, scrap_inventory_id, original_part_id,
            refurbished_part_id, quantity, comment, created_by
        ) VALUES (
            v_item_id, v_final_scrap, v_part_id, v_refurb_id, v_quantity, v_comment, auth.uid()
        );
    END LOOP;

    SELECT COALESCE(sum(line_total), 0) INTO v_total
    FROM   public.purchase_invoice_items
    WHERE  invoice_id = v_invoice_id;

    -- Compared in numeric, as on a multi-vehicle invoice.
    IF v_total <> v_approved THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'AMOUNT_MISMATCH',
            'error_message', format('The parts add up to ₹%s; the approved amount is ₹%s.',
                                    to_char(v_total, 'FM999999999990.00'),
                                    to_char(v_approved, 'FM999999999990.00')),
            'details',       null
        )::text;
    END IF;

    UPDATE public.purchase_invoices SET total_amount = v_total WHERE id = v_invoice_id;

    -- The insert trigger submits it to finance.
    INSERT INTO public.outsource_invoices (
        purchase_invoice_id, date_of_activity, invoice_no, paid_by, invoice_value,
        approved_amount, advance_amount, maintenance_payment_status, payby_date, created_by
    ) VALUES (
        v_invoice_id, v_inv_date, btrim(p_invoice->>'invoice_number'), p_invoice->>'paid_by', v_inv_value,
        v_approved, v_advance, p_invoice->>'maintenance_payment_status', v_payby, auth.uid()
    );

    RETURN v_invoice_id;
END;
$$;

-- A refurbishment invoice's header is fixed once saved: its workshop because a move would
-- shift stock while the scrap stayed marked refurbished, and the rest because finance
-- reviews it. The total is not listed — it follows the lines, which are locked already.
CREATE FUNCTION public.guard_refurbishment_invoice_header() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM   public.purchase_invoice_items pii
        JOIN   public.scrap_refurbishments sr ON sr.purchase_invoice_item_id = pii.id
        WHERE  pii.invoice_id = NEW.id
    ) THEN
        RAISE EXCEPTION 'This invoice came from a scrap refurbishment, so only its notes can be changed.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER trigger_guard_refurbishment_invoice_location ON public.purchase_invoices;
DROP FUNCTION public.guard_refurbishment_invoice_location();

CREATE TRIGGER trigger_guard_refurbishment_invoice_header
    BEFORE UPDATE ON public.purchase_invoices
    FOR EACH ROW
    WHEN ((OLD.location_id, OLD.supplier_id, OLD.supplier_name, OLD.invoice_number, OLD.invoice_date, OLD.invoice_file_url)
          IS DISTINCT FROM
          (NEW.location_id, NEW.supplier_id, NEW.supplier_name, NEW.invoice_number, NEW.invoice_date, NEW.invoice_file_url))
    EXECUTE FUNCTION public.guard_refurbishment_invoice_header();

-- The ledgers, the awaiting-acceptance count and the summary tiles take the supplier of
-- a purchase invoice as a third owner. Signatures and return columns are unchanged.
CREATE OR REPLACE FUNCTION public.supplier_ledger_lines() RETURNS TABLE(supplier_id uuid, entry_at timestamp with time zone, seq integer, line_id uuid, kind text, amount numeric, counts boolean, due_date date, invoice_id uuid, invoice_no text, job_card_number integer, batch_number integer, detail jsonb)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with inv as (
      select oi.*,
             coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id) as sup_id,
             public.invoice_submitted_day(oi)               as submitted_day,
             coalesce(oi.accepted_at, oi.updated_at)        as entered_at,
             oi.paid_by in ('NVS 659 Manjunath', 'NVS 2954 Gokilavanan', 'PCN') as by_person,
             jc.job_card_number, bs.batch_number
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
             'purchase_invoice_id', inv.purchase_invoice_id)
  from   inv join public.suppliers s on s.id = inv.sup_id

  union all

  select inv.sup_id, inv.entered_at, 2, inv.id, 'advance',
         -inv.advance_amount, true, null,
         inv.id, inv.invoice_no, inv.job_card_number, inv.batch_number,
         jsonb_build_object('paid_by', inv.paid_by, 'advance_by_person', inv.by_person,
                            'purchase_invoice_id', inv.purchase_invoice_id)
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
             'purchase_invoice_id', oi.purchase_invoice_id)
  from   public.outsource_invoices oi
  left join public.job_cards         jc on jc.id = oi.job_card_id
  left join public.batch_services    bs on bs.id = oi.batch_service_id
  left join public.purchase_invoices pi on pi.id = oi.purchase_invoice_id
  left join public.suppliers         s  on s.id  = coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id)
  where  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
    and  (bs.id is null or bs.status = 'Active')
    and  oi.advance_amount > 0
    and  oi.paid_by in ('NVS 659 Manjunath', 'NVS 2954 Gokilavanan', 'PCN')

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

CREATE OR REPLACE FUNCTION public.get_supplier_balances(p_supplier_id uuid DEFAULT NULL::uuid) RETURNS TABLE(supplier_id uuid, entity_name text, credit_days integer, outstanding numeric, overdue numeric, due_this_wednesday numeric, due_next_wednesday numeric, later numeric, this_wednesday date, last_payment_on date, last_reconciled_on date, awaiting_acceptance bigint)
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
          AND  oi.finance_payment_status IN ('New', 'Hold')
          AND  (bs.id IS NULL OR bs.status = 'Active')
        GROUP  BY 1
    )
    SELECT s.id, s.entity_name, s.payment_terms_days,
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

CREATE OR REPLACE FUNCTION public.get_outsource_invoice_summary(p_maintenance_payment_status text[] DEFAULT NULL::text[], p_paid_by text[] DEFAULT NULL::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_finance_payment_status text[] DEFAULT NULL::text[]) RETURNS TABLE(new_count bigint, hold_count bigint, reject_count bigint, accepted_count bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'New')      AS new_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Hold')     AS hold_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Reject')   AS reject_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Accepted') AS accepted_count
    FROM  outsource_invoices     oi
    LEFT JOIN job_cards          jc ON jc.id = oi.job_card_id
    LEFT JOIN batch_services     bs ON bs.id = oi.batch_service_id
    WHERE (bs.status = 'Active' OR jc.status = 'Completed' OR oi.purchase_invoice_id IS NOT NULL)
      AND (p_maintenance_payment_status IS NULL OR oi.maintenance_payment_status = ANY(p_maintenance_payment_status))
      AND (p_finance_payment_status     IS NULL OR oi.finance_payment_status     = ANY(p_finance_payment_status))
      AND (p_paid_by                    IS NULL OR oi.paid_by                    = ANY(p_paid_by))
      AND (p_date_from                  IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to                    IS NULL OR oi.date_of_activity <= p_date_to)
$$;
