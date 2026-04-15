-- Add GST rate column (stored as a percentage value: 0, 5, 12, 18, or 28)
ALTER TABLE purchase_invoice_items
    ADD COLUMN gst_rate NUMERIC(5,2) NOT NULL DEFAULT 0;

-- Recreate line_total to factor in GST: quantity × unit_price × (1 + gst_rate / 100)
ALTER TABLE purchase_invoice_items DROP COLUMN line_total;
ALTER TABLE purchase_invoice_items
    ADD COLUMN line_total NUMERIC(12,2) GENERATED ALWAYS AS (
        ROUND(quantity * unit_price * (1 + gst_rate / 100.0), 2)
    ) STORED;
