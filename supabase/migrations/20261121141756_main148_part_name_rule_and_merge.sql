-- MAIN-148: the Parts Catalog refuses a duplicate part name, and the 9 existing duplicate
-- sets are merged first. Two names are the same part when they match ignoring capitals and
-- extra spaces (at either end, or doubled in the middle) — part_name_key().
-- All in one transaction: if any before/after check differs, nothing is changed.

-- ── 1. The name key ─────────────────────────────────────────────────────────────────
CREATE FUNCTION public.part_name_key(p_name text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$ SELECT lower(btrim(regexp_replace(p_name, '[[:space:]]+', ' ', 'g'))) $$;

COMMENT ON FUNCTION public.part_name_key(text) IS
  'A part name in lower case with spaces trimmed and runs of spaces made one — what part-name uniqueness matches on (MAIN-148). Mirrored by partNameKey() in src/utils/partName.js.';

-- Sections 2–6 run as one block, so the merge is all-or-nothing however the migration is
-- run: any failed check undoes every part of it.
DO $m148$
DECLARE
    v_other text;
    v_diff  text;
BEGIN
-- Nothing else may write a part or its references while they are merged.
LOCK TABLE public.parts, public.part_stock, public.purchase_invoice_items, public.issue_parts,
           public.stock_transfer_items, public.stock_audit_items, public.refurbished_part_links,
           public.scrap_refurbishments, public.scrap_inventory, public.scrap_excluded_parts
    IN SHARE ROW EXCLUSIVE MODE;

-- ── 2. The sets to merge, as agreed in MAIN-148 ─────────────────────────────────────
-- Each survivor gets this name and unit, and no part number (blank, or the "1" cleared).
CREATE TEMP TABLE m148_sets (name_key text PRIMARY KEY, name text NOT NULL, unit text NOT NULL);
INSERT INTO m148_sets VALUES
    ('retreading tyre 235/70',  'Retreading Tyre 235/70',  'No''s'),
    ('battery xp 1000',         'Battery XP 1000',         'No''s'),
    ('295/80 retreading tyres', '295/80 Retreading tyres', 'No''s'),
    ('starter bendex assy',     'Starter Bendex Assy',     'Pcs'),
    ('sol switch assy',         'Sol Switch Assy',         'Pcs'),
    ('piano switch',            'Piano Switch',            'pcs'),
    ('brush holder n/m',        'Brush Holder N/m',        'Pcs'),
    ('drag link assy',          'Drag link assy',          'No''s'),
    ('terminal spray',          'Terminal spray',          'No''s');

-- The oldest copy of each set survives.
CREATE TEMP TABLE m148_map AS
SELECT p.id AS old_id,
       first_value(p.id) OVER (PARTITION BY public.part_name_key(p.name) ORDER BY p.created_at, p.id) AS new_id,
       public.part_name_key(p.name) AS name_key,
       p.name, p.part_number, p.unit, p.quantity_in_stock
FROM   public.parts p
WHERE  public.part_name_key(p.name) IN (SELECT name_key FROM m148_sets);

    -- A duplicate the ticket did not agree on (one created since) stops the merge rather
    -- than having a survivor guessed for it.
    SELECT string_agg(k, ', ') INTO v_other
    FROM (SELECT public.part_name_key(name) k FROM public.parts GROUP BY 1 HAVING count(*) > 1) d
    WHERE k NOT IN (SELECT name_key FROM m148_sets);
    IF v_other IS NOT NULL THEN
        RAISE EXCEPTION 'MAIN-148: duplicate part names not in the agreed list: %', v_other;
    END IF;

    -- One stock audit line per part per audit: two copies on one audit would collide.
    IF EXISTS (SELECT 1 FROM public.stock_audit_items a JOIN m148_map m ON m.old_id = a.part_id
               GROUP BY a.audit_id, m.new_id HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'MAIN-148: a stock audit counts two copies of one part';
    END IF;

    -- refurbished_part_links allows one link per original.
    IF EXISTS (SELECT 1 FROM public.refurbished_part_links l JOIN m148_map m ON m.old_id = l.original_part_id
               GROUP BY m.new_id HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'MAIN-148: two copies of one part each have a refurbished part';
    END IF;

-- ── 3. What must not change ─────────────────────────────────────────────────────────
-- Stock per part name per workshop, each part's total, every invoice's total and lines,
-- and how much of each part every job card, purchase, transfer, audit and scrap row holds.
CREATE TEMP VIEW m148_figures AS
SELECT 'stock' AS what, public.part_name_key(p.name) || ' @ ' || ps.location_id AS item, sum(ps.quantity) AS value
FROM   public.part_stock ps JOIN public.parts p ON p.id = ps.part_id GROUP BY 1, 2
UNION ALL
SELECT 'total stock', public.part_name_key(name), sum(quantity_in_stock) FROM public.parts GROUP BY 1, 2
UNION ALL
SELECT 'invoice total', id::text, total_amount FROM public.purchase_invoices
UNION ALL
SELECT 'invoice lines', invoice_id::text, sum(line_total) FROM public.purchase_invoice_items GROUP BY 1, 2
UNION ALL
SELECT 'job card use', public.part_name_key(p.name), sum(x.quantity_used)
FROM   public.issue_parts x JOIN public.parts p ON p.id = x.part_id GROUP BY 1, 2
UNION ALL
SELECT 'purchase line', public.part_name_key(p.name), sum(x.quantity)
FROM   public.purchase_invoice_items x JOIN public.parts p ON p.id = x.part_id GROUP BY 1, 2
UNION ALL
SELECT 'transfer line', public.part_name_key(p.name), sum(x.quantity)
FROM   public.stock_transfer_items x JOIN public.parts p ON p.id = x.part_id GROUP BY 1, 2
UNION ALL
SELECT 'audit line', public.part_name_key(p.name), count(*)
FROM   public.stock_audit_items x JOIN public.parts p ON p.id = x.part_id GROUP BY 1, 2
UNION ALL
SELECT 'scrap row', public.part_name_key(p.name), sum(x.quantity_snapshot)
FROM   public.scrap_inventory x JOIN public.parts p ON p.id = x.part_id_snapshot GROUP BY 1, 2
UNION ALL
SELECT 'excluded from scrap', public.part_name_key(p.name), count(*)
FROM   public.scrap_excluded_parts x JOIN public.parts p ON p.id = x.part_id_snapshot GROUP BY 1, 2
UNION ALL
SELECT 'rows', t, n FROM (VALUES
    ('issue_parts',            (SELECT count(*) FROM public.issue_parts)),
    ('purchase_invoice_items', (SELECT count(*) FROM public.purchase_invoice_items)),
    ('stock_transfer_items',   (SELECT count(*) FROM public.stock_transfer_items)),
    ('stock_audit_items',      (SELECT count(*) FROM public.stock_audit_items)),
    ('refurbished_part_links', (SELECT count(*) FROM public.refurbished_part_links)),
    ('scrap_refurbishments',   (SELECT count(*) FROM public.scrap_refurbishments)),
    ('scrap_inventory',        (SELECT count(*) FROM public.scrap_inventory)),
    ('scrap_excluded_parts',   (SELECT count(*) FROM public.scrap_excluded_parts))
) r(t, n);

CREATE TEMP TABLE m148_before AS SELECT * FROM m148_figures;

-- ── 4. Merge ────────────────────────────────────────────────────────────────────────
-- Moving a purchase line must neither move stock (its triggers would take it off one copy
-- and add it to the other) nor be refused by the Accepted/Reject and refurbishment guards:
-- the stock is combined below instead. Same approach as MAIN-143's backfill.
ALTER TABLE public.purchase_invoice_items DISABLE TRIGGER USER;

UPDATE public.purchase_invoice_items x SET part_id = m.new_id FROM m148_map m WHERE x.part_id = m.old_id AND m.old_id <> m.new_id;
UPDATE public.issue_parts            x SET part_id = m.new_id FROM m148_map m WHERE x.part_id = m.old_id AND m.old_id <> m.new_id;
UPDATE public.stock_transfer_items   x SET part_id = m.new_id FROM m148_map m WHERE x.part_id = m.old_id AND m.old_id <> m.new_id;
UPDATE public.stock_audit_items      x SET part_id = m.new_id FROM m148_map m WHERE x.part_id = m.old_id AND m.old_id <> m.new_id;
UPDATE public.refurbished_part_links x SET original_part_id = m.new_id FROM m148_map m WHERE x.original_part_id = m.old_id AND m.old_id <> m.new_id;
UPDATE public.refurbished_part_links x SET refurbished_part_id = m.new_id FROM m148_map m WHERE x.refurbished_part_id = m.old_id AND m.old_id <> m.new_id;
UPDATE public.scrap_refurbishments   x SET original_part_id = m.new_id FROM m148_map m WHERE x.original_part_id = m.old_id AND m.old_id <> m.new_id;
UPDATE public.scrap_refurbishments   x SET refurbished_part_id = m.new_id FROM m148_map m WHERE x.refurbished_part_id = m.old_id AND m.old_id <> m.new_id;
-- Scrap keeps the name it recorded at the time; only the part it points at moves.
UPDATE public.scrap_inventory        x SET part_id_snapshot = m.new_id FROM m148_map m WHERE x.part_id_snapshot = m.old_id AND m.old_id <> m.new_id;
UPDATE public.scrap_excluded_parts   x SET part_id_snapshot = m.new_id FROM m148_map m WHERE x.part_id_snapshot = m.old_id AND m.old_id <> m.new_id;

ALTER TABLE public.purchase_invoice_items ENABLE TRIGGER USER;

-- Stock: each workshop's quantities added together on the survivor. part_stock's own
-- trigger keeps parts.quantity_in_stock equal to the sum.
CREATE TEMP TABLE m148_stock AS
SELECT m.new_id AS part_id, ps.location_id, sum(ps.quantity) AS quantity, max(ps.updated_at) AS updated_at
FROM   public.part_stock ps JOIN m148_map m ON m.old_id = ps.part_id
GROUP  BY 1, 2;

DELETE FROM public.part_stock WHERE part_id IN (SELECT old_id FROM m148_map);
INSERT INTO public.part_stock (part_id, location_id, quantity, updated_at)
SELECT part_id, location_id, quantity, updated_at FROM m148_stock;

-- The log: one entry per survivor naming what was folded into it, one per removed copy.
INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields)
SELECT 'parts', s.id, 'UPDATE',
       jsonb_build_object('name', s.name, 'unit', s.unit, 'part_number', s.part_number),
       jsonb_build_object('name', t.name, 'unit', t.unit, 'part_number', null,
                          'merged_by', 'MAIN-148',
                          'merged_from', (SELECT jsonb_agg(jsonb_build_object('id', m.old_id, 'name', m.name,
                                                  'part_number', m.part_number, 'unit', m.unit,
                                                  'quantity_in_stock', m.quantity_in_stock) ORDER BY m.old_id)
                                          FROM m148_map m WHERE m.new_id = s.id AND m.old_id <> m.new_id)),
       ARRAY['merged_from', 'name', 'unit', 'part_number']
FROM   public.parts s
JOIN   m148_sets t ON t.name_key = public.part_name_key(s.name)
WHERE  s.id IN (SELECT new_id FROM m148_map);

INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data)
SELECT 'parts', m.old_id, 'DELETE',
       jsonb_build_object('name', m.name, 'part_number', m.part_number, 'unit', m.unit, 'quantity_in_stock', m.quantity_in_stock),
       jsonb_build_object('merged_by', 'MAIN-148', 'merged_into', m.new_id)
FROM   m148_map m WHERE m.old_id <> m.new_id;

UPDATE public.parts p SET name = t.name, unit = t.unit, part_number = NULL
FROM   m148_sets t
WHERE  p.id IN (SELECT new_id FROM m148_map) AND public.part_name_key(p.name) = t.name_key;

DELETE FROM public.parts WHERE id IN (SELECT old_id FROM m148_map WHERE old_id <> new_id);

-- ── 5. The checks ───────────────────────────────────────────────────────────────────
    SELECT string_agg(format('%s %s: %s', what, item, value), '; ') INTO v_diff
    FROM ((SELECT *, 'before' FROM m148_before EXCEPT SELECT *, 'before' FROM m148_figures)
          UNION ALL
          (SELECT *, 'after' FROM m148_figures EXCEPT SELECT *, 'after' FROM m148_before)) d(what, item, value, side);
    IF v_diff IS NOT NULL THEN
        RAISE EXCEPTION 'MAIN-148: figures changed by the merge — %', v_diff;
    END IF;

    IF EXISTS (SELECT 1 FROM public.parts GROUP BY public.part_name_key(name) HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'MAIN-148: duplicate part names remain';
    END IF;


-- ── 6. Part No. "1" ─────────────────────────────────────────────────────────────────
-- It came from a column of the 29 Jul 2026 upload sheet and is not a real part number.
INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields)
SELECT 'parts', id, 'UPDATE', jsonb_build_object('part_number', part_number),
       jsonb_build_object('part_number', null, 'changed_by', 'MAIN-148'), ARRAY['part_number']
FROM   public.parts WHERE part_number = '1';
UPDATE public.parts SET part_number = NULL WHERE part_number = '1';

INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields)
SELECT 'scrap_inventory', id, 'UPDATE', jsonb_build_object('part_number_snapshot', part_number_snapshot),
       jsonb_build_object('part_number_snapshot', null, 'changed_by', 'MAIN-148'), ARRAY['part_number_snapshot']
