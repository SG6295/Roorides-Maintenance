-- MAIN-167: correct purchases that differ from the bills and finance's sheet
-- ("Maintenance inventory 26-27", Purchased tab), as approved on the ticket.
-- Every changed line is first checked against its current values; if anything differs the
-- migration stops and changes nothing. Each touched purchase is logged in audit_logs with its
-- before and after (header and lines), marked corrected_by MAIN-167. Totals are recomputed from
-- the lines, and the existing triggers move stock and re-cost first-in-first-out.

CREATE TEMP TABLE m167_fix (pn int, part text, oq numeric, op numeric, od numeric, og numeric,
                            nq numeric, np numeric, nd numeric, ng numeric) ON COMMIT DROP;
INSERT INTO m167_fix VALUES
  (17,'Cotton Waste',5,180.96,0,5,10,180.96,0,5),
  (19,'Brake hose',1,410.99,0,18,2,410.99,0,18),
  (129,'Cotton Waste',5,190.48,0,18,5,190.48,0,5),
  (36,'Coolant Oil (Blue)',40,120,0,0,40,120,0,18),
  (36,'Coolant Oil (Green)',20,120,0,0,20,120,0,18),
  (58,'Retreading Tyre 750',1,3093.22,309.32,18,1,3093.22,154.66,18),
  (68,'New radiator',1,6600,0,0,1,8100,0,0),
  (142,'Air Dryer Kit',3,4270.34,0,18,3,4720.34,0,18),
  (161,'Adblue at site',100,88,0,18,100,88,1342.44,18),
  (162,'Adblue at site',100,88,0,18,100,88,1342.44,18),
  (163,'Adblue at site',150,88,0,18,150,88,2013.66,18),
  (164,'Adblue at site',30,88,0,18,30,88,402.73,18),
  (166,'Brake Oil 500 ml',20,185,0,18,26,247.5,0,18),
  (166,'Brake Oil 500 ml',20,0,0,0,14,247.5,0,18),
  (171,'4mm wire cable',50,15.6,234,18,50,31.2,468,18),
  (189,'Retreading Tyre 235/70',1,3898.3,40,18,1,3898.3,0,18),
  (189,'Retreading Tyre 235/70',1,3728.81,40,18,1,3728.81,0,18),
  (189,'Retreading Tyre 235/70',1,3855.93,337,18,1,3855.93,0,18),
  (190,'Retreading Tyre 750',8,3093.22,0,18,8,3093.22,1237.29,18),
  (190,'Retreading Tyre 825',5,3262.71,0,18,5,3262.71,815.68,18),
  (191,'Retreading Tyre 750',6,3093.22,0,18,6,3093.22,927.97,18),
  (191,'Retreading Tyre 750',1,3262.71,0,18,1,3262.71,163.14,18),
  (191,'Retreading Tyre 750',1,3135.59,0,18,1,3135.59,156.78,18),
  (192,'Retreading Tyre 235/70',2,3983.05,0,18,2,3983.05,398.31,18),
  (192,'Retreading Tyre 235/70',1,4237.29,0,18,1,4237.29,211.86,18),
  (192,'Retreading Tyre 235/70',5,3728.81,0,18,5,3728.81,932.2,18),
  (192,'Retreading Tyre 235/70',3,3559.32,0,18,3,3559.32,533.9,18),
  (193,'Retreading Tyre 750',13,3093.22,0,18,13,3093.22,2010.59,18),
  (196,'Indicator Assy LH',2,80,0,18,2,320,160,18),
  (196,'Indicator Assy RH',2,80,0,18,2,320,160,18),
  (196,'Tail Lamp Glass Kit',4,337,0,18,4,337,337,18),
  (198,'Top Gear Bearing M/Z',1,1059.25,283,18,1,1059.25,0,18),
  (200,'295/80 Retreading tyres',1,6035,0,18,1,6475,0,18),
  (202,'Idler Rij',2,785.59,0,18,2,785.59,283,18),
  (206,'Tt. Striker plate',3,923.73,0,18,3,114.41,0,18),
  (227,'synch Ring Big M/Z',2,1428.78,0,18,2,714.39,0,18),
  (227,'synch Ring Small M/Z',3,1395.96,0,18,3,465.32,0,18),
  (227,'Main shaft bearing',1,143.99,0,18,1,1143.99,0,18),
  (238,'Diesel filter tata',2,831.36,0,18,2,831.36,299.29,18),
  (252,'Brush Holder N/m',1,550,15.25,18,1,550,83.88,18),
  (252,'Starter Field Coil Assy',1,2151,23,18,1,2151,494.73,18),
  (252,'Bend Patti AL',2,75,25,18,2,75,37.5,18),
  (252,'Bolt Kit AL',2,70,25,18,2,70,35,18),
  (252,'Starter carbon brush',2,480,15.25,18,2,480,146.4,18),
  (252,'Pole Screws',4,23,15.25,18,4,23,14.03,18),
  (252,'BulbH4',30,90,15.25,18,30,90,411.75,18);

