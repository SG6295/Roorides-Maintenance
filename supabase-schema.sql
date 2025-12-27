-- NVS Maintenance Management System
-- Database Schema for Supabase
-- Run this in Supabase SQL Editor

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- TABLES
-- ============================================================================

-- Sites table
CREATE TABLE sites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT UNIQUE NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Vehicles table
CREATE TABLE vehicles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  number TEXT UNIQUE NOT NULL,
  site TEXT REFERENCES sites(name) ON UPDATE CASCADE,
  type TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Users table (extends Supabase auth.users)
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  employee_id TEXT,
  contact TEXT,
  role TEXT CHECK (role IN ('supervisor', 'maintenance_exec', 'finance')) NOT NULL,
  site TEXT REFERENCES sites(name) ON UPDATE CASCADE, -- NULL for exec/finance
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Tickets table
CREATE TABLE tickets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ticket_number INTEGER GENERATED ALWAYS AS IDENTITY (START WITH 1434),
  created_at TIMESTAMP DEFAULT NOW(),

  -- Form data from supervisor
  site TEXT NOT NULL REFERENCES sites(name) ON UPDATE CASCADE,
  vehicle_number TEXT NOT NULL,
  category TEXT CHECK (category IN ('Mechanical', 'Electrical', 'Body', 'Tyre', 'GPS/Camera', 'Other')) NOT NULL,
  complaint TEXT NOT NULL,
  supervisor_name TEXT NOT NULL,
  supervisor_id TEXT NOT NULL,
  supervisor_contact TEXT,
  photos TEXT[], -- Google Drive URLs
  remarks TEXT,

  -- Assignment (by maintenance exec)
  impact TEXT CHECK (impact IN ('Minor', 'Major')),
  job_sheet_id TEXT,
  assigned_date DATE,
  activity_plan_date DATE,
  work_type TEXT CHECK (work_type IN ('In House', 'Outsource')),
  status TEXT CHECK (status IN ('Pending', 'Team Assigned', 'Completed', 'Rejected')) DEFAULT 'Pending',

  -- Completion
  completed_date DATE,
  completion_remarks TEXT,

  -- SLA (computed fields)
  sla_days INTEGER,
  sla_end_date DATE,
  assignment_sla_status TEXT CHECK (assignment_sla_status IN ('Adhered', 'Violated', 'Pending')) DEFAULT 'Pending',
  completion_sla_status TEXT CHECK (completion_sla_status IN ('Adhered', 'Violated', 'Pending')) DEFAULT 'Pending',
  tat_days INTEGER,

  -- CSAT (Phase 4)
  rating TEXT CHECK (rating IN ('Good', 'Ok', 'Bad')),
  csat_score INTEGER CHECK (csat_score IN (0, 1, 2)),

  -- Metadata
  is_duplicate BOOLEAN DEFAULT false,
  merged_into_ticket_id UUID REFERENCES tickets(id),
  created_by_user_id UUID REFERENCES users(id) NOT NULL
);

-- Finance entries table (Phase 2)
CREATE TABLE finance_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMP DEFAULT NOW(),

  work_type TEXT CHECK (work_type IN ('Spare Purchases', 'Outsourced Work', 'Job Card')) NOT NULL,
  activity_date DATE NOT NULL,
  vehicle_number TEXT,
  job_sheet_id TEXT,
  ticket_id UUID REFERENCES tickets(id),
  site TEXT REFERENCES sites(name) ON UPDATE CASCADE,

  -- Vendor details
  vendor_name TEXT,
  vendor_contact TEXT,
  work_description TEXT NOT NULL,
  approved_amount NUMERIC,
  invoice_number TEXT,

  -- Job card specific
  km_reading INTEGER,
  work_inspected_by TEXT,

  -- Payment tracking
  payable_amount NUMERIC,
  advance_amount NUMERIC,
  invoice_value NUMERIC,
  paid_amount NUMERIC,
  payment_date DATE,
  payment_status TEXT CHECK (payment_status IN ('Pending', 'Partial', 'Paid')) DEFAULT 'Pending',
  transaction_details TEXT,
  payment_via TEXT,

  -- Documents (Google Drive URLs)
  bill_attachment TEXT,
  approval_screenshot TEXT,
  job_card_upload TEXT,

  -- Metadata
  created_by_user_id UUID REFERENCES users(id) NOT NULL,
  accounting_status TEXT CHECK (accounting_status IN ('Pending', 'Processed', 'Closed')) DEFAULT 'Pending'
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

