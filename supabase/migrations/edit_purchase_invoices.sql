-- Allow maintenance_exec and finance to update purchase invoices
CREATE POLICY "Exec and finance update invoices" ON purchase_invoices
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('maintenance_exec', 'finance'))
    );

-- Allow maintenance_exec and finance to update invoice items
CREATE POLICY "Exec and finance update invoice items" ON purchase_invoice_items
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('maintenance_exec', 'finance'))
    );

-- Allow maintenance_exec and finance to delete invoice items
CREATE POLICY "Exec and finance delete invoice items" ON purchase_invoice_items
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('maintenance_exec', 'finance'))
    );

-- Trigger: adjust inventory when a purchase line item quantity or part is updated
CREATE OR REPLACE FUNCTION adjust_part_inventory_on_update()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.part_id = OLD.part_id THEN
        -- Same part: apply the quantity delta
        UPDATE parts
        SET quantity_in_stock = quantity_in_stock + (NEW.quantity - OLD.quantity)
        WHERE id = NEW.part_id;
    ELSE
        -- Part changed: reverse old part stock, add to new part stock
        UPDATE parts SET quantity_in_stock = quantity_in_stock - OLD.quantity WHERE id = OLD.part_id;
        UPDATE parts SET quantity_in_stock = quantity_in_stock + NEW.quantity WHERE id = NEW.part_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_adjust_part_inventory_on_update ON purchase_invoice_items;
CREATE TRIGGER trigger_adjust_part_inventory_on_update
    AFTER UPDATE ON purchase_invoice_items
    FOR EACH ROW EXECUTE FUNCTION adjust_part_inventory_on_update();

-- Trigger: reverse inventory when a purchase line item is deleted
CREATE OR REPLACE FUNCTION reverse_part_inventory_on_delete()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE parts
    SET quantity_in_stock = quantity_in_stock - OLD.quantity
    WHERE id = OLD.part_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_reverse_part_inventory_on_delete ON purchase_invoice_items;
CREATE TRIGGER trigger_reverse_part_inventory_on_delete
    AFTER DELETE ON purchase_invoice_items
    FOR EACH ROW EXECUTE FUNCTION reverse_part_inventory_on_delete();
