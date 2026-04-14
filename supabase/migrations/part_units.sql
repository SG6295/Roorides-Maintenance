-- Part Units: configurable unit-of-measure list for inventory parts

BEGIN;

CREATE TABLE IF NOT EXISTS part_units (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL UNIQUE,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO part_units (name, sort_order) VALUES
    ('pcs',   1),
    ('set',   2),
    ('kg',    3),
    ('g',     4),
    ('litre', 5),
    ('ml',    6),
    ('metre', 7),
    ('cm',    8)
ON CONFLICT (name) DO NOTHING;

ALTER TABLE part_units ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read units
CREATE POLICY "Authenticated read part_units" ON part_units
    FOR SELECT USING (auth.role() = 'authenticated');

-- Only maintenance_exec can insert / update / delete
CREATE POLICY "Execs manage part_units" ON part_units
    FOR ALL
    USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'maintenance_exec'));

COMMIT;
