-- MAIN-21: Per-line-item discount for purchase invoices.
-- The discount applies to the taxable value BEFORE GST.

-- 1. New canonical column. NOT NULL + DEFAULT 0 so every existing row reads 0
--    (no data backfill needed; also required for prod->staging sync compatibility).
ALTER TABLE public.purchase_invoice_items
    ADD COLUMN discount_amount numeric(12,2) NOT NULL DEFAULT 0;

-- 2. Guardrails: discount is non-negative and cannot exceed the pre-tax subtotal.
ALTER TABLE public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_discount_nonneg
    CHECK (discount_amount >= 0);
ALTER TABLE public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_discount_max
    CHECK (discount_amount <= quantity * unit_price);

-- 3. Redefine line_total to subtract the discount before applying GST.
--    A generated column's expression cannot be altered in place, so drop and
--    re-add it. Existing rows recompute with discount 0 -> identical values.
ALTER TABLE public.purchase_invoice_items DROP COLUMN line_total;
ALTER TABLE public.purchase_invoice_items
    ADD COLUMN line_total numeric(12,2)
    GENERATED ALWAYS AS (
        round((quantity * unit_price - discount_amount) * (1 + gst_rate / 100.0), 2)
    ) STORED;
