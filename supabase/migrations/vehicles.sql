-- Vehicles catalog
CREATE TABLE IF NOT EXISTS vehicles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    registration_number TEXT UNIQUE NOT NULL,
    make TEXT,
    model TEXT,
    year INTEGER,
    site TEXT,
    notes TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;

-- All authenticated users can view vehicles
CREATE POLICY "Authenticated users view vehicles" ON vehicles
    FOR SELECT USING (auth.role() = 'authenticated');

-- Only exec and finance can insert/update vehicles
CREATE POLICY "Exec and finance manage vehicles" ON vehicles
    FOR ALL USING (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('maintenance_exec', 'finance'))
    );

-- Give finance read access to job_cards so VehicleHistory and MechanicDetail work for them
CREATE POLICY "Finance view job cards" ON job_cards
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'finance')
    );
