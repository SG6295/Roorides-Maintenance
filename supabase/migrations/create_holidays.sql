-- Create holidays table
CREATE TABLE IF NOT EXISTS holidays (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  date DATE NOT NULL UNIQUE,
  description TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE holidays ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Everyone can read holidays" 
  ON holidays FOR SELECT 
  USING (true);

CREATE POLICY "Execs can manage holidays" 
  ON holidays FOR ALL
  USING (
    auth.uid() IN (SELECT id FROM users WHERE role = 'maintenance_exec')
  );

-- Add weekly off setting (0=Sunday, 6=Saturday)
INSERT INTO system_settings (key, value, description)
VALUES ('sla_weekly_offs', '[0]', 'Array of day indices (0-6) representing weekly offs')
ON CONFLICT (key) DO NOTHING;
