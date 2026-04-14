-- Add invoice file attachment support to purchase_invoices
ALTER TABLE purchase_invoices
    ADD COLUMN IF NOT EXISTS invoice_file_url TEXT;
