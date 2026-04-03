-- Restore inventory when a part is removed from an issue
CREATE OR REPLACE FUNCTION restore_part_to_inventory()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE parts
    SET quantity_in_stock = quantity_in_stock + OLD.quantity_used
    WHERE id = OLD.part_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_restore_part_inventory ON issue_parts;
CREATE TRIGGER trigger_restore_part_inventory
    AFTER DELETE ON issue_parts
    FOR EACH ROW EXECUTE FUNCTION restore_part_to_inventory();

-- Allow mechanics to delete parts on their assigned job cards
CREATE POLICY "Mechanics delete issue parts on assigned cards" ON issue_parts
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM issues i
            JOIN job_cards jc ON jc.id = i.job_card_id
            WHERE i.id = issue_parts.issue_id
            AND (
                jc.assigned_mechanic_id = auth.uid()
                OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'maintenance_exec')
            )
        )
    );
