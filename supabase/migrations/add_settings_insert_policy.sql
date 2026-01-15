-- Add INSERT policy for system_settings (needed for upsert, or potential future settings)
CREATE POLICY "Execs can insert settings" 
  ON system_settings FOR INSERT
  WITH CHECK (
    auth.uid() IN (SELECT id FROM users WHERE role = 'maintenance_exec')
  );
