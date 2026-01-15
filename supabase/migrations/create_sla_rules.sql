-- Create SLA Rules table
CREATE TABLE IF NOT EXISTS sla_rules (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  impact TEXT NOT NULL,   -- e.g., 'Major', 'Minor'
  category TEXT NOT NULL, -- e.g., 'Mechanical', 'Electrical'
  days INTEGER NOT NULL DEFAULT 3,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  
  -- Add unique constraint to prevent duplicates
  UNIQUE(impact, category)
);

-- Enable RLS
ALTER TABLE sla_rules ENABLE ROW LEVEL SECURITY;

-- Policies
-- Everyone can read
CREATE POLICY "Everyone can read SLA rules" 
  ON sla_rules FOR SELECT 
  USING (true);

-- Only Maintenance Execs (or admins) can update
CREATE POLICY "Execs can update SLA rules" 
  ON sla_rules FOR UPDATE
  USING (
    auth.uid() IN (SELECT id FROM users WHERE role = 'maintenance_exec')
  );

-- Seed Initial Data (From PRD)
INSERT INTO sla_rules (impact, category, days) VALUES
  ('Major', 'Mechanical', 15),
  ('Major', 'Electrical', 7),
  ('Major', 'Body', 30),
  ('Major', 'Tyre', 15),
  ('Major', 'GPS/Camera', 3),
  ('Minor', 'Mechanical', 3),
  ('Minor', 'Electrical', 3),
  ('Minor', 'Body', 3),
  ('Minor', 'Tyre', 3),
  ('Minor', 'GPS/Camera', 3),
  ('Minor', 'Other', 3),
  ('Major', 'Other', 7)
ON CONFLICT (impact, category) DO NOTHING;
