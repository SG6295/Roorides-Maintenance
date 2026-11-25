-- MAIN-167: PI-117 is a second copy of PI-116.
-- Both carry the same bill — Shivashakthi Traders invoice 161, 3 Aug 2026, 50 buckets x 20 L
-- of Adblue, Rs 87,500 — uploaded twice (19 Aug as PI-116, 3 Sep as PI-117). Finance's sheet
-- has the bill once. The app has no way to delete a purchase, so it is removed here.
--
-- Deleting the header runs the existing triggers: its line goes first, the 1,000 L leave
-- Bannerghatta's NVS Travels stock, and Adblue (Def) is re-costed first-in-first-out.
-- The removed purchase is kept in audit_logs.

DO $$
DECLARE
  v_pi   public.purchase_invoices;
  v_line jsonb;
BEGIN
  SELECT * INTO v_pi FROM public.purchase_invoices WHERE purchase_number = 117;
  IF NOT FOUND THEN
    RAISE NOTICE 'MAIN-167: PI-117 not found, nothing to do';
    RETURN;
  END IF;

  SELECT jsonb_agg(jsonb_build_object('part_id', it.part_id, 'part', p.name, 'quantity', it.quantity,
                                      'unit_price', it.unit_price, 'gst_rate', it.gst_rate,
                                      'discount_amount', it.discount_amount, 'line_total', it.line_total))
  INTO   v_line
  FROM   public.purchase_invoice_items it JOIN public.parts p ON p.id = it.part_id
  WHERE  it.invoice_id = v_pi.id;

  IF v_pi.invoice_number <> '161'
     OR v_pi.supplier_name NOT ILIKE 'shivashakthi%'
     OR v_pi.invoice_date <> DATE '2026-08-03'
     OR v_pi.total_amount <> 87497.00
     OR jsonb_array_length(v_line) <> 1
     OR v_line->0->>'part' <> 'Adblue (Def)'
     OR (v_line->0->>'quantity')::numeric <> 1000
     OR EXISTS (SELECT 1 FROM public.outsource_invoices WHERE purchase_invoice_id = v_pi.id)
     OR NOT EXISTS (SELECT 1 FROM public.purchase_invoices
                    WHERE purchase_number = 116 AND invoice_number = '161'
                      AND supplier_name ILIKE 'shivashakthi%' AND total_amount = 87497.00)
  THEN
    RAISE EXCEPTION 'MAIN-167: PI-117 is not the duplicate this migration expects; stopping';
  END IF;

  INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data)
  VALUES ('purchase_invoices', v_pi.id, 'DELETE',
          to_jsonb(v_pi) || jsonb_build_object('lines', v_line),
          jsonb_build_object('deleted_by', 'MAIN-167', 'duplicate_of', 'PI-116',
                             'reason', 'Same bill (Shivashakthi 161, 3 Aug 2026) recorded twice'));

  DELETE FROM public.purchase_invoices WHERE id = v_pi.id;
END $$;