FROM   public.scrap_inventory WHERE part_number_snapshot = '1';
UPDATE public.scrap_inventory SET part_number_snapshot = NULL WHERE part_number_snapshot = '1';

DROP VIEW m148_figures;
DROP TABLE m148_sets, m148_map, m148_before, m148_stock;
END $m148$;

-- ── 7. The rule ─────────────────────────────────────────────────────────────────────
-- Generated, so the prod→staging seed skips it and staging recomputes it.
ALTER TABLE public.parts ADD COLUMN name_key text GENERATED ALWAYS AS (public.part_name_key(name)) STORED;
CREATE UNIQUE INDEX parts_name_key_key ON public.parts (name_key);

COMMENT ON COLUMN public.parts.name_key IS
  'part_name_key(name): unique, so no two parts share a name ignoring capitals and extra spaces (MAIN-148).';

-- ── 8. Refurbishment ────────────────────────────────────────────────────────────────
-- Every original whose refurbished name is the same shares one refurbished part, so the
-- links are keyed by the original and a refurbished part may have several.
ALTER TABLE public.refurbished_part_links DROP CONSTRAINT refurbished_part_links_pkey;
ALTER TABLE public.refurbished_part_links DROP CONSTRAINT refurbished_part_links_original_part_id_key;
ALTER TABLE public.refurbished_part_links ADD PRIMARY KEY (original_part_id);
CREATE INDEX refurbished_part_links_refurbished_part_id_idx ON public.refurbished_part_links (refurbished_part_id);

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
       OR v_advance   IS NULL OR v_advance   < 0 OR v_advance  > v_approved THEN
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

    -- Only this function may mark an invoice a refurbishment or add lines to one.
    PERFORM set_config('app.recording_refurbishment', 'on', true);

    INSERT INTO public.purchase_invoices
        (kind, invoice_number, supplier_id, supplier_name, invoice_date, notes, invoice_file_url, location_id, created_by)
    VALUES (
        'refurbishment',
        btrim(p_invoice->>'invoice_number'),
        v_supplier_id,
        v_supplier,
        v_inv_date,
        NULLIF(p_invoice->>'notes', ''),
        btrim(p_invoice->>'invoice_file_url'),
        v_location,
        auth.uid()
    )
    RETURNING id INTO v_invoice_id;

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
        WHERE  original_part_id = v_part_id OR refurbished_part_id = v_part_id
        LIMIT  1;

        IF v_refurb_id IS NULL THEN
            -- A part already carrying the refurbished name is that part (MAIN-148), so
            -- originals of the same name share one refurbished part.
            SELECT id INTO v_refurb_id
            FROM   public.parts
            WHERE  name_key = public.part_name_key(v_part_name || ' (Refurbished)');

            IF v_refurb_id IS NULL THEN
                INSERT INTO public.parts (name, part_number, unit, quantity_in_stock)
                VALUES (v_part_name || ' (Refurbished)', v_part_number, v_part_unit, 0)
                RETURNING id INTO v_refurb_id;
            END IF;

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

    PERFORM set_config('app.recording_refurbishment', 'off', true);

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

    PERFORM public.save_purchase_finance_invoice(v_invoice_id, p_invoice);

    RETURN v_invoice_id;
END;
$$;