CREATE INDEX idx_tickets_site ON tickets(site);
CREATE INDEX idx_tickets_status ON tickets(status);
CREATE INDEX idx_tickets_created_at ON tickets(created_at DESC);
CREATE INDEX idx_tickets_vehicle_number ON tickets(vehicle_number);
CREATE INDEX idx_tickets_job_sheet_id ON tickets(job_sheet_id);
CREATE INDEX idx_tickets_created_by ON tickets(created_by_user_id);
CREATE INDEX idx_finance_job_sheet_id ON finance_entries(job_sheet_id);
CREATE INDEX idx_finance_ticket_id ON finance_entries(ticket_id);
CREATE INDEX idx_finance_site ON finance_entries(site);

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES - TICKETS
-- ============================================================================

-- Supervisors can see only their site's tickets
CREATE POLICY "Supervisors see own site tickets"
  ON tickets FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.role = 'supervisor'
      AND users.site = tickets.site
    )
  );

-- Maintenance exec can see all tickets
CREATE POLICY "Maintenance exec sees all tickets"
  ON tickets FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.role = 'maintenance_exec'
    )
  );

-- Supervisors can create tickets
CREATE POLICY "Supervisors create tickets"
  ON tickets FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.role = 'supervisor'
    )
  );

-- Maintenance exec can update tickets
CREATE POLICY "Maintenance exec updates tickets"
  ON tickets FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.role = 'maintenance_exec'
    )
  );

-- ============================================================================
-- RLS POLICIES - FINANCE ENTRIES
-- ============================================================================

-- Finance team can see all finance entries
CREATE POLICY "Finance sees all entries"
  ON finance_entries FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.role IN ('finance', 'maintenance_exec')
    )
  );

-- Finance team can create entries
CREATE POLICY "Finance creates entries"
  ON finance_entries FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.role = 'finance'
    )
  );

-- Finance team can update entries
CREATE POLICY "Finance updates entries"
  ON finance_entries FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.role = 'finance'
    )
  );

-- ============================================================================
-- RLS POLICIES - USERS
-- ============================================================================

-- Users can see their own profile
CREATE POLICY "Users see own profile"
  ON users FOR SELECT
  USING (auth.uid() = id);

-- Maintenance exec can see all users
CREATE POLICY "Maintenance exec sees all users"
  ON users FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.role = 'maintenance_exec'
    )
  );

-- ============================================================================
-- RLS POLICIES - SITES & VEHICLES
-- ============================================================================

-- Everyone can read sites
CREATE POLICY "All authenticated users see sites"
  ON sites FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- Everyone can read vehicles
CREATE POLICY "All authenticated users see vehicles"
  ON vehicles FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- ============================================================================
-- FUNCTIONS FOR AUTOMATIC SLA CALCULATION
-- ============================================================================

-- Function to calculate SLA days based on impact and category
CREATE OR REPLACE FUNCTION calculate_sla_days(p_impact TEXT, p_category TEXT)
RETURNS INTEGER AS $$
BEGIN
  RETURN CASE
    WHEN p_impact = 'Major' AND p_category = 'Electrical' THEN 7
    WHEN p_impact = 'Major' AND p_category = 'Mechanical' THEN 15
    WHEN p_impact = 'Major' AND p_category = 'Body' THEN 30
    WHEN p_impact = 'Major' AND p_category = 'Tyre' THEN 15
    WHEN p_impact = 'Major' AND p_category = 'GPS/Camera' THEN 3
    WHEN p_impact = 'Minor' THEN 3
    ELSE 3
  END;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update SLA fields when ticket is updated
