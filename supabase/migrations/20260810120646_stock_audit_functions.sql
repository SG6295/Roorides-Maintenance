-- The only supported ways to run a stock audit (MAIN-30).
--
-- All SECURITY DEFINER with the role check inside the body, mirroring transfer_stock():
-- the tables carry SELECT policies only, so nothing can start, count or complete an audit
-- except through here.
--
-- Stock is only ever moved by apply_part_stock_delta(), which takes a FOR UPDATE row lock,
-- creates the (part, location) row if it is missing and refuses to drive a workshop
-- negative. parts.quantity_in_stock is never written directly — trg_sync_part_total_stock
-- recalculates it from part_stock.

-- ── Start ─────────────────────────────────────────────────────────────────────
-- Snapshots what the app believes is on the shelves right now. That snapshot is frozen:
-- everything the audit later reports is measured against it.
CREATE OR REPLACE FUNCTION public.start_stock_audit(
    p_location_id uuid,
    p_notes       text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_audit_id    uuid;
    v_role        text;
    v_name        text;
    v_open_by     text;
    v_open_at     timestamp without time zone;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can run a stock audit.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.workshop_locations WHERE id = p_location_id AND is_active
    ) THEN
        RAISE EXCEPTION 'That workshop is not an active location.';
    END IF;

    SELECT started_by_name, started_at INTO v_open_by, v_open_at
    FROM   public.stock_audits
    WHERE  location_id = p_location_id
      AND  status IN ('counting', 'review');

    IF v_open_at IS NOT NULL THEN
        RAISE EXCEPTION 'An audit is already open at this workshop, started by % on %. Complete or cancel it before starting another.',
            COALESCE(NULLIF(v_open_by, ''), 'someone'),
            to_char(v_open_at, 'DD Mon YYYY');
    END IF;

    INSERT INTO public.stock_audits (location_id, started_by, started_by_name, notes)
    VALUES (p_location_id, auth.uid(), COALESCE(v_name, ''),
            NULLIF(btrim(COALESCE(p_notes, '')), ''))
    RETURNING id INTO v_audit_id;

    -- Only what is actually stocked here. Printing the whole catalogue would mean 300+
    -- rows of zeroes to write out by hand at a workshop that stocks seven parts, and a
    -- blank row blocks the upload. Anything physically present but unlisted comes back
    -- on one of the sheet's blank "found" rows instead.
    --
    -- A workshop with no stock at all yields an empty sheet on purpose: that is how a new
    -- workshop's opening stock gets entered, entirely through found rows.
    INSERT INTO public.stock_audit_items (
        audit_id, part_id, part_name_snapshot, part_number_snapshot, unit_snapshot, system_qty
    )
    SELECT v_audit_id, p.id, p.name, p.part_number, COALESCE(p.unit, 'pcs'), ps.quantity
    FROM   public.part_stock ps
    JOIN   public.parts p ON p.id = ps.part_id
    WHERE  ps.location_id = p_location_id
      AND  ps.quantity > 0;

    RETURN v_audit_id;
END;
$$;

