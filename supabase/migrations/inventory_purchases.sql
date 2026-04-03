-- Purchase invoices: one row per supplier invoice
CREATE TABLE IF NOT EXISTS purchase_invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invoice_number TEXT NOT NULL,
    supplier_name TEXT NOT NULL,
    invoice_date DATE NOT NULL,
    total_amount NUMERIC(12,2),
    notes TEXT,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Line items: one row per part per invoice
CREATE TABLE IF NOT EXISTS purchase_invoice_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invoice_id UUID NOT NULL REFERENCES purchase_invoices(id) ON DELETE CASCADE,
    part_id UUID NOT NULL REFERENCES parts(id),
    quantity NUMERIC(10,2) NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    line_total NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED
);

-- RLS
ALTER TABLE purchase_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_invoice_items ENABLE ROW LEVEL SECURITY;

-- maintenance_exec and finance can view all invoices
CREATE POLICY "Exec and finance view invoices" ON purchase_invoices
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('maintenance_exec', 'finance'))
    );

-- maintenance_exec and finance can insert invoices
CREATE POLICY "Exec and finance insert invoices" ON purchase_invoices
    FOR INSERT WITH CHECK (
        auth.uid() = created_by AND
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('maintenance_exec', 'finance'))
    );

-- maintenance_exec and finance can view all invoice items
CREATE POLICY "Exec and finance view invoice items" ON purchase_invoice_items
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('maintenance_exec', 'finance'))
    );

-- maintenance_exec and finance can insert invoice items
CREATE POLICY "Exec and finance insert invoice items" ON purchase_invoice_items
    FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('maintenance_exec', 'finance'))
    );

-- Trigger: add to inventory when a purchase line item is inserted
CREATE OR REPLACE FUNCTION add_part_to_inventory()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE parts
    SET quantity_in_stock = quantity_in_stock + NEW.quantity
    WHERE id = NEW.part_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_add_part_inventory ON purchase_invoice_items;
CREATE TRIGGER trigger_add_part_inventory
    AFTER INSERT ON purchase_invoice_items
    FOR EACH ROW EXECUTE FUNCTION add_part_to_inventory();

-- Allow all authenticated users to view parts (already exists, but ensure finance can too)
-- The existing policy covers 'authenticated' so no change needed for parts SELECT.

-- Allow maintenance_exec and finance to insert/update parts (for bulk upload auto-create)
DROP POLICY IF EXISTS "Execs manage parts" ON parts;
CREATE POLICY "Exec and finance manage parts" ON parts
    FOR ALL USING (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('maintenance_exec', 'finance'))
    );
