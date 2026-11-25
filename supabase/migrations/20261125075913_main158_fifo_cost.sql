-- MAIN-158 (epic MAIN-154): opening stock prices, first-in-first-out cost and job card value.
--
-- Every quantity that enters stock is a lot, kept per part and company across all
-- workshops: a purchase or refurbishment line (dated by its invoice date, under its
-- Billed to), stock found in an audit (at the part's last cost), and an opening lot for
-- stock that never came in through a recorded purchase (always first in the queue).
-- Every quantity that leaves stock — an in-house spare, by the company split in
-- issue_parts.stock_draws, or stock an audit found missing — takes the oldest lot still
-- left. Costs include GST.
--
-- Nothing about the queue is edited by hand. stock_cost_draws is rebuilt from scratch for
-- a part and company by rebuild_part_cost() whenever anything that feeds it changes, so a
-- corrected price or an old bill entered late re-costs every spare after it (user
-- decision 2026-11-25). Workshop moves never touch lots; PI-176/180/183/185 were moves
-- recorded as purchases and make none.

-- ── Helpers ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.is_workshop_move_invoice(p_purchase_number integer)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
    -- "Bannerghatta Hub", ₹1 lines: stock moved Bannerghatta → Mahadevpura before stock
    -- transfers existed. Also left out of company_ledger_lines.
    SELECT p_purchase_number IN (176, 180, 183, 185);
$$;

CREATE INDEX IF NOT EXISTS issue_parts_part_id_idx ON public.issue_parts (part_id);
CREATE INDEX IF NOT EXISTS issue_parts_issue_id_idx ON public.issue_parts (issue_id);
CREATE INDEX IF NOT EXISTS purchase_invoice_items_part_id_idx ON public.purchase_invoice_items (part_id);

-- ── Opening lots ─────────────────────────────────────────────────────────────

CREATE TABLE public.opening_stock_lots (
    id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    part_id         uuid NOT NULL REFERENCES public.parts(id),
    company         text DEFAULT 'nvs_travels' NOT NULL,
    quantity        numeric(12,2) NOT NULL,
    unit_price      numeric(12,2) NOT NULL,
    gst_rate        numeric(5,2) DEFAULT 0 NOT NULL,
    unit_cost       numeric(14,4) GENERATED ALWAYS AS (round(unit_price * (1 + gst_rate / 100.0), 4)) STORED,
    source          text DEFAULT 'price_sheet' NOT NULL,
    note            text,
    created_by      uuid,
    created_by_name text DEFAULT '' NOT NULL,
    created_at      timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT opening_stock_lots_company_check CHECK (company = ANY (ARRAY['nvs_travels', 'nvs_travel_solutions'])),
    CONSTRAINT opening_stock_lots_quantity_check CHECK (quantity > 0),
    CONSTRAINT opening_stock_lots_unit_price_check CHECK (unit_price >= 0),
    CONSTRAINT opening_stock_lots_gst_rate_check CHECK (gst_rate >= 0 AND gst_rate <= 100),
    -- price_sheet: the MAIN-158 load. exec: the price an exec gave when a spare found
    -- stock with no price (add_opening_stock_price).
    CONSTRAINT opening_stock_lots_source_check CHECK (source = ANY (ARRAY['price_sheet', 'exec']))
);
CREATE INDEX opening_stock_lots_part_idx ON public.opening_stock_lots (part_id, company);

COMMENT ON TABLE public.opening_stock_lots IS
    'MAIN-158: stock that never came in through a recorded purchase, priced. Always first in the first-in-first-out queue. Written only by the MAIN-158 migration and add_opening_stock_price().';

ALTER TABLE public.opening_stock_lots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Exec and finance view opening stock lots" ON public.opening_stock_lots
    FOR SELECT TO authenticated USING (public.is_maintenance_exec() OR public.is_finance());

-- ── Draws: which lot each spare (or audit loss) took ─────────────────────────

CREATE TABLE public.stock_cost_draws (
    id                  uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    part_id             uuid NOT NULL REFERENCES public.parts(id) ON DELETE CASCADE,
    company             text NOT NULL,
    -- What took the stock (exactly one).
    issue_part_id       uuid REFERENCES public.issue_parts(id) ON DELETE CASCADE,
    audit_item_id       uuid REFERENCES public.stock_audit_items(id) ON DELETE CASCADE,
    -- Which lot it came from (at most one; none = no lot left, i.e. no price).
    purchase_item_id    uuid REFERENCES public.purchase_invoice_items(id) ON DELETE CASCADE,
    opening_lot_id      uuid REFERENCES public.opening_stock_lots(id) ON DELETE CASCADE,
    found_audit_item_id uuid REFERENCES public.stock_audit_items(id) ON DELETE CASCADE,
    quantity            numeric(12,2) NOT NULL,
    unit_cost           numeric(14,4),
    amount              numeric(14,2) GENERATED ALWAYS AS (round(quantity * unit_cost, 2)) STORED,
    CONSTRAINT stock_cost_draws_company_check CHECK (company = ANY (ARRAY['nvs_travels', 'nvs_travel_solutions'])),
    CONSTRAINT stock_cost_draws_quantity_check CHECK (quantity > 0),
    CONSTRAINT stock_cost_draws_one_consumer_check CHECK (num_nonnulls(issue_part_id, audit_item_id) = 1),
    CONSTRAINT stock_cost_draws_one_lot_check CHECK (num_nonnulls(purchase_item_id, opening_lot_id, found_audit_item_id) <= 1),
    CONSTRAINT stock_cost_draws_cost_check CHECK ((unit_cost IS NULL) = (num_nonnulls(purchase_item_id, opening_lot_id, found_audit_item_id) = 0))
);
CREATE INDEX stock_cost_draws_issue_part_idx ON public.stock_cost_draws (issue_part_id) WHERE issue_part_id IS NOT NULL;
CREATE INDEX stock_cost_draws_part_idx ON public.stock_cost_draws (part_id, company);

COMMENT ON TABLE public.stock_cost_draws IS
    'MAIN-158: first-in-first-out allocation of lots to spares and audit losses. Derived: rebuilt per part and company by rebuild_part_cost(); never edited.';

ALTER TABLE public.stock_cost_draws ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Exec and finance view stock cost draws" ON public.stock_cost_draws
    FOR SELECT TO authenticated USING (public.is_maintenance_exec() OR public.is_finance());

-- ── The queue ────────────────────────────────────────────────────────────────

-- Lots of a part and company, in first-in-first-out order.
CREATE OR REPLACE FUNCTION public.part_cost_lots(p_part_id uuid, p_company text)
RETURNS TABLE (kind text, lot_id uuid, quantity numeric, unit_cost numeric, rnk integer, at_time timestamp, recorded_at timestamp)
LANGUAGE plpgsql STABLE
SET search_path TO 'public'
AS $$
DECLARE
    v_found_cost numeric;
BEGIN
    -- Stock found in an audit takes the part's latest cost: its latest purchase, else
    -- its latest opening price, else nothing.
    SELECT x.cost INTO v_found_cost FROM (
        SELECT ((pii.quantity * pii.unit_price - pii.discount_amount) * (1 + pii.gst_rate / 100.0)) / pii.quantity AS cost,
               1 AS r, pi.invoice_date::timestamp AS t, pi.created_at AS t2
        FROM   public.purchase_invoice_items pii
        JOIN   public.purchase_invoices pi ON pi.id = pii.invoice_id
        WHERE  pii.part_id = p_part_id AND NOT public.is_workshop_move_invoice(pi.purchase_number)
        UNION ALL
        SELECT o.unit_cost, 0, o.created_at::timestamp, o.created_at::timestamp
        FROM   public.opening_stock_lots o
        WHERE  o.part_id = p_part_id
    ) x
    ORDER BY x.r DESC, x.t DESC, x.t2 DESC
    LIMIT 1;

    RETURN QUERY
    SELECT 'opening'::text, o.id, o.quantity::numeric, o.unit_cost::numeric, 0, o.created_at::timestamp, o.created_at::timestamp
    FROM   public.opening_stock_lots o
    WHERE  o.part_id = p_part_id AND o.company = p_company
    UNION ALL
    SELECT 'purchase', pii.id, pii.quantity::numeric,
           ((pii.quantity * pii.unit_price - pii.discount_amount) * (1 + pii.gst_rate / 100.0)) / pii.quantity,
           1, pi.invoice_date::timestamp, pi.created_at
    FROM   public.purchase_invoice_items pii
    JOIN   public.purchase_invoices pi ON pi.id = pii.invoice_id
    WHERE  pii.part_id = p_part_id AND pi.billed_to = p_company
      AND  NOT public.is_workshop_move_invoice(pi.purchase_number)
    UNION ALL
    SELECT 'found', i.id, i.applied_delta::numeric, coalesce(v_found_cost, 0), 1, a.completed_at, a.completed_at
    FROM   public.stock_audit_items i
    JOIN   public.stock_audits a ON a.id = i.audit_id
    WHERE  a.status = 'completed' AND i.part_id = p_part_id AND i.company = p_company
      AND  i.applied_delta > 0;
END;
$$;

-- What took stock of a part and company, in time order. An in-house spare from before
-- MAIN-157 (empty stock_draws) drew NVS Travels stock — the rule restore_part_to_inventory
-- uses to give it back.
CREATE OR REPLACE FUNCTION public.part_cost_consumers(p_part_id uuid, p_company text)
RETURNS TABLE (kind text, consumer_id uuid, quantity numeric, at_time timestamp)
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT 'spare'::text, ip.id,
           CASE WHEN ip.stock_draws ? p_company THEN (ip.stock_draws ->> p_company)::numeric
                ELSE ip.quantity_used::numeric END,
           coalesce(ip.added_at, 'epoch'::timestamp)
    FROM   public.issue_parts ip
    JOIN   public.issues i ON i.id = ip.issue_id
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  ip.part_id = p_part_id
      AND  (ip.stock_draws ? p_company
            OR (ip.stock_draws = '{}'::jsonb AND jc.type = 'InHouse' AND p_company = 'nvs_travels'))
    UNION ALL
    SELECT 'audit', i.id, -i.applied_delta::numeric, a.completed_at
    FROM   public.stock_audit_items i
    JOIN   public.stock_audits a ON a.id = i.audit_id
    WHERE  a.status = 'completed' AND i.part_id = p_part_id AND i.company = p_company
      AND  i.applied_delta < 0;
$$;

-- Stock of a part and company that has no lot: stock now + everything taken − every lot.
-- Positive = that much needs an opening price.
CREATE OR REPLACE FUNCTION public.part_cost_gap(p_part_id uuid, p_company text)
RETURNS numeric
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT coalesce((SELECT sum(quantity) FROM public.part_stock WHERE part_id = p_part_id AND company = p_company), 0)
         + coalesce((SELECT sum(quantity) FROM public.part_cost_consumers(p_part_id, p_company)), 0)
         - coalesce((SELECT sum(quantity) FROM public.part_cost_lots(p_part_id, p_company)), 0);
$$;

CREATE OR REPLACE FUNCTION public.rebuild_part_cost(p_part_id uuid, p_company text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_kind  text[];
    v_id    uuid[];
    v_qty   numeric[];
    v_cost  numeric[];
    v_n     integer;
    v_i     integer := 1;
    v_left  numeric := 0;
    v_need  numeric;
    v_take  numeric;
    c       record;
BEGIN
    IF p_part_id IS NULL OR p_company IS NULL THEN
        RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('stock_cost:' || p_part_id::text || ':' || p_company, 0));

    DELETE FROM public.stock_cost_draws WHERE part_id = p_part_id AND company = p_company;

    SELECT array_agg(l.kind     ORDER BY l.rnk, l.at_time, l.recorded_at, l.lot_id),
           array_agg(l.lot_id   ORDER BY l.rnk, l.at_time, l.recorded_at, l.lot_id),
           array_agg(l.quantity ORDER BY l.rnk, l.at_time, l.recorded_at, l.lot_id),
           array_agg(l.unit_cost ORDER BY l.rnk, l.at_time, l.recorded_at, l.lot_id)
    INTO   v_kind, v_id, v_qty, v_cost
    FROM   public.part_cost_lots(p_part_id, p_company) l;

    v_n := coalesce(cardinality(v_id), 0);
    IF v_n > 0 THEN
        v_left := v_qty[1];
    END IF;

    FOR c IN
        SELECT * FROM public.part_cost_consumers(p_part_id, p_company) x
        ORDER BY x.at_time, x.consumer_id
    LOOP
        v_need := c.quantity;
        WHILE v_need > 0 LOOP
            -- Step past used-up lots.
            WHILE v_i <= v_n AND v_left <= 0 LOOP
                v_i := v_i + 1;
                IF v_i <= v_n THEN
                    v_left := v_qty[v_i];
                END IF;
            END LOOP;

            IF v_i > v_n THEN
                -- No lot left: this quantity has no price.
                INSERT INTO public.stock_cost_draws (part_id, company, issue_part_id, audit_item_id, quantity, unit_cost)
                VALUES (p_part_id, p_company,
                        CASE WHEN c.kind = 'spare' THEN c.consumer_id END,
                        CASE WHEN c.kind = 'audit' THEN c.consumer_id END,
                        v_need, NULL);
                v_need := 0;
            ELSE
                v_take := least(v_need, v_left);
                INSERT INTO public.stock_cost_draws (part_id, company, issue_part_id, audit_item_id,
                                                     purchase_item_id, opening_lot_id, found_audit_item_id,
                                                     quantity, unit_cost)
                VALUES (p_part_id, p_company,
                        CASE WHEN c.kind = 'spare' THEN c.consumer_id END,
                        CASE WHEN c.kind = 'audit' THEN c.consumer_id END,
                        CASE WHEN v_kind[v_i] = 'purchase' THEN v_id[v_i] END,
                        CASE WHEN v_kind[v_i] = 'opening'  THEN v_id[v_i] END,
                        CASE WHEN v_kind[v_i] = 'found'    THEN v_id[v_i] END,
                        v_take, v_cost[v_i]);
                v_left := v_left - v_take;
                v_need := v_need - v_take;
            END IF;
        END LOOP;
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.rebuild_part_cost(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rebuild_part_cost(uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.part_cost_lots(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.part_cost_consumers(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.part_cost_gap(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.part_cost_lots(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.part_cost_consumers(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.part_cost_gap(uuid, text) TO service_role;

-- ── Load the opening prices (sheet "Opening stock prices", 25 Nov 2026) ──────
--
-- Price per unit before GST and GST %, one row per part. The quantity is worked out
-- here, not taken from the sheet, so spares used since the sheet was made still balance.
-- Revit, Brake Oil 500 ml, 5mm Wire and Wiper linkage assy take the app's last purchase
-- price; the two diesel filters' sheet prices were swapped; Jack is 18% (user decision
-- 2026-11-25, recorded in the sheet's Comment column).

DO $$
DECLARE
    r         record;
    v_part    uuid;
    v_gap     numeric;
    v_missing text[] := '{}';
    v_loaded  integer := 0;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
    ('Adblue (Def)', 55.93, 18),
    ('P Clamp', 2.00, 18),
    ('Fuse', 8.00, 18),
    ('White Cloth', 7.50, 0),
    ('Colour Cloth', 12.50, 0),
    ('Engine Oil', 243.22, 18),
    ('4 Pin relay', 175.00, 18),
    ('Pressing Clips', 3.00, 18),
    ('Hose Clamp', 33.90, 18),
    ('Revit', 38, 18),
    ('Synth engine oil', 368.64, 18),
    ('Brush', 65.00, 0),
    ('Coolant Oil (Green)', 150.00, 0),
    ('Wire Tag', 5.00, 0),
    ('Jug', 8.00, 0),
    ('Battery Cable', 241.51, 18),
    ('Coolant Oil (Blue)', 112.50, 18),
    ('Camera Back View', 500.00, 0),
    ('Gear Oil', 245.45, 18),
    ('Dust Pan', 8.00, 0),
    ('Rubber Mat', 110.00, 0),
    ('Speaker Wire', 18.00, 18),
    ('Emergency Door Cap', 254.24, 18),
    ('W.C Kit (761)', 90.21, 18),
    ('Vacuum Pipe Adapter 6mm', 55.08, 18),
    ('Axle Pin', 10.00, 18),
    ('Battery Terminal', 90.00, 18),
    ('Brake Oil 500 ml', 185, 18),
    ('Slack Adjuster', 567.00, 18),
    ('Wheel Bolt & Nut', 207.61, 18),
    ('Battery Clip (Each Pkts -10NO''s)', 25.00, 18),
    ('4mm wire cable', 23.60, 18),
    ('Bulb 1141', 16.00, 18),
    ('BulbH4', 90.00, 18),
    ('Vacuum Pipe Adapter 10mm', 138.00, 28),
    ('Wiper Blade 20 "', 143.00, 18),
    ('Rivet Kit', 10.00, 28),
    ('Side Mirror', 100.00, 18),
    ('Insulation Tape', 20.00, 18),
    ('Housing Oil', 145.60, 18),
    ('Patty holder', 15.00, 18),
    ('Vacuum Pipe Adapter 8mm', 110.00, 28),
    ('Wiper 26', 259.00, 18),
    ('Retreading Tyre 825', 2288.00, 18),
    ('24v Bulb', 8.00, 18),
    ('Clutch Pedal Bush Kit', 117.18, 28),
    ('Horn', 400.00, 18),
    ('Brake Lining', 906.04, 18),
    ('5mm Wire', 39.20, 18),
    ('33111 bearing', 1102.04, 18),
    ('407 oil seal', 46.61, 18),
    ('Window lock', 89.99, 28),
    ('709 lining', 1847.46, 18),
    ('Side Indicator 903', 180.00, 18),
    ('Wiper Blade 24 "', 213.00, 18),
    ('12mm Vacuum Pipe Adapter', 160.00, 28),
    ('Air Filter BS4', 2057.66, 18),
    ('Diaphragm Rubber', 289.00, 18),
    ('Outer Door Handle', 169.48, 18),
    ('7.50 Flap', 254.24, 18),
    ('7.50 tube', 508.47, 18),
    ('Air Compressor Kit', 816.05, 18),
    ('Clips', 110.00, 18),
    ('Oil Filter Spin on', 1177.12, 18),
    ('Side Parking Light Scale', 110.00, 18),
    ('Wiper blade with rod', 160.00, 0),
    ('12 v colour bulb', 18.00, 18),
    ('Axle Packing', 7.50, 18),
    ('Bonnet Lock', 80.51, 18),
    ('Power Steering oil 1 ltr', 183.00, 18),
    ('Side blinker', 135.00, 18),
    ('24v fancy lite', 160.00, 18),
    ('Fog Lamp with Clamp', 400.00, 18),
    ('Mobile charger', 200.00, 18),
    ('Radiator Cap Small', 152.53, 18),
    ('Seat Belt', 350.00, 18),
    ('Bulb H1', 140.00, 18),
    ('Cotton Waste', 161.91, 5),
    ('CSC Kit Top', 901.25, 28),
    ('Pressing Bulb', 8.00, 18),
    ('Push Pull Switch', 60.00, 18),
    ('Teflon tape', 15.00, 18),
    ('W.C Kit (760)', 62.64, 18),
    ('Bulb H7', 210.00, 18),
    ('Clutch Top Cylinder Assy', 842.93, 18),
    ('CSC Kit Bottom', 901.25, 28),
    ('Mop', 78.00, 0),
    ('Oil Filter 1/2Ltr', 327.01, 18),
    ('Side Indicator 901', 124.53, 18),
    ('Vacuum Pipe 6mm', 42.37, 18),
    ('32210 Bearing', 866.51, 18),
    ('Brake Shoe Kit Lock', 296.59, 18),
    ('Clutch Bottom Cylinder Assy', 1053.42, 18),
    ('clutch Pedal Spring', 60.00, 0),
    ('Def Filter', 1488.98, 18),
    ('Diesel Tank Cap', 491.53, 18),
    ('Headlight Relay', 379.00, 18),
    ('Hex bolt W lock nut', 15.00, 18),
    ('Indica fuse', 65.00, 18),
    ('Retreading Tyre 750', 2288.00, 18),
    ('Shock Absorber Bush', 58.59, 28),
    ('Tie rod End Kit', 1110.17, 18),
    ('Wheel Mat', 127.11, 18),
    ('32307 bearing', 949.34, 18),
    ('Clutch Pedal Rubber', 50.84, 18),
    ('Diesel filter tata', 810.17, 18),
    ('Hand brake cable small', 302.01, 18),
    ('Indicator Flasher', 457.87, 18),
    ('Inner Door Lock', 54.69, 28),
    ('JK door post key', 275.40, 18),
    ('Piano Switch', 85.00, 18),
    ('Radiator Bottom Hose', 528.71, 18),
    ('Radiator Cap Big', 169.48, 18),
    ('Side Wall door Packing', 185.00, 0),
    ('1835 belt', 950.00, 18),
    ('32212 bearing', 728.81, 18),
    ('Back Tail Lamp Assy', 415.00, 18),
    ('Battery charging clip', 45.00, 18),
    ('Bulb 2416 24v', 19.00, 18),
    ('Center Joint Bearing', 754.24, 18),
    ('Center Joint Rubber', 806.11, 18),
    ('Clutch Pedal Kit', 118.64, 18),
    ('Diesel Filter 1 ltr', 111.64, 18),
    ('Elbow packing', 21.18, 18),
    ('Gear Lever Boot', 720.00, 18),
    ('Gear lever Bush Kit', 10.00, 18),
    ('Radiator Top Hose', 261.00, 18),
    ('Sub Mirror Big', 220.34, 18),
    ('TT Joint bolt', 16.95, 18),
    ('WC ASSY 110MM', 1361.35, 18),
    ('WC ASSY 90MM', 1425.80, 18),
    ('32214 bearing', 1029.66, 18),
    ('Anna Bond Grey', 120.00, 18),
    ('Banjo Washer Kit', 101.69, 18),
    ('Chamber packing', 380.00, 18),
    ('Clutch & Loading Plate Assy', 4274.00, 18),
    ('Coolant hose', 180.00, 0),
    ('Dash board lock', 150.00, 18),
    ('Diesel return Pipe', 40.00, 0),
    ('Fan belt 1427', 278.83, 18),
    ('Gear cable lock', 62.50, 28),
    ('Hand Brake Lining', 596.57, 18),
    ('Headlight Holder 3 pin', 65.00, 18),
    ('Nozzle Pipe Set', 70.84, 18),
    ('Oil Filter 1 Ltr', 283.07, 18),
    ('Roof handle', 35.00, 18),
    ('Sleeve', 10.00, 18),
    ('Sleeve big', 25.00, 18),
    ('Tarpaulin', 1000.00, 0),
    ('Thread Locker', 25.42, 18),
    ('18 No Wiring Clip', 296.63, 18),
    ('2 pin connector', 90.00, 18),
    ('Accelerator Cable', 314.69, 18),
    ('Axle stud', 65.00, 18),
    ('Balance rod bush', 58.59, 28),
    ('Brake lining Tata', 4279.66, 18),
    ('Bulb 1016', 20.00, 18),
    ('Coupler Fuse Holder', 65.00, 18),
    ('Door bush', 93.49, 28),
    ('Fly wheel bearing', 181.95, 18),
    ('Free flow jali', 40.00, 18),
    ('Glass Handle', 42.62, 28),
    ('Inner lock Kit', 118.64, 18),
    ('Isolation Relay Kit', 3126.77, 18),
    ('LCV Mirror Rod', 450.00, 28),
    ('Nozzle Pipe Dummy', 16.95, 18),
    ('Oil Seal Back', 86.44, 18),
    ('Outer lock Kit', 729.00, 0),
    ('Reverse Gear Switch M/Z', 346.76, 18),
    ('Silencer rubber', 54.24, 18),
    ('Sub Mirror Small', 220.34, 18),
    ('Temp Switch', 175.77, 28),
    ('TT bearings', 684.01, 28),
    ('TT fog lamp switch', 156.78, 18),
    ('WC kit 841', 77.97, 18),
    ('Air Filter BS3', 779.35, 18),
    ('Air tank nut', 203.39, 18),
    ('Back Outer Bearing', 611.86, 18),
    ('Brake cam lock', 20.00, 18),
    ('Brake Pad', 872.88, 18),
    ('Cabin Bed', 323.10, 28),
    ('Clutch Fork', 219.99, 18),
    ('Combination Connector M/Z', 436.99, 18),
    ('Diesel Filter 1/2 ltrs 3 pin', 2133.05, 18),
    ('Drag link kit mz', 587.62, 18),
    ('Engine dummy', 9.38, 28),
    ('Fuel Security Kit', 1864.65, 18),
    ('Fuel Strainer', 140.94, 18),
    ('Hand brake Cable Big', 268.46, 18),
    ('Headlight assy', 295.00, 18),
    ('Jack', 2205, 18),
    ('LCV mirror', 350.00, 18),
    ('New Tyre  Tubeless 215/75R15', 5338.98, 18),
    ('Nozzle Pipe Small', 70.84, 18),
    ('Oil Seal Front', 59.49, 18),
    ('Pump Switch', 489.34, 28),
    ('Reverse Gear switch Big', 466.07, 28),
    ('Reverse Horn', 750.00, 18),
    ('Rust Spray', 322.03, 18),
    ('Silencer gasket', 23.73, 18),
    ('Silicon Paste', 150.00, 18),
    ('Tata heating switch', 140.00, 18),
    ('TT gear lever rubber', 165.25, 18),
    ('TT reverse light switch', 114.41, 18),
    ('Valve Door Gasket', 260.00, 18),
    ('Water pipe packing', 15.00, 0),
    ('Wiper Arm', 1550.00, 18),
    ('235/75 tyre', 10423.73, 18),
    ('8mm Cable Wire', 77.00, 18),
    ('ACC patti U type', 30.00, 18),
    ('Air Dryer Kit', 4402.54, 18),
    ('Air Guide Fiber RH', 393.22, 28),
    ('Back Inner Bearing', 611.86, 18),
    ('Center joint rubber assy', 745.76, 18),
    ('Centre mirror', 450.00, 18),
    ('Clutch Booster Assy', 2389.83, 18),
    ('Combination Switch Assy', 1165.55, 18),
    ('Diesel Filter 1/2 ltr', 140.94, 18),
    ('Diesel main pipe', 278.37, 18),
    ('Fan belt 1115', 278.83, 18),
    ('Fan belt 960T', 278.83, 18),
    ('Fuse spray (contact)', 375.00, 18),
    ('Gear lever Assy', 2028.68, 18),
    ('H11 Bulb', 350.00, 18),
    ('Heating Switch', 190.00, 0),
    ('Inner Bearing Front', 444.92, 18),
    ('Jk door rod', 202.11, 28),
    ('Nozzle Pipe Big', 20.88, 18),
    ('Sealing tape', 2500.00, 18),
    ('Side indicator LED', 150.00, 18),
    ('Side Mirror Lh', 449.15, 18),
    ('Side Mirror Rod R & L', 1500.00, 28),
    ('Silencer Bed', 187.49, 28),
    ('SS sensor tata', 491.53, 18),
    ('Steering bolt', 140.00, 18),
    ('Sub Key Set', 253.89, 28),
    ('Temp gauge BS4', 419.09, 18),
    ('TL Marcopolo [ OEM Type]', 195.00, 18),
    ('TT Diesel filter assy', 4404.92, 18),
    ('Turbo Gasket', 60.00, 18),
    ('Turbo Hose Pipe Bottom', 780.00, 18),
    ('Vacuum Pipe Adapter 6mm T', 23.44, 28),
    ('Wiper 32', 450.00, 18),
    ('Grease (Red )', 567.00, 18),
    ('1171 belt', 427.97, 18),
    ('1267 Bulb', 8.00, 18),
    ('15mtr Car Washer Hose', 2300.00, 0),
    ('Accelerator pedal', 1820.31, 28),
    ('Air Guide Fiber LH', 393.22, 28),
    ('Balance rod Bush Kit', 826.22, 18),
    ('Battery Cut Off', 1293.81, 18),
    ('Battery XP 1000', 8053.39, 18),
    ('Battery XP 1300', 10033.90, 18),
    ('Battery xp 800', 5527.97, 18),
    ('Bend ARM', 2162.74, 28),
    ('Brake hose', 504.20, 18),
    ('Brake Lining 90mm Std', 873.97, 18),
    ('Brake Master Cylinder Assy', 3203.00, 28),
    ('Brake pipe', 360.14, 18),
    ('Clutch Master Cylinder', 1125.37, 28),
    ('Clutch Releser Bearing', 1208.80, 18),
    ('Combination Switch Pin', 436.99, 18),
    ('combination switch TATA', 838.98, 18),
    ('Comp. Head Assy', 2556.30, 18),
    ('Comp. Head Top Plate', 1682.33, 18),
    ('Comp. Kit Half', 589.11, 18),
    ('Comp. Reed Valve Plate', 4120.06, 18),
    ('Compressor pulley with bearing', 669.58, 28),
    ('Counter gear bearing', 606.26, 18),
    ('Delivery PIPE Assy', 1762.71, 18),
    ('Diesel Filter Bs4', 1382.55, 18),
    ('Diode assy unit', 450.41, 18),
    ('Distilled Water', 31.30, 0),
    ('Door lock', 254.24, 18),
    ('Drag link assy', 3512.47, 18),
    ('Driver Fan', 1350.00, 18),
    ('Elbow', 90.00, 0),
    ('Emergency switch outer', 4375.75, 28),
    ('Engaging lever', 83.00, 18),
    ('Family lock set', 1635.59, 18),
    ('Fan belt 1110', 279.66, 18),
    ('Fan belt 1170', 278.83, 18),
    ('Fan belt 980', 278.83, 18),
    ('Flasher Unit', 122.88, 18),
    ('Fuel gauge', 669.65, 18),
    ('Fuel Pipe Hose', 150.00, 0),
    ('G L knob tata', 406.00, 18),
    ('Gear cable set mz', 4269.20, 18),
    ('Gear lever end', 280.00, 18),
    ('Gear lever Knob', 171.88, 28),
    ('Gear lever rod', 2340.00, 18),
    ('Gear Shift Cable', 3936.37, 28),
    ('Handle Control Valve', 3100.00, 0),
    ('HeadLight Bulb High Beam', 1018.00, 0),
    ('HeadLight Bulb low Beam', 1018.00, 18),
    ('Headlight Switch', 100.00, 18),
    ('Horn relay', 122.88, 18),
    ('Horn Stick', 218.00, 18),
    ('Ignition Lock Set M/Z', 1516.78, 18),
    ('Indicator Front', 400.00, 0),
    ('JK Door Lock Assy', 2129.01, 18),
    ('King pin full kit mz 1os', 2516.78, 28),
    ('Main Bearing oil seal', 156.77, 18),
    ('MC Assy BS3', 2699.48, 18),
    ('MC Assy BS4', 3425.80, 18),
    ('Mounting clip', 39.06, 28),
    ('Oil filter combo bs4', 1784.62, 18),
    ('Oil Switch', 340.29, 28),
    ('Pinion bearing big', 797.74, 18),
    ('Power Steering Pipe', 450.00, 0),
    ('Pvc fanal', 450.00, 18),
    ('RC lock', 133.47, 18),
    ('Side Indicator', 110.00, 18),
    ('Silicon Paste Black', 150.00, 18),
    ('Smal rod', 100.00, 0),
    ('Spare Starter', 423.73, 18),
    ('Speedo Cable Big', 284.61, 28),
    ('Starter brush holder mico', 885.00, 18),
    ('Starter carbon brush', 550.00, 18),
    ('Stepney Bracket', 380.00, 28),
    ('Terminal spray', 380.00, 18),
    ('Timing oil seal', 199.85, 18),
    ('Top Gear Oil seal', 105.92, 18),
    ('TT clutch cover', 5084.75, 18),
    ('TT clutch plate', 3389.83, 18),
    ('TT gear select cable', 859.38, 28),
    ('TT head light blaze', 421.88, 28),
    ('TT Joint star', 593.22, 18),
    ('TT Pinion flange', 2288.14, 18),
    ('TT Rear cross holder', 805.08, 18),
    ('Turbo Hose Bottom', 780.00, 18),
    ('Turbo Hose Top', 780.00, 18),
    ('Turbo Intercooler Hose M/Z', 862.04, 18),
    ('Union adopter', 190.66, 18),
    ('Wiper linkage assy', 1161.07, 18),
    ('Wiper Motor', 2852.94, 28),
    ('Wiper Water Pin', 160.00, 0),
    ('Wire Tag 450mm', 513.00, 18)
        ) AS v(name, unit_price, gst_rate)
    LOOP
        SELECT id INTO v_part FROM public.parts WHERE name_key = public.part_name_key(r.name);
        IF v_part IS NULL THEN
            v_missing := v_missing || r.name::text;
            CONTINUE;
        END IF;

        v_gap := public.part_cost_gap(v_part, 'nvs_travels');
        IF v_gap > 0 THEN
            INSERT INTO public.opening_stock_lots (part_id, company, quantity, unit_price, gst_rate, source, note, created_by_name)
            VALUES (v_part, 'nvs_travels', v_gap, r.unit_price, r.gst_rate, 'price_sheet',
                    'MAIN-158 opening stock prices sheet', 'System (MAIN-158)');
            v_loaded := v_loaded + 1;
        END IF;
    END LOOP;

    IF cardinality(v_missing) > 0 THEN
        RAISE EXCEPTION 'MAIN-158: parts on the price sheet are not in the catalog: %', v_missing;
    END IF;
    RAISE NOTICE 'MAIN-158: % opening lots loaded', v_loaded;
END;
$$;

-- ── Replay: cost every spare and audit loss so far ───────────────────────────

DO $$
DECLARE
    r          record;
    v_pairs    integer := 0;
    v_uncosted integer;
BEGIN
    FOR r IN
        SELECT DISTINCT part_id, company FROM (
            SELECT pii.part_id, pi.billed_to AS company
            FROM   public.purchase_invoice_items pii JOIN public.purchase_invoices pi ON pi.id = pii.invoice_id
            UNION SELECT part_id, company FROM public.opening_stock_lots
            UNION SELECT part_id, company FROM public.part_stock
            UNION SELECT part_id, company FROM public.stock_audit_items
            UNION SELECT ip.part_id, d.key FROM public.issue_parts ip, jsonb_object_keys(ip.stock_draws) d(key)
            UNION SELECT ip.part_id, 'nvs_travels' FROM public.issue_parts ip WHERE ip.stock_draws = '{}'::jsonb
        ) x
    LOOP
        PERFORM public.rebuild_part_cost(r.part_id, r.company);
        v_pairs := v_pairs + 1;
    END LOOP;

    SELECT count(*) INTO v_uncosted FROM public.stock_cost_draws WHERE unit_cost IS NULL;
    RAISE NOTICE 'MAIN-158: % part/company queues rebuilt; % draws with no price', v_pairs, v_uncosted;
END;
$$;

-- ── Keep it current ──────────────────────────────────────────────────────────

-- A spare added, changed or removed. A new spare that finds stock with no price is
-- refused, so the exec is asked for one (PART_NEEDS_PRICE); service-role writes pass.
CREATE OR REPLACE FUNCTION public.stock_cost_on_issue_part_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_company text;
    v_qty     numeric;
    v_part    record;
BEGIN
    -- Closure writes outsource_part_disposition onto spares; nothing that costs them.
    IF TG_OP = 'UPDATE'
       AND (NEW.part_id, NEW.issue_id, NEW.quantity_used, NEW.stock_draws, NEW.added_at)
           IS NOT DISTINCT FROM (OLD.part_id, OLD.issue_id, OLD.quantity_used, OLD.stock_draws, OLD.added_at) THEN
        RETURN NULL;
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        FOR v_company IN
            SELECT k FROM jsonb_object_keys(OLD.stock_draws) k
            UNION SELECT 'nvs_travels' WHERE OLD.stock_draws = '{}'::jsonb
        LOOP
            PERFORM public.rebuild_part_cost(OLD.part_id, v_company);
        END LOOP;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        FOR v_company IN
            SELECT k FROM jsonb_object_keys(NEW.stock_draws) k
            UNION SELECT 'nvs_travels' WHERE NEW.stock_draws = '{}'::jsonb
        LOOP
            PERFORM public.rebuild_part_cost(NEW.part_id, v_company);
        END LOOP;

        IF TG_OP = 'INSERT' AND auth.uid() IS NOT NULL THEN
            SELECT d.company, sum(d.quantity) INTO v_company, v_qty
            FROM   public.stock_cost_draws d
            WHERE  d.issue_part_id = NEW.id AND d.unit_cost IS NULL
            GROUP  BY d.company
            LIMIT  1;

            IF v_qty IS NOT NULL THEN
                SELECT name, unit INTO v_part FROM public.parts WHERE id = NEW.part_id;
                RAISE EXCEPTION 'No price is recorded for % (%): some of its stock never came in on a recorded purchase.',
                    v_part.name, public.stock_company_label(v_company)
                    USING HINT = 'PART_NEEDS_PRICE',
                          DETAIL = json_build_object('part_id', NEW.part_id, 'part_name', v_part.name,
                                                     'unit', v_part.unit, 'company', v_company,
                                                     'quantity', v_qty)::text;
            END IF;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_stock_cost_issue_part
    AFTER INSERT OR UPDATE OR DELETE ON public.issue_parts
    FOR EACH ROW EXECUTE FUNCTION public.stock_cost_on_issue_part_change();

-- A purchase or refurbishment line added, changed or removed.
CREATE OR REPLACE FUNCTION public.stock_cost_on_purchase_line_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_company text;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT billed_to INTO v_company FROM public.purchase_invoices WHERE id = OLD.invoice_id;
        IF v_company IS NULL THEN
            -- The invoice itself is being deleted: rebuild both companies.
            PERFORM public.rebuild_part_cost(OLD.part_id, 'nvs_travels');
            PERFORM public.rebuild_part_cost(OLD.part_id, 'nvs_travel_solutions');
        ELSE
            PERFORM public.rebuild_part_cost(OLD.part_id, v_company);
        END IF;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT billed_to INTO v_company FROM public.purchase_invoices WHERE id = NEW.invoice_id;
        PERFORM public.rebuild_part_cost(NEW.part_id, v_company);
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_stock_cost_purchase_line
    AFTER INSERT OR UPDATE OR DELETE ON public.purchase_invoice_items
    FOR EACH ROW EXECUTE FUNCTION public.stock_cost_on_purchase_line_change();

-- A purchase's Billed to or invoice date changed: its lots move company or place.
CREATE OR REPLACE FUNCTION public.stock_cost_on_purchase_header_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_part uuid;
BEGIN
    IF (NEW.billed_to, NEW.invoice_date, NEW.purchase_number)
       IS NOT DISTINCT FROM (OLD.billed_to, OLD.invoice_date, OLD.purchase_number) THEN
        RETURN NULL;
    END IF;

    FOR v_part IN SELECT DISTINCT part_id FROM public.purchase_invoice_items WHERE invoice_id = NEW.id
    LOOP
        PERFORM public.rebuild_part_cost(v_part, OLD.billed_to);
        IF NEW.billed_to <> OLD.billed_to THEN
            PERFORM public.rebuild_part_cost(v_part, NEW.billed_to);
        END IF;
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_stock_cost_purchase_header
    AFTER UPDATE ON public.purchase_invoices
    FOR EACH ROW EXECUTE FUNCTION public.stock_cost_on_purchase_header_change();

-- An opening lot added (add_opening_stock_price).
CREATE OR REPLACE FUNCTION public.stock_cost_on_opening_lot_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        PERFORM public.rebuild_part_cost(OLD.part_id, OLD.company);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM public.rebuild_part_cost(NEW.part_id, NEW.company);
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_stock_cost_opening_lot
    AFTER INSERT OR UPDATE OR DELETE ON public.opening_stock_lots
    FOR EACH ROW EXECUTE FUNCTION public.stock_cost_on_opening_lot_change();

-- An audit completed: what it found adds lots, what it lost takes them.
CREATE OR REPLACE FUNCTION public.stock_cost_on_audit_completed()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT DISTINCT part_id, company FROM public.stock_audit_items
        WHERE  audit_id = NEW.id AND coalesce(applied_delta, 0) <> 0
    LOOP
        PERFORM public.rebuild_part_cost(r.part_id, r.company);
    END LOOP;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_stock_cost_audit_completed
    AFTER UPDATE OF status ON public.stock_audits
    FOR EACH ROW
    WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
    EXECUTE FUNCTION public.stock_cost_on_audit_completed();

-- ── The safety net: an exec prices stock that has none ───────────────────────
--
-- p_price: { unit_price, gst_rate } — the price for one unit before GST and the GST % on
-- the bill. Adds an opening lot for each company whose stock of the part has no lot.
-- jsonb so later fields need no new parameter (a new parameter under CREATE OR REPLACE
-- makes a second overload).

CREATE OR REPLACE FUNCTION public.add_opening_stock_price(p_part_id uuid, p_price jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_price   numeric;
    v_gst     numeric;
    v_company text;
    v_gap     numeric;
    v_name    text;
    v_added   jsonb := '[]'::jsonb;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION 'Only a maintenance exec can set a part''s price.' USING ERRCODE = '42501';
    END IF;

    PERFORM 1 FROM public.parts WHERE id = p_part_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Part not found.';
    END IF;

    BEGIN
        v_price := (p_price ->> 'unit_price')::numeric;
        v_gst   := (p_price ->> 'gst_rate')::numeric;
    EXCEPTION WHEN others THEN
        RAISE EXCEPTION 'Enter the price and the GST %%.';
    END;
    IF v_price IS NULL OR v_price < 0 THEN
        RAISE EXCEPTION 'Enter a price of 0 or more.';
    END IF;
    IF v_gst IS NULL OR NOT (v_gst = ANY (public.gst_rates())) THEN
        RAISE EXCEPTION 'Choose a GST %% from the list.';
    END IF;

    SELECT name INTO v_name FROM public.users WHERE id = auth.uid();

    FOREACH v_company IN ARRAY ARRAY['nvs_travels', 'nvs_travel_solutions']
    LOOP
        v_gap := public.part_cost_gap(p_part_id, v_company);
        IF v_gap > 0 THEN
            INSERT INTO public.opening_stock_lots (part_id, company, quantity, unit_price, gst_rate, source, created_by, created_by_name)
            VALUES (p_part_id, v_company, v_gap, round(v_price, 2), v_gst, 'exec', auth.uid(), coalesce(v_name, ''));
            v_added := v_added || jsonb_build_object('company', v_company, 'quantity', v_gap);
        END IF;
    END LOOP;

    IF jsonb_array_length(v_added) = 0 THEN
        RAISE EXCEPTION 'All of this part''s stock already has a price.';
    END IF;

    RETURN v_added;
END;
$$;

REVOKE ALL ON FUNCTION public.add_opening_stock_price(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_opening_stock_price(uuid, jsonb) TO authenticated, service_role;

-- ── Values, read as PostgREST computed fields ────────────────────────────────
--
-- Money: shown to maintenance exec, super_admin and finance only; NULL for anyone else.

-- A spare's first-in-first-out cost incl. GST. NULL: an outsourced card's spare (no
-- stock was used) or a quantity with no price.
CREATE OR REPLACE FUNCTION public.spare_cost(ip public.issue_parts)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
    SELECT CASE
        WHEN NOT (public.is_maintenance_exec() OR public.is_finance()) THEN NULL
        WHEN NOT EXISTS (SELECT 1 FROM public.stock_cost_draws d WHERE d.issue_part_id = ip.id) THEN NULL
        WHEN EXISTS (SELECT 1 FROM public.stock_cost_draws d WHERE d.issue_part_id = ip.id AND d.unit_cost IS NULL) THEN NULL
        ELSE (SELECT sum(d.amount) FROM public.stock_cost_draws d WHERE d.issue_part_id = ip.id)
    END;
$$;

-- A job card's value. In-house: its spares' cost (0 with none; NULL if any has no
-- price). Outsourced: its invoice's Approved Amount, else the multi-vehicle invoice lines
-- linked to it (cancelled invoices left out), else NULL (invoice pending).
CREATE OR REPLACE FUNCTION public.job_card_value(jc public.job_cards)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
    SELECT CASE
        WHEN NOT (public.is_maintenance_exec() OR public.is_finance()) THEN NULL
        WHEN jc.type = 'Outsource' THEN coalesce(
            (SELECT max(oi.approved_amount) FROM public.outsource_invoices oi WHERE oi.job_card_id = jc.id),
            (SELECT sum(bsv.amount)
             FROM   public.batch_service_vehicles bsv
             JOIN   public.batch_services bs ON bs.id = bsv.batch_service_id
             WHERE  bsv.job_card_id = jc.id AND bs.status <> 'Cancelled'))
        WHEN EXISTS (
            SELECT 1 FROM public.issues i
            JOIN   public.issue_parts ip ON ip.issue_id = i.id
            JOIN   public.stock_cost_draws d ON d.issue_part_id = ip.id
            WHERE  i.job_card_id = jc.id AND d.unit_cost IS NULL) THEN NULL
        ELSE coalesce((
            SELECT sum(d.amount) FROM public.issues i
            JOIN   public.issue_parts ip ON ip.issue_id = i.id
            JOIN   public.stock_cost_draws d ON d.issue_part_id = ip.id
            WHERE  i.job_card_id = jc.id), 0)
    END;
$$;

REVOKE ALL ON FUNCTION public.spare_cost(public.issue_parts) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.job_card_value(public.job_cards) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.spare_cost(public.issue_parts) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.job_card_value(public.job_cards) TO authenticated, service_role;

-- New tables and indexes: give the planner statistics now, or the job card list's values
-- run as a slow plan until autovacuum gets to them.
ANALYZE public.opening_stock_lots;
ANALYZE public.stock_cost_draws;
ANALYZE public.issue_parts;
ANALYZE public.purchase_invoice_items;
