-- Only exec and finance can insert/update vehicles
CREATE POLICY "Exec and finance manage vehicles" ON vehicles
    FOR ALL USING (
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('maintenance_exec', 'finance'))
    );