CREATE TEMP TABLE m167_remove (pn int, part text, oq numeric, op numeric) ON COMMIT DROP;
INSERT INTO m167_remove VALUES (203,'Nox injector',1,5500), (203,'Main relay',1,650);
CREATE TEMP TABLE m167_whole (pn int, inv text, tot numeric) ON COMMIT DROP;
INSERT INTO m167_whole VALUES (170,'8708',9812.92), (22,'1',11000.0);
CREATE TEMP TABLE m167_dates (pn int, od date, nd date) ON COMMIT DROP;
INSERT INTO m167_dates SELECT pn, invoice_date, invoice_date + 1 FROM purchase_invoices pi
  JOIN unnest(ARRAY[26,27,28,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,95,96,97,98,135,136,137,139,140,141,142,143,144,145,146,147,148,149,150,152,153,154,155,156,157,158,159,160,161,162,163,164,165,166,167,168,169,171,172,173,190,191,192,193,194,195,196,197,198,199,200,201,202,204,205,206,207,208,210,211,212,213,216,217,218,219,220,221,222,223,224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,240,241,242,243,244,246,247,248,250,251,252,253,254,255,256]) AS pn ON pn = pi.purchase_number;
INSERT INTO m167_dates VALUES (120,'2026-08-14','2026-08-17'), (189,'2026-06-29','2026-07-03'), (209,'2026-09-19','2026-09-29'), (214,'2026-10-09','2026-10-02'), (215,'2026-10-09','2026-10-03'), (245,'2026-09-19','2026-09-30'), (249,'2026-10-27','2026-10-26'), (30,'2026-05-31','2026-06-01');


-- A purchase that does not exist here at all is skipped (staging was copied from prod before
-- PI-257 was recorded). One that exists but differs from what is expected stops the migration.
DO $$ DECLARE s text; BEGIN
  SELECT string_agg(DISTINCT 'PI-' || pn, ', ') INTO s FROM (SELECT pn FROM m167_fix UNION SELECT pn FROM m167_remove
    UNION SELECT pn FROM m167_whole UNION SELECT pn FROM m167_dates UNION SELECT unnest(ARRAY[1,23,257,94,137])) t
  WHERE pn NOT IN (SELECT purchase_number FROM purchase_invoices);
  IF s IS NOT NULL THEN RAISE NOTICE 'MAIN-167: not present here, skipped: %', s; END IF;
END $$;
DELETE FROM m167_fix WHERE pn NOT IN (SELECT purchase_number FROM purchase_invoices);
DELETE FROM m167_remove WHERE pn NOT IN (SELECT purchase_number FROM purchase_invoices);
DELETE FROM m167_whole WHERE pn NOT IN (SELECT purchase_number FROM purchase_invoices);

CREATE TEMP TABLE m167_touched ON COMMIT DROP AS
SELECT DISTINCT pn FROM (SELECT pn FROM m167_fix UNION SELECT pn FROM m167_remove UNION SELECT pn FROM m167_whole
  UNION SELECT pn FROM m167_dates UNION SELECT unnest(ARRAY[1,23,257,94,94,137])) t
  WHERE pn IN (SELECT purchase_number FROM purchase_invoices);

CREATE TEMP TABLE m167_snap ON COMMIT DROP AS
SELECT pi.purchase_number pn, pi.id,
       to_jsonb(pi) - 'created_at' || jsonb_build_object('lines', (SELECT jsonb_agg(jsonb_build_object('part', p.name, 'quantity', it.quantity,
              'unit_price', it.unit_price, 'discount_amount', it.discount_amount, 'gst_rate', it.gst_rate, 'line_total', it.line_total) ORDER BY p.name, it.unit_price)
              FROM purchase_invoice_items it JOIN parts p ON p.id = it.part_id WHERE it.invoice_id = pi.id)) AS before
FROM purchase_invoices pi JOIN m167_touched t ON t.pn = pi.purchase_number;

