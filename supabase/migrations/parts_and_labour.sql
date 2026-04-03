-- Add Blocked status to issue_status enum
ALTER TYPE issue_status ADD VALUE IF NOT EXISTS 'Blocked';

-- Add labour_hours to issues
ALTER TABLE issues ADD COLUMN IF NOT EXISTS labour_hours NUMERIC(5,2);

-- Parts inventory catalog
CREATE TABLE IF NOT EXISTS parts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    part_number TEXT,
    unit TEXT DEFAULT 'pcs',
    quantity_in_stock NUMERIC(10,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Parts used per issue
CREATE TABLE IF NOT EXISTS issue_parts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    issue_id UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
    part_id UUID NOT NULL REFERENCES parts(id),
    quantity_used NUMERIC(10,2) NOT NULL CHECK (quantity_used > 0),
    added_by UUID REFERENCES users(id),
    added_at TIMESTAMP DEFAULT NOW()
);

-- RLS
ALTER TABLE parts ENABLE ROW LEVEL SECURITY;
ALTER TABLE issue_parts ENABLE ROW LEVEL SECURITY;

-- Parts: all authenticated users can view
CREATE POLICY "Authenticated users view parts" ON parts
    FOR SELECT USING (auth.role() = 'authenticated');

-- Parts: only exec can insert/update/delete
CREATE POLICY "Execs manage parts" ON parts
    FOR ALL USING (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'maintenance_exec')
    );

-- issue_parts: mechanics can view parts for their assigned job card issues, exec can view all
CREATE POLICY "View issue parts" ON issue_parts
    FOR SELECT USING (
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

-- issue_parts: mechanics can add parts on their assigned job cards
CREATE POLICY "Mechanics insert issue parts" ON issue_parts
    FOR INSERT WITH CHECK (
        auth.uid() = added_by AND
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

-- Trigger: deduct from inventory when part is used
CREATE OR REPLACE FUNCTION deduct_part_from_inventory()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE parts
    SET quantity_in_stock = quantity_in_stock - NEW.quantity_used
    WHERE id = NEW.part_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_deduct_part_inventory ON issue_parts;
CREATE TRIGGER trigger_deduct_part_inventory
    AFTER INSERT ON issue_parts
    FOR EACH ROW EXECUTE FUNCTION deduct_part_from_inventory();