CREATE OR REPLACE FUNCTION update_ticket_sla()
RETURNS TRIGGER AS $$
BEGIN
  -- Calculate SLA days and end date when impact is assigned
  IF NEW.impact IS NOT NULL AND NEW.category IS NOT NULL THEN
    NEW.sla_days := calculate_sla_days(NEW.impact, NEW.category);
    NEW.sla_end_date := NEW.created_at::DATE + NEW.sla_days;
  END IF;

  -- Update assignment SLA status
  IF NEW.assigned_date IS NOT NULL THEN
    IF (NEW.assigned_date - NEW.created_at::DATE) <= 1 THEN
      NEW.assignment_sla_status := 'Adhered';
    ELSE
      NEW.assignment_sla_status := 'Violated';
    END IF;
  ELSIF (CURRENT_DATE - NEW.created_at::DATE) > 1 THEN
    NEW.assignment_sla_status := 'Violated';
  END IF;

  -- Update completion SLA status
  IF NEW.status = 'Completed' AND NEW.completed_date IS NOT NULL AND NEW.sla_end_date IS NOT NULL THEN
    IF NEW.completed_date <= NEW.sla_end_date THEN
      NEW.completion_sla_status := 'Adhered';
    ELSE
      NEW.completion_sla_status := 'Violated';
    END IF;

    -- Calculate TAT
    NEW.tat_days := NEW.completed_date - NEW.created_at::DATE;
  ELSIF NEW.sla_end_date IS NOT NULL AND CURRENT_DATE > NEW.sla_end_date AND NEW.status != 'Completed' THEN
    NEW.completion_sla_status := 'Violated';
  END IF;

  -- Update CSAT score based on rating
  IF NEW.rating IS NOT NULL THEN
    NEW.csat_score := CASE
      WHEN NEW.rating = 'Good' THEN 2
      WHEN NEW.rating = 'Ok' THEN 1
      WHEN NEW.rating = 'Bad' THEN 0
    END;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_ticket_sla
  BEFORE INSERT OR UPDATE ON tickets
  FOR EACH ROW
  EXECUTE FUNCTION update_ticket_sla();

-- ============================================================================
-- SEED DATA (Optional - add your sites here)
-- ============================================================================

-- Example sites (replace with your actual 60+ sites)
INSERT INTO sites (name) VALUES
  ('Site A'),
  ('Site B'),
  ('Site C')
ON CONFLICT (name) DO NOTHING;

-- Example vehicles (replace with your actual vehicles)
INSERT INTO vehicles (number, site, type) VALUES
  ('KA-01-AB-1234', 'Site A', 'SWARAJ MAZDA (20+1)'),
  ('KA-01-AB-5678', 'Site B', 'TATA LPT 1618')
ON CONFLICT (number) DO NOTHING;

-- ============================================================================
-- VIEWS FOR DASHBOARDS (Optional - Phase 3)
-- ============================================================================

-- View for supervisor dashboard stats
CREATE OR REPLACE VIEW supervisor_dashboard_stats AS
SELECT
  site,
  COUNT(*) FILTER (WHERE status = 'Pending') as pending_count,
  COUNT(*) FILTER (WHERE status = 'Team Assigned') as assigned_count,
  COUNT(*) FILTER (WHERE status = 'Completed') as completed_count,
  COUNT(*) FILTER (WHERE status = 'Rejected') as rejected_count,
  COUNT(*) FILTER (WHERE completion_sla_status = 'Violated') as sla_violated_count,
  ROUND(AVG(csat_score), 2) as avg_csat_score
FROM tickets
GROUP BY site;

-- View for maintenance exec dashboard
CREATE OR REPLACE VIEW maintenance_dashboard_stats AS
SELECT
  COUNT(*) as total_tickets,
  COUNT(*) FILTER (WHERE status = 'Pending') as pending_tickets,
  COUNT(*) FILTER (WHERE assignment_sla_status = 'Violated') as assignment_sla_violated,
  COUNT(*) FILTER (WHERE completion_sla_status = 'Violated') as completion_sla_violated,
  COUNT(*) FILTER (WHERE work_type = 'In House') as inhouse_count,
  COUNT(*) FILTER (WHERE work_type = 'Outsource') as outsource_count,
  ROUND(AVG(tat_days), 1) as avg_tat_days
FROM tickets;

-- ============================================================================
-- DONE!
-- ============================================================================
-- Next steps:
-- 1. Create your first user in Supabase Auth dashboard
-- 2. Add corresponding entry in users table with role
-- 3. Add your actual sites and vehicles
-- 4. Test the application