DO $$
DECLARE r record; n int;
BEGIN
  IF (SELECT count(*) FROM m167_snap) <> (SELECT count(*) FROM m167_touched) THEN
    RAISE EXCEPTION 'MAIN-167: a purchase to correct is missing';
  END IF;
  FOR r IN SELECT * FROM m167_fix LOOP
    SELECT count(*) INTO n FROM purchase_invoice_items it JOIN purchase_invoices pi ON pi.id = it.invoice_id JOIN parts p ON p.id = it.part_id
    WHERE pi.purchase_number = r.pn AND p.name = r.part AND it.quantity = r.oq AND it.unit_price = r.op
      AND it.discount_amount = r.od AND it.gst_rate = r.og;
    IF n <> 1 THEN RAISE EXCEPTION 'MAIN-167: PI-% % is not as expected (% matches)', r.pn, r.part, n; END IF;
  END LOOP;
  FOR r IN SELECT * FROM m167_remove LOOP
    SELECT count(*) INTO n FROM purchase_invoice_items it JOIN purchase_invoices pi ON pi.id = it.invoice_id JOIN parts p ON p.id = it.part_id
    WHERE pi.purchase_number = r.pn AND p.name = r.part AND it.quantity = r.oq AND it.unit_price = r.op;
    IF n <> 1 THEN RAISE EXCEPTION 'MAIN-167: PI-% % is not as expected', r.pn, r.part; END IF;
  END LOOP;
  FOR r IN SELECT * FROM m167_whole LOOP
    IF NOT EXISTS (SELECT 1 FROM purchase_invoices WHERE purchase_number = r.pn AND invoice_number = r.inv AND total_amount = r.tot)
       OR EXISTS (SELECT 1 FROM outsource_invoices oi JOIN purchase_invoices pi ON pi.id = oi.purchase_invoice_id WHERE pi.purchase_number = r.pn)
    THEN RAISE EXCEPTION 'MAIN-167: PI-% is not the duplicate expected', r.pn; END IF;
  END LOOP;
  FOR r IN SELECT * FROM m167_dates LOOP
    IF NOT EXISTS (SELECT 1 FROM purchase_invoices WHERE purchase_number = r.pn AND invoice_date = r.od) THEN
      RAISE EXCEPTION 'MAIN-167: PI-% date is not as expected', r.pn; END IF;
  END LOOP;
END $$;

-- Lines
UPDATE purchase_invoice_items it SET quantity = f.nq, unit_price = f.np, discount_amount = f.nd, gst_rate = f.ng
FROM m167_fix f, purchase_invoices pi, parts p
WHERE pi.id = it.invoice_id AND p.id = it.part_id AND pi.purchase_number = f.pn AND p.name = f.part
  AND it.quantity = f.oq AND it.unit_price = f.op AND it.discount_amount = f.od AND it.gst_rate = f.og;

INSERT INTO purchase_invoice_items (invoice_id, part_id, quantity, unit_price, discount_amount, gst_rate)
SELECT pi.id, (SELECT id FROM parts WHERE name = 'Tie rod End Kit'), 2, 935.87, 0, 18 FROM purchase_invoices pi WHERE pi.purchase_number = 1;
DELETE FROM purchase_invoice_items it USING m167_remove r, purchase_invoices pi, parts p
WHERE pi.id = it.invoice_id AND p.id = it.part_id AND pi.purchase_number = r.pn AND p.name = r.part AND it.quantity = r.oq AND it.unit_price = r.op;
DELETE FROM purchase_invoices WHERE purchase_number IN (SELECT pn FROM m167_whole);

-- Headers

UPDATE purchase_invoices SET invoice_number = '3335' WHERE purchase_number = 23 AND invoice_number = '335';
UPDATE purchase_invoices SET invoice_number = '6440' WHERE purchase_number = 257 AND invoice_number = '440';
UPDATE purchase_invoices SET invoice_number = '1126' WHERE purchase_number = 94 AND invoice_number = '1198';
UPDATE purchase_invoices SET invoice_date = '2026-07-03' WHERE purchase_number = 94 AND invoice_date = '2026-07-02';
UPDATE purchase_invoices SET supplier_name = 'AGASTYA AUTOMOBILES PVT LTD' WHERE purchase_number = 137 AND supplier_name = 'KHIVRAJ ELIXIR PRIVATE LIMITED (SERVICE)';
UPDATE purchase_invoices pi SET invoice_date = d.nd FROM m167_dates d WHERE pi.purchase_number = d.pn AND pi.invoice_date = d.od;
UPDATE purchase_invoices pi SET total_amount = (SELECT coalesce(sum(line_total), 0) FROM purchase_invoice_items WHERE invoice_id = pi.id)
WHERE pi.purchase_number IN (SELECT pn FROM m167_touched);

-- History: one entry per purchase, before and after
INSERT INTO audit_logs (table_name, record_id, action, old_data, new_data)
SELECT 'purchase_invoices', s.id,
       CASE WHEN pi.id IS NULL THEN 'DELETE' ELSE 'UPDATE' END,
       s.before,
       CASE WHEN pi.id IS NULL THEN jsonb_build_object('deleted_by', 'MAIN-167', 'reason', 'Duplicate of a purchase already recorded')
            ELSE to_jsonb(pi) - 'created_at' || jsonb_build_object('corrected_by', 'MAIN-167', 'lines', (SELECT jsonb_agg(jsonb_build_object('part', p.name,
                 'quantity', it.quantity, 'unit_price', it.unit_price, 'discount_amount', it.discount_amount, 'gst_rate', it.gst_rate,
                 'line_total', it.line_total) ORDER BY p.name, it.unit_price)
                 FROM purchase_invoice_items it JOIN parts p ON p.id = it.part_id WHERE it.invoice_id = pi.id)) END
FROM m167_snap s LEFT JOIN purchase_invoices pi ON pi.id = s.id;
