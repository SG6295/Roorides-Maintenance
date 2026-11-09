-- MAIN-123: a stock-audit mismatch can be explained by several lines (quantity, reason,
-- comment), and every Damaged line reaches scrap when the audit completes.

CREATE TABLE public.stock_audit_item_reasons (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    audit_item_id uuid NOT NULL REFERENCES public.stock_audit_items(id) ON DELETE CASCADE,
    quantity numeric(10,2) NOT NULL,
    reason text NOT NULL,
    notes text,
    sort_order integer DEFAULT 0 NOT NULL,
    CONSTRAINT stock_audit_item_reasons_quantity_check CHECK (quantity > 0),
    CONSTRAINT stock_audit_item_reasons_reason_check
        CHECK (reason = ANY (ARRAY['missing'::text, 'stolen'::text, 'damaged'::text, 'found'::text, 'other'::text]))
);

CREATE INDEX idx_stock_audit_item_reasons_item ON public.stock_audit_item_reasons (audit_item_id);

COMMENT ON TABLE public.stock_audit_item_reasons IS 'Why a counted part differed from the system. The lines of a part must add up to the absolute variance before the audit can complete.';

ALTER TABLE public.stock_audit_item_reasons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Exec and finance view stock_audit_item_reasons" ON public.stock_audit_item_reasons
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role = ANY (ARRAY['finance'::text, 'super_admin'::text, 'maintenance_exec'::text])
    ));

INSERT INTO public.stock_audit_item_reasons (audit_item_id, quantity, reason, notes)
SELECT id, abs(variance), reason, reason_notes
FROM   public.stock_audit_items
WHERE  reason IS NOT NULL AND COALESCE(variance, 0) <> 0;

COMMENT ON COLUMN public.stock_audit_items.reason IS 'Superseded by stock_audit_item_reasons (MAIN-123). No longer written or read.';
COMMENT ON COLUMN public.stock_audit_items.reason_notes IS 'Superseded by stock_audit_item_reasons (MAIN-123). No longer written or read.';

-- Scrap can now come from an audit instead of a job card.
ALTER TABLE public.scrap_inventory
    ALTER COLUMN source_ticket_id DROP NOT NULL,
    ALTER COLUMN source_job_card_id DROP NOT NULL,
    ALTER COLUMN source_issue_id DROP NOT NULL,
    ALTER COLUMN source_vehicle_number DROP NOT NULL,
    ADD COLUMN source_audit_reason_id uuid REFERENCES public.stock_audit_item_reasons(id),
    ADD CONSTRAINT scrap_inventory_one_source_check
        CHECK (num_nonnulls(source_job_card_id, source_audit_reason_id) = 1);

CREATE INDEX idx_scrap_inventory_audit_reason_id ON public.scrap_inventory (source_audit_reason_id);

COMMENT ON COLUMN public.scrap_inventory.source_audit_reason_id IS 'The Damaged line of a stock audit this item came from. Exactly one of this and source_job_card_id is set.';

-- Without this an audit's scrap would fall through to the default workshop.
CREATE OR REPLACE FUNCTION public.set_scrap_location_from_job_card() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    IF NEW.source_job_card_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT jc.location_id INTO NEW.location_id
    FROM   public.job_cards jc
    WHERE  jc.id = NEW.source_job_card_id;

    IF NEW.location_id IS NULL THEN
        NEW.location_id := 'a1e1d4c0-0000-4000-8000-000000000001';
    END IF;

    RETURN NEW;
END;
$$;