-- ── Upload the filled sheet ───────────────────────────────────────────────────
-- p_counts: [{ "part_id": uuid, "counted_qty": numeric }, ...]
-- Parts not printed on the sheet are accepted as found rows. Re-uploading a corrected
-- sheet is allowed while the audit is under review; only rows whose number actually
-- changed lose the reason already given for them.
CREATE OR REPLACE FUNCTION public.submit_stock_audit_counts(
    p_audit_id uuid,
    p_counts   jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_role       text;
    v_name       text;
    v_status     text;
    v_location   uuid;
    r            RECORD;
    v_blank      integer;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can upload a count sheet.';
    END IF;

    SELECT status, location_id INTO v_status, v_location
    FROM   public.stock_audits WHERE id = p_audit_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status NOT IN ('counting', 'review') THEN
        RAISE EXCEPTION 'This audit is already % and cannot take new counts.', v_status;
    END IF;

    FOR r IN
        SELECT (elem->>'part_id')::uuid       AS part_id,
               (elem->>'counted_qty')::numeric AS counted_qty
        FROM   jsonb_array_elements(p_counts) AS elem
    LOOP
        IF r.part_id IS NULL OR r.counted_qty IS NULL THEN
            RAISE EXCEPTION 'Every row on the sheet needs a part and a counted quantity.';
        END IF;
        IF r.counted_qty < 0 THEN
            RAISE EXCEPTION 'A counted quantity cannot be negative.';
        END IF;

        UPDATE public.stock_audit_items
        SET counted_qty  = r.counted_qty,
            reason       = CASE WHEN counted_qty IS DISTINCT FROM r.counted_qty
                                THEN NULL ELSE reason END,
            reason_notes = CASE WHEN counted_qty IS DISTINCT FROM r.counted_qty
                                THEN NULL ELSE reason_notes END
        WHERE audit_id = p_audit_id AND part_id = r.part_id;

        IF NOT FOUND THEN
            -- Written onto a blank row: stock the app did not know was here.
            INSERT INTO public.stock_audit_items (
                audit_id, part_id, part_name_snapshot, part_number_snapshot,
                unit_snapshot, system_qty, counted_qty, was_found_row
            )
            SELECT p_audit_id, p.id, p.name, p.part_number, COALESCE(p.unit, 'pcs'),
                   COALESCE(ps.quantity, 0), r.counted_qty, true
            FROM   public.parts p
            LEFT   JOIN public.part_stock ps
                   ON ps.part_id = p.id AND ps.location_id = v_location
            WHERE  p.id = r.part_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'A part written onto the sheet is not in the catalogue. Add it under Parts Catalog first, then upload again.';
            END IF;
        END IF;
    END LOOP;

    -- Nothing printed on the sheet may come back blank.
    SELECT count(*) INTO v_blank
    FROM   public.stock_audit_items
    WHERE  audit_id = p_audit_id AND counted_qty IS NULL;

    IF v_blank > 0 THEN
        RAISE EXCEPTION '% part(s) on the sheet have no counted quantity. Every row must be filled in before the sheet can be uploaded.', v_blank;
    END IF;

    UPDATE public.stock_audits
    SET status                  = 'review',
        counts_uploaded_by      = auth.uid(),
        counts_uploaded_by_name = COALESCE(v_name, ''),
        counts_uploaded_at      = now()
    WHERE id = p_audit_id;
END;
$$;

-- ── Reasons ───────────────────────────────────────────────────────────────────
-- p_items: [{ "part_id": uuid, "reason": text, "notes": text }, ...]
CREATE OR REPLACE FUNCTION public.set_stock_audit_reasons(
    p_audit_id uuid,
    p_items    jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_role      text;
    v_status    text;
    r           RECORD;
    v_variance  numeric;
    v_part_name text;
BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can explain an audit mismatch.';
    END IF;

    SELECT status INTO v_status FROM public.stock_audits WHERE id = p_audit_id;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status <> 'review' THEN
        RAISE EXCEPTION 'Reasons can only be set while the audit is under review. This one is %.', v_status;
    END IF;

    FOR r IN
        SELECT (elem->>'part_id')::uuid AS part_id,
               NULLIF(btrim(COALESCE(elem->>'reason', '')), '') AS reason,
               NULLIF(btrim(COALESCE(elem->>'notes',  '')), '') AS notes
        FROM   jsonb_array_elements(p_items) AS elem
    LOOP
        SELECT variance, part_name_snapshot INTO v_variance, v_part_name
        FROM   public.stock_audit_items
        WHERE  audit_id = p_audit_id AND part_id = r.part_id;

        IF v_part_name IS NULL THEN
            RAISE EXCEPTION 'One of those parts is not part of this audit.';
        END IF;

        IF r.reason IS NOT NULL THEN
            IF r.reason NOT IN ('missing', 'stolen', 'damaged', 'found', 'other') THEN
                RAISE EXCEPTION 'Unknown reason "%".', r.reason;
            END IF;
            IF r.reason = 'other' AND r.notes IS NULL THEN
                RAISE EXCEPTION 'A note is required when the reason is Other (%).', v_part_name;
            END IF;
            IF r.reason = 'found' AND COALESCE(v_variance, 0) <= 0 THEN
                RAISE EXCEPTION 'Found / excess only applies where more was counted than expected (%).', v_part_name;
            END IF;
            IF r.reason IN ('missing', 'stolen', 'damaged') AND COALESCE(v_variance, 0) >= 0 THEN
                RAISE EXCEPTION 'Missing, Stolen and Damaged only apply to a shortfall (%).', v_part_name;
            END IF;
        END IF;

        UPDATE public.stock_audit_items
        SET reason = r.reason, reason_notes = r.notes
        WHERE audit_id = p_audit_id AND part_id = r.part_id;
    END LOOP;
END;
$$;

-- ── Complete ──────────────────────────────────────────────────────────────────
-- Posts the difference the audit FOUND on top of whatever stock is by now, rather than
-- setting stock to the counted number. If a mechanic legitimately used 2 of a part while
-- the audit was open, that consumption stays applied and the audit's own shortfall lands
-- on top of it. Setting stock to the counted figure would silently hand those 2 back.
CREATE OR REPLACE FUNCTION public.complete_stock_audit(p_audit_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_role         text;
    v_name         text;
    v_status       text;
    v_location     uuid;
    r              RECORD;
    v_live         numeric;
    v_unit_value   numeric;
    v_total        integer := 0;
    v_var_parts    integer := 0;
    v_net_units    numeric := 0;
    v_net_value    numeric := 0;
    v_unvalued     integer := 0;
    v_unexplained  integer;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can complete a stock audit.';
    END IF;

    SELECT status, location_id INTO v_status, v_location
    FROM   public.stock_audits WHERE id = p_audit_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status <> 'review' THEN
        RAISE EXCEPTION 'Only an audit under review can be completed. This one is %.', v_status;
    END IF;

    SELECT count(*) INTO v_unexplained
    FROM   public.stock_audit_items
    WHERE  audit_id = p_audit_id AND variance <> 0 AND reason IS NULL;

    IF v_unexplained > 0 THEN
        RAISE EXCEPTION '% mismatch(es) still need a reason before the audit can be completed.', v_unexplained;
    END IF;

    FOR r IN
        SELECT * FROM public.stock_audit_items
        WHERE  audit_id = p_audit_id
        ORDER  BY part_name_snapshot
    LOOP
        SELECT quantity INTO v_live
        FROM   public.part_stock
        WHERE  part_id = r.part_id AND location_id = v_location;
        v_live := COALESCE(v_live, 0);

        -- Latest purchase price per unit, net of discount and before GST — the same
        -- arithmetic purchase_invoice_items.line_total uses.
        SELECT (pii.quantity * pii.unit_price - pii.discount_amount) / NULLIF(pii.quantity, 0)
        INTO   v_unit_value
        FROM   public.purchase_invoice_items pii
        JOIN   public.purchase_invoices pi ON pi.id = pii.invoice_id
        WHERE  pii.part_id = r.part_id
        ORDER  BY pi.invoice_date DESC, pi.created_at DESC
        LIMIT  1;

        IF COALESCE(r.variance, 0) <> 0 THEN
            -- apply_part_stock_delta guards this too, but it cannot know the count is
            -- what pushed the workshop negative, so check here for a usable message.
            IF v_live + r.variance < 0 THEN
                RAISE EXCEPTION 'Cannot write off % of "%": only % left at this workshop after activity during the audit. Re-count that part and run a fresh audit.',
                    abs(r.variance), r.part_name_snapshot, v_live;
            END IF;

            PERFORM public.apply_part_stock_delta(r.part_id, v_location, r.variance);

            v_var_parts := v_var_parts + 1;
            v_net_units := v_net_units + r.variance;

            IF v_unit_value IS NULL THEN
                v_unvalued := v_unvalued + 1;
            ELSE
                v_net_value := v_net_value + round(r.variance * v_unit_value, 2);
            END IF;
        END IF;

        UPDATE public.stock_audit_items
        SET moved_during_audit  = v_live - r.system_qty,
            applied_delta       = COALESCE(r.variance, 0),
            final_qty           = v_live + COALESCE(r.variance, 0),
            unit_value_snapshot = v_unit_value,
            variance_value      = CASE
                                      WHEN v_unit_value IS NULL THEN NULL
                                      ELSE round(COALESCE(r.variance, 0) * v_unit_value, 2)
                                  END
        WHERE id = r.id;

        v_total := v_total + 1;
    END LOOP;

    UPDATE public.stock_audits
    SET status            = 'completed',
        completed_by      = auth.uid(),
        completed_by_name = COALESCE(v_name, ''),
        completed_at      = now(),
        total_parts       = v_total,
        variance_parts    = v_var_parts,
        net_units         = v_net_units,
        net_value         = v_net_value,
        unvalued_parts    = v_unvalued
    WHERE id = p_audit_id;

    RETURN p_audit_id;
END;
$$;

-- ── Cancel ────────────────────────────────────────────────────────────────────
-- Abandons an audit without touching stock, freeing the workshop for another one.
CREATE OR REPLACE FUNCTION public.cancel_stock_audit(
    p_audit_id uuid,
    p_reason   text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_role   text;
    v_name   text;
    v_status text;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can cancel a stock audit.';
    END IF;

    SELECT status INTO v_status FROM public.stock_audits WHERE id = p_audit_id FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status NOT IN ('counting', 'review') THEN
        RAISE EXCEPTION 'Only an audit still in progress can be cancelled. This one is %.', v_status;
    END IF;

    UPDATE public.stock_audits
    SET status            = 'cancelled',
        cancelled_by      = auth.uid(),
        cancelled_by_name = COALESCE(v_name, ''),
        cancelled_at      = now(),
        cancel_reason     = NULLIF(btrim(COALESCE(p_reason, '')), '')
    WHERE id = p_audit_id;
END;
$$;

-- ── What moved while the audit was open ───────────────────────────────────────
-- Everything that legitimately changed stock at this workshop since the count sheet was
-- generated. Drives the warning on a review row: without it, a part whose final figure
-- differs from the counted figure looks like a bug rather than a job card doing its job.
CREATE OR REPLACE FUNCTION public.stock_audit_movements(p_audit_id uuid)
RETURNS TABLE (
    part_id        uuid,
    source         text,
    quantity       numeric,
    reference      text,
    vehicle_number text,
    occurred_at    timestamp without time zone
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    WITH a AS (
        SELECT id, location_id, started_at FROM public.stock_audits WHERE id = p_audit_id
    )
    -- Consumed on a job card. Outsource job cards never touch stock, so they are excluded
    -- here exactly as deduct_part_from_inventory() excludes them.
    SELECT ip.part_id,
           'consumption'::text,
           -ip.quantity_used,
           'JC-' || jc.job_card_number::text,
           jc.vehicle_number,
           ip.added_at
    FROM   a
    JOIN   public.job_cards  jc ON jc.location_id = a.location_id AND jc.type <> 'Outsource'
    JOIN   public.issues     i  ON i.job_card_id = jc.id
    JOIN   public.issue_parts ip ON ip.issue_id = i.id
    WHERE  ip.added_at > a.started_at

    UNION ALL

    -- Inwarded on a purchase invoice.
    SELECT pii.part_id,
           'purchase'::text,
           pii.quantity,
           pi.invoice_number,
           NULL::text,
           pi.created_at
    FROM   a
    JOIN   public.purchase_invoices      pi  ON pi.location_id = a.location_id
    JOIN   public.purchase_invoice_items pii ON pii.invoice_id = pi.id
    WHERE  pi.created_at > a.started_at

    UNION ALL

    -- Moved to or from another workshop.
    SELECT sti.part_id,
           CASE WHEN st.to_location_id = a.location_id
                THEN 'transfer_in' ELSE 'transfer_out' END,
           CASE WHEN st.to_location_id = a.location_id
                THEN sti.quantity ELSE -sti.quantity END,
           wl.name,
           NULL::text,
           st.transferred_at
    FROM   a
    JOIN   public.stock_transfers st
           ON (st.from_location_id = a.location_id OR st.to_location_id = a.location_id)
    JOIN   public.stock_transfer_items sti ON sti.transfer_id = st.id
    JOIN   public.workshop_locations wl
           ON wl.id = CASE WHEN st.to_location_id = a.location_id
                           THEN st.from_location_id ELSE st.to_location_id END
    WHERE  st.transferred_at > a.started_at

    ORDER BY 6 DESC;
$$;
