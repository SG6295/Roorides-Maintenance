-- Create system_settings table for global configs
CREATE TABLE IF NOT EXISTS system_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT,
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Everyone can read settings" 
  ON system_settings FOR SELECT 
  USING (true);

CREATE POLICY "Execs can update settings" 
  ON system_settings FOR UPDATE
  USING (
    auth.uid() IN (SELECT id FROM users WHERE role = 'maintenance_exec')
  );

-- Seed Assignment SLA setting
INSERT INTO system_settings (key, value, description)
VALUES ('assignment_sla_days', '1', 'Days allowed to assign a ticket before SLA violation')
ON CONFLICT (key) DO NOTHING;