-- p_items is now [{ part_id, lines: [{ quantity, reason, notes }] }]. The lines given
-- replace the part's saved ones; they may fall short of the mismatch while work is in
-- progress, and complete_stock_audit is what insists they add up.
CREATE OR REPLACE FUNCTION public.set_stock_audit_reasons(p_audit_id uuid, p_items jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_role      text;
    v_status    text;
    r           RECORD;
    l           RECORD;
    v_item_id   uuid;
    v_variance  numeric;
    v_part_name text;
    v_total     numeric;
    v_sort      integer;
BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can explain an audit mismatch.';
    END IF;

    SELECT status INTO v_status FROM public.stock_audits WHERE id = p_audit_id FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status <> 'review' THEN
        RAISE EXCEPTION 'Reasons can only be set while the audit is under review. This one is %.', v_status;
    END IF;

    FOR r IN
        SELECT (elem->>'part_id')::uuid AS part_id,
               COALESCE(elem->'lines', '[]'::jsonb) AS lines
        FROM   jsonb_array_elements(p_items) AS elem
    LOOP
        v_item_id := NULL;
        SELECT id, variance, part_name_snapshot INTO v_item_id, v_variance, v_part_name
        FROM   public.stock_audit_items
        WHERE  audit_id = p_audit_id AND part_id = r.part_id;

        IF v_item_id IS NULL THEN
            RAISE EXCEPTION 'One of those parts is not part of this audit.';
        END IF;

        DELETE FROM public.stock_audit_item_reasons WHERE audit_item_id = v_item_id;

        v_total := 0;
        v_sort  := 0;

        FOR l IN
            SELECT round((e->>'quantity')::numeric, 2) AS quantity,
                   NULLIF(btrim(COALESCE(e->>'reason', '')), '') AS reason,
                   NULLIF(btrim(COALESCE(e->>'notes',  '')), '') AS notes
            FROM   jsonb_array_elements(r.lines) AS e
        LOOP
            IF l.quantity IS NULL OR l.quantity <= 0 THEN
                RAISE EXCEPTION 'Every reason needs a quantity above zero (%).', v_part_name;
            END IF;
            IF l.reason IS NULL THEN
                RAISE EXCEPTION 'Every line needs a reason (%).', v_part_name;
            END IF;
            IF l.reason NOT IN ('missing', 'stolen', 'damaged', 'found', 'other') THEN
                RAISE EXCEPTION 'Unknown reason "%".', l.reason;
            END IF;
            IF l.reason = 'other' AND l.notes IS NULL THEN
                RAISE EXCEPTION 'A note is required when the reason is Other (%).', v_part_name;
            END IF;
            IF l.reason = 'found' AND COALESCE(v_variance, 0) <= 0 THEN
                RAISE EXCEPTION 'Found / excess only applies where more was counted than expected (%).', v_part_name;
            END IF;
            IF l.reason IN ('missing', 'stolen', 'damaged') AND COALESCE(v_variance, 0) >= 0 THEN
                RAISE EXCEPTION 'Missing, Stolen and Damaged only apply to a shortfall (%).', v_part_name;
            END IF;

            INSERT INTO public.stock_audit_item_reasons (audit_item_id, quantity, reason, notes, sort_order)
            VALUES (v_item_id, l.quantity, l.reason, l.notes, v_sort);

            v_total := v_total + l.quantity;
            v_sort  := v_sort + 1;
        END LOOP;

        IF v_total > abs(COALESCE(v_variance, 0)) THEN
            RAISE EXCEPTION 'The quantities for "%" add up to %, more than the difference of %.',
                v_part_name, v_total, abs(COALESCE(v_variance, 0));
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_stock_audit_counts(p_audit_id uuid, p_counts jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_role     text;
    v_name     text;
    v_status   text;
    v_location uuid;
    r          RECORD;
    v_blank    integer;
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
        SELECT (elem->>'part_id')::uuid        AS part_id,
               (elem->>'counted_qty')::numeric AS counted_qty
        FROM   jsonb_array_elements(p_counts) AS elem
    LOOP
        IF r.part_id IS NULL OR r.counted_qty IS NULL THEN
            RAISE EXCEPTION 'Every row on the sheet needs a part and a counted quantity.';
        END IF;
        IF r.counted_qty < 0 THEN
            RAISE EXCEPTION 'A counted quantity cannot be negative.';
        END IF;

        -- A changed count makes the explanation of the old difference meaningless.
        DELETE FROM public.stock_audit_item_reasons l
        USING  public.stock_audit_items i
        WHERE  l.audit_item_id = i.id
          AND  i.audit_id = p_audit_id
          AND  i.part_id = r.part_id
          AND  i.counted_qty IS DISTINCT FROM r.counted_qty;

        UPDATE public.stock_audit_items
        SET counted_qty = r.counted_qty
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

CREATE OR REPLACE FUNCTION public.complete_stock_audit(p_audit_id uuid) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_role        text;
    v_name        text;
    v_status      text;
    v_location    uuid;
    r             RECORD;
    v_live        numeric;
    v_unit_value  numeric;
    v_total       integer := 0;
    v_var_parts   integer := 0;
    v_net_units   numeric := 0;
    v_net_value   numeric := 0;
    v_unvalued    integer := 0;
    v_unexplained integer;
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
    FROM   public.stock_audit_items i
    WHERE  i.audit_id = p_audit_id
      AND  i.variance <> 0
      AND  COALESCE((SELECT sum(l.quantity)
                     FROM   public.stock_audit_item_reasons l
                     WHERE  l.audit_item_id = i.id), 0) <> abs(i.variance);

    IF v_unexplained > 0 THEN
        RAISE EXCEPTION '% mismatch(es) still need reasons that add up to the difference before the audit can be completed.', v_unexplained;
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

            -- One scrap item per Damaged line, so each keeps its own comment. Parts set
            -- to skip scrap at job card closure skip it here too.
            INSERT INTO public.scrap_inventory (
                source_audit_reason_id, part_id_snapshot, part_name_snapshot,
                part_number_snapshot, quantity_snapshot, unit_snapshot, notes,
                status, location_id, created_by
            )
            SELECT l.id, r.part_id, r.part_name_snapshot, r.part_number_snapshot,
                   l.quantity, r.unit_snapshot, l.notes,
                   'in_storage'::public.scrap_item_status, v_location, auth.uid()
            FROM   public.stock_audit_item_reasons l
            JOIN   public.parts p ON p.id = r.part_id
            WHERE  l.audit_item_id = r.id
              AND  l.reason = 'damaged'
              AND  NOT p.default_exclude_from_scrap;
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
