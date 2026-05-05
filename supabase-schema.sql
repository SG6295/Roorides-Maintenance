-- NVS Maintenance Management System — Full Database Schema
-- Regenerated from live Supabase DB: 2026-05-05
-- This file is the canonical schema reference. Update it after every migration.
-- It is NOT guaranteed to be executable top-to-bottom on a fresh DB;
-- use it as a reference for table structure, triggers, policies, and functions.

-- ============================================================================
-- EXTENSIONS
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";       -- Used to schedule sync-roorides-vehicles nightly

-- ============================================================================
-- ENUMS
-- ============================================================================

CREATE TYPE issue_category AS ENUM ('Mechanical','Electrical','Body','Tyre','GPS','AdBlue','Other');
CREATE TYPE issue_severity  AS ENUM ('Minor','Major');
CREATE TYPE issue_status    AS ENUM ('Open','Done','Blocked');
CREATE TYPE job_card_status AS ENUM ('Open','Completed');
CREATE TYPE rating_enum     AS ENUM ('Good','Ok','Bad');
CREATE TYPE sla_status_enum AS ENUM ('Pending','Adhered','Violated');
CREATE TYPE ticket_status_new AS ENUM ('New','Accepted','Work In Progress','Resolved','Closed','Rejected');
CREATE TYPE work_type_enum  AS ENUM ('InHouse','Outsource');

-- ============================================================================
-- TABLES (dependency order)
-- ============================================================================

-- Sites
CREATE TABLE sites (
  id         UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  name       TEXT NOT NULL UNIQUE,
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT now()
);

-- Parts catalog
CREATE TABLE parts (
  id                UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  name              TEXT NOT NULL,
  part_number       TEXT,
  unit              TEXT DEFAULT 'pcs',
  quantity_in_stock NUMERIC NOT NULL DEFAULT 0,
  created_at        TIMESTAMP DEFAULT now()
);

-- Part units (labels like kg, pcs, litre)
CREATE TABLE part_units (
  id         UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  name       TEXT NOT NULL UNIQUE,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT now()
);

-- Holidays (used for SLA business-day calculation)
CREATE TABLE holidays (
  id          UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  date        DATE NOT NULL UNIQUE,
  description TEXT,
  created_at  TIMESTAMP DEFAULT now()
);

-- System settings (key-value store for SLA config, weekly offs, etc.)
CREATE TABLE system_settings (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  description TEXT,
  updated_at  TIMESTAMP DEFAULT now()
);

-- Users (extends auth.users)
CREATE TABLE users (
  id          UUID PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  email       TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  employee_id TEXT,
  contact     TEXT,
  role        TEXT NOT NULL CHECK (role IN ('supervisor','maintenance_exec','super_admin','mechanic','electrician','finance')),
  site        TEXT,                -- Legacy; authoritative source for supervisors is user_sites
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMP DEFAULT now()
);

-- User settings (notification preferences)
CREATE TABLE user_settings (
  user_id             UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  notify_daily_digest BOOLEAN DEFAULT false,
  digest_preferences  JSONB DEFAULT '{"created_24h": true, "rejected_24h": true, "sla_expiring": true}',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

-- User ↔ Site junction (supervisors can have multiple sites)
CREATE TABLE user_sites (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  site_id    UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, site_id)
);

-- Vehicles
CREATE TABLE vehicles (
  id                  UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  registration_number TEXT NOT NULL UNIQUE,
  type                TEXT,
  is_active           BOOLEAN DEFAULT true,
  created_at          TIMESTAMP DEFAULT now(),
  make                TEXT,
  model               TEXT,
  year                INTEGER,
  notes               TEXT,
  raw_data            JSONB     -- Raw payload from Roorides API sync
);

-- Vehicle ↔ Site junction
CREATE TABLE vehicle_sites (
  vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  site_name  TEXT NOT NULL,
  PRIMARY KEY (vehicle_id, site_name)
);

-- Tickets (submitted by supervisors)
CREATE TABLE tickets (
  id                   UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  ticket_number        INTEGER GENERATED ALWAYS AS IDENTITY (START WITH 1434),
  created_at           TIMESTAMP DEFAULT now(),
  site                 TEXT NOT NULL,
  vehicle_number       TEXT NOT NULL,
  supervisor_name      TEXT NOT NULL,
  supervisor_id        TEXT NOT NULL,
  supervisor_contact   TEXT,
  photos               TEXT[],                            -- Google Drive URLs
  status               ticket_status_new DEFAULT 'New',
  tat_days             INTEGER,
  is_duplicate         BOOLEAN DEFAULT false,
  merged_into_ticket_id UUID REFERENCES tickets(id),
  created_by_user_id   UUID NOT NULL REFERENCES users(id),
  rating_comment       TEXT,
  rated_at             TIMESTAMPTZ,
  initial_remarks      TEXT,
  rejected_reason      TEXT,
  resolved_at          TIMESTAMP,
  closed_at            TIMESTAMP,
  final_sla_end_date   DATE,                             -- MAX(issues.sla_end_date), set by trigger
  overall_sla_status   sla_status_enum,                  -- Set by trigger
  rejection_reason     TEXT,
  rejection_comment    TEXT,
  acceptance_sla_status sla_status_enum DEFAULT 'Pending',
  rejected_at          TIMESTAMPTZ
);

-- Job cards (InHouse or Outsource work orders)
CREATE TABLE job_cards (
  id                  UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  job_card_number     INTEGER GENERATED ALWAYS AS IDENTITY,
  created_at          TIMESTAMP DEFAULT now(),
  type                work_type_enum NOT NULL,
  assigned_mechanic_id UUID REFERENCES users(id),        -- NULL for Outsource
  vendor_name         TEXT,                              -- NULL for InHouse
  vehicle_number      TEXT NOT NULL,
  site                TEXT NOT NULL,
  status              job_card_status DEFAULT 'Open',
  completed_at        TIMESTAMP,
  remarks             TEXT
);

-- Issues (individual problems within a ticket)
CREATE TABLE issues (
  id             UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  issue_number   TEXT,                                   -- e.g. T-1434-01, auto-generated by trigger
  created_at     TIMESTAMP DEFAULT now(),
  ticket_id      UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  job_card_id    UUID REFERENCES job_cards(id),          -- NULL until assigned
  description    TEXT NOT NULL,
  category       issue_category NOT NULL,
  severity       issue_severity DEFAULT 'Minor',
  work_type      work_type_enum,
  status         issue_status DEFAULT 'Open',
  sla_days       INTEGER,                                -- Set by trigger from sla_rules_config
  sla_end_date   DATE,                                   -- Set by trigger
  sla_status     sla_status_enum DEFAULT 'Pending',
  rating         rating_enum,                            -- Supervisor feedback (Good/Ok/Bad)
  rating_remarks TEXT,
  rated_at       TIMESTAMP,
  labour_hours   NUMERIC
);

-- Parts consumed on an issue (within a job card)
CREATE TABLE issue_parts (
  id            UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  issue_id      UUID NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
  part_id       UUID NOT NULL REFERENCES parts(id),
  quantity_used NUMERIC NOT NULL,
  added_by      UUID REFERENCES users(id),
  added_at      TIMESTAMP DEFAULT now()
);

-- Purchase invoices (inventory restocking)
CREATE TABLE purchase_invoices (
  id               UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  invoice_number   TEXT NOT NULL,
  supplier_name    TEXT NOT NULL,
  invoice_date     DATE NOT NULL,
  total_amount     NUMERIC,
  notes            TEXT,
  created_by       UUID REFERENCES users(id),
  created_at       TIMESTAMP DEFAULT now(),
  invoice_file_url TEXT
);

-- Line items on a purchase invoice
CREATE TABLE purchase_invoice_items (
  id         UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  invoice_id UUID NOT NULL REFERENCES purchase_invoices(id) ON DELETE CASCADE,
  part_id    UUID NOT NULL REFERENCES parts(id),
  quantity   NUMERIC NOT NULL,
  unit_price NUMERIC NOT NULL,
  gst_rate   NUMERIC NOT NULL DEFAULT 0,
  line_total NUMERIC
);

-- Finance entries (manual cost tracking)
CREATE TABLE finance_entries (
  id                 UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  created_at         TIMESTAMP DEFAULT now(),
  work_type          TEXT NOT NULL,
  activity_date      DATE NOT NULL,
  vehicle_number     TEXT,
  job_sheet_id       TEXT,
  ticket_id          UUID REFERENCES tickets(id),
  site               TEXT,
  vendor_name        TEXT,
  vendor_contact     TEXT,
  work_description   TEXT NOT NULL,
  approved_amount    NUMERIC,
  invoice_number     TEXT,
  km_reading         INTEGER,
  work_inspected_by  TEXT,
  payable_amount     NUMERIC,
  advance_amount     NUMERIC,
  invoice_value      NUMERIC,
  paid_amount        NUMERIC,
  payment_date       DATE,
  payment_status     TEXT DEFAULT 'Pending',
  transaction_details TEXT,
  payment_via        TEXT,
  bill_attachment    TEXT,
  approval_screenshot TEXT,
  job_card_upload    TEXT,
  created_by_user_id UUID NOT NULL REFERENCES users(id),
  accounting_status  TEXT DEFAULT 'Pending'
);

-- SLA rules (legacy impact+category model; still present, not used by triggers)
CREATE TABLE sla_rules (
  id         UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  impact     TEXT NOT NULL,
  category   TEXT NOT NULL,
  days       INTEGER NOT NULL DEFAULT 3,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  UNIQUE (impact, category)
);

-- SLA rules config (active model: category+severity → days; used by triggers)
CREATE TABLE sla_rules_config (
  id       UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  category issue_category NOT NULL,
  severity issue_severity NOT NULL,
  sla_days INTEGER NOT NULL,
  UNIQUE (category, severity)
);

-- SLA timeline events (surfaced via useSLAEvents hook)
CREATE TABLE sla_events (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id  UUID REFERENCES tickets(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  created_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  metadata   JSONB DEFAULT '{}'
);

-- Audit logs (covers ticket, issue, and job card changes)
CREATE TABLE audit_logs (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name     TEXT NOT NULL,
  record_id      UUID NOT NULL,
  action         TEXT NOT NULL,
  old_data       JSONB,
  new_data       JSONB,
  changed_fields TEXT[],
  performed_by   UUID REFERENCES users(id),
  performed_at   TIMESTAMPTZ DEFAULT now()
);

-- Suppliers (self-registered via public /supplier-registration route)
CREATE TABLE suppliers (
  id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at                 TIMESTAMPTZ DEFAULT now(),
  status                     TEXT DEFAULT 'pending',       -- pending | approved | rejected
  email                      TEXT NOT NULL,
  entity_name                TEXT NOT NULL,
  entity_type                TEXT NOT NULL,
  entity_type_other          TEXT,
  registered_office_address  TEXT NOT NULL,
  nature_of_work             TEXT NOT NULL,
  workshop_address           TEXT,
  owner_name                 TEXT NOT NULL,
  owner_contact              TEXT NOT NULL,
  owner_email                TEXT,
  accounts_contact_name      TEXT,
  accounts_contact_number    TEXT NOT NULL,
  accounts_email             TEXT,
  sales_contact_name         TEXT,
  sales_contact_number       TEXT,
  sales_email                TEXT,
  po_communication_emails    TEXT,
  pan_number                 TEXT NOT NULL UNIQUE,
  pan_copy_url               TEXT NOT NULL,
  gstin                      TEXT NOT NULL,
  gst_registration_type      TEXT NOT NULL,
  gst_certificate_url        TEXT,
  msme_udyam_number          TEXT,
  udyam_certificate_url      TEXT,
  pf_registration_number     TEXT,
  pf_certificate_url         TEXT,
  esi_registration_number    TEXT,
  esi_certificate_url        TEXT,
  labour_license_number      TEXT,
  bank_name                  TEXT NOT NULL,
  bank_branch                TEXT NOT NULL,
  account_holder_name        TEXT NOT NULL,
  account_number             TEXT NOT NULL,
  ifsc_code                  TEXT NOT NULL,
  account_type               TEXT,
  cancelled_cheque_url       TEXT NOT NULL,
  years_of_experience        TEXT NOT NULL,
  major_clients              TEXT,
  skilled_manpower_available BOOLEAN,
  brand_spares_usage         TEXT,
  payment_terms_days         TEXT NOT NULL,
  submitted_by               TEXT NOT NULL
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX idx_finance_job_sheet_id ON finance_entries(job_sheet_id);
CREATE INDEX idx_finance_site         ON finance_entries(site);
CREATE INDEX idx_finance_ticket_id    ON finance_entries(ticket_id);

CREATE UNIQUE INDEX holidays_date_key ON holidays(date);

CREATE INDEX idx_issues_job_card_id ON issues(job_card_id);
CREATE INDEX idx_issues_status      ON issues(status);
CREATE INDEX idx_issues_ticket_id   ON issues(ticket_id);

CREATE INDEX idx_job_cards_mechanic ON job_cards(assigned_mechanic_id);
CREATE INDEX idx_job_cards_status   ON job_cards(status);

CREATE UNIQUE INDEX part_units_name_key ON part_units(name);
CREATE UNIQUE INDEX sites_name_key      ON sites(name);

CREATE INDEX idx_sla_events_ticket_id ON sla_events(ticket_id);

CREATE UNIQUE INDEX sla_rules_impact_category_key        ON sla_rules(impact, category);
CREATE UNIQUE INDEX sla_rules_config_category_severity_key ON sla_rules_config(category, severity);

CREATE UNIQUE INDEX suppliers_pan_number_key ON suppliers(pan_number);

CREATE INDEX idx_tickets_created_at    ON tickets(created_at DESC);
CREATE INDEX idx_tickets_created_by    ON tickets(created_by_user_id);
CREATE INDEX idx_tickets_site          ON tickets(site);
CREATE INDEX idx_tickets_status        ON tickets(status);
CREATE INDEX idx_tickets_vehicle_number ON tickets(vehicle_number);

CREATE UNIQUE INDEX user_sites_user_id_site_id_key ON user_sites(user_id, site_id);
CREATE UNIQUE INDEX users_email_key                ON users(email);
CREATE UNIQUE INDEX vehicles_number_key            ON vehicles(registration_number);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE audit_logs            ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance_entries       ENABLE ROW LEVEL SECURITY;
ALTER TABLE holidays              ENABLE ROW LEVEL SECURITY;
ALTER TABLE issue_parts           ENABLE ROW LEVEL SECURITY;
ALTER TABLE issues                ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_cards             ENABLE ROW LEVEL SECURITY;
ALTER TABLE part_units            ENABLE ROW LEVEL SECURITY;
ALTER TABLE parts                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_invoices     ENABLE ROW LEVEL SECURITY;
ALTER TABLE sites                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE sla_events            ENABLE ROW LEVEL SECURITY;
ALTER TABLE sla_rules             ENABLE ROW LEVEL SECURITY;
ALTER TABLE sla_rules_config      ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers             ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_settings       ENABLE ROW LEVEL SECURITY;
ALTER TABLE tickets               ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_settings         ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sites            ENABLE ROW LEVEL SECURITY;
ALTER TABLE users                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicle_sites         ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicles              ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

-- audit_logs
CREATE POLICY "Users can insert audit logs" ON audit_logs FOR INSERT WITH CHECK (auth.uid() = performed_by);
CREATE POLICY "Users can view audit logs"   ON audit_logs FOR SELECT USING (auth.role() = 'authenticated');

-- finance_entries
CREATE POLICY "Finance sees all entries"   ON finance_entries FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['finance','maintenance_exec','super_admin'])));
CREATE POLICY "Finance creates entries"    ON finance_entries FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['finance','super_admin'])));
CREATE POLICY "Finance updates entries"    ON finance_entries FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['finance','super_admin'])));

-- holidays
CREATE POLICY "Everyone can read holidays"       ON holidays FOR SELECT USING (true);
CREATE POLICY "Super admins can insert holidays" ON holidays FOR INSERT WITH CHECK (is_super_admin());
CREATE POLICY "Super admins can update holidays" ON holidays FOR UPDATE USING (is_super_admin());
CREATE POLICY "Super admins can delete holidays" ON holidays FOR DELETE USING (is_super_admin());

-- issue_parts
CREATE POLICY "View issue parts"                   ON issue_parts FOR SELECT USING (EXISTS (SELECT 1 FROM (issues i JOIN job_cards jc ON jc.id = i.job_card_id) WHERE i.id = issue_parts.issue_id AND (jc.assigned_mechanic_id = auth.uid() OR is_maintenance_exec())));
CREATE POLICY "Mechanics insert issue parts"       ON issue_parts FOR INSERT WITH CHECK (auth.uid() = added_by AND EXISTS (SELECT 1 FROM (issues i JOIN job_cards jc ON jc.id = i.job_card_id) WHERE i.id = issue_parts.issue_id AND (jc.assigned_mechanic_id = auth.uid() OR is_maintenance_exec())));
CREATE POLICY "Mechanics delete issue parts on assigned cards" ON issue_parts FOR DELETE USING (EXISTS (SELECT 1 FROM (issues i JOIN job_cards jc ON jc.id = i.job_card_id) WHERE i.id = issue_parts.issue_id AND (jc.assigned_mechanic_id = auth.uid() OR is_maintenance_exec())));

-- issues
CREATE POLICY "Execs manage issues"                   ON issues FOR ALL USING (is_maintenance_exec());
CREATE POLICY "Supervisors create issues"             ON issues FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM (tickets t JOIN users u ON u.id = auth.uid()) WHERE t.id = issues.ticket_id AND u.role = 'supervisor' AND t.site IN (SELECT s.name FROM (user_sites us JOIN sites s ON s.id = us.site_id) WHERE us.user_id = auth.uid())));
CREATE POLICY "Supervisors view site issues"          ON issues FOR SELECT USING (EXISTS (SELECT 1 FROM tickets t WHERE t.id = issues.ticket_id AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'supervisor')) AND t.site IN (SELECT s.name FROM (user_sites us JOIN sites s ON s.id = us.site_id) WHERE us.user_id = auth.uid())));
CREATE POLICY "Supervisors update own ratings"        ON issues FOR UPDATE USING (EXISTS (SELECT 1 FROM tickets t WHERE t.id = issues.ticket_id AND (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'supervisor')) AND t.site IN (SELECT s.name FROM (user_sites us JOIN sites s ON s.id = us.site_id) WHERE us.user_id = auth.uid())));
CREATE POLICY "Mechanics view issues on assigned cards" ON issues FOR SELECT USING (EXISTS (SELECT 1 FROM job_cards WHERE job_cards.id = issues.job_card_id AND job_cards.assigned_mechanic_id = auth.uid()));
CREATE POLICY "Mechanics update issues on assigned cards" ON issues FOR UPDATE USING (EXISTS (SELECT 1 FROM job_cards WHERE job_cards.id = issues.job_card_id AND job_cards.assigned_mechanic_id = auth.uid()));

-- job_cards
CREATE POLICY "Execs manage job cards"        ON job_cards FOR ALL USING (is_maintenance_exec());
CREATE POLICY "Finance view job cards"        ON job_cards FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'finance'));
CREATE POLICY "Mechanics view assigned cards" ON job_cards FOR SELECT USING (assigned_mechanic_id = auth.uid() OR is_maintenance_exec());
CREATE POLICY "Mechanics update assigned cards" ON job_cards FOR UPDATE USING (assigned_mechanic_id = auth.uid());

-- part_units
CREATE POLICY "Authenticated read part_units" ON part_units FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Execs manage part_units"       ON part_units FOR ALL USING (is_maintenance_exec());

-- parts
CREATE POLICY "Authenticated users view parts"     ON parts FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Exec and finance manage parts"      ON parts FOR ALL USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','finance','super_admin'])));

-- purchase_invoice_items
CREATE POLICY "Exec and finance view invoice items"   ON purchase_invoice_items FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','finance','super_admin'])));
CREATE POLICY "Exec and finance insert invoice items" ON purchase_invoice_items FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','finance','super_admin'])));
CREATE POLICY "Exec and finance update invoice items" ON purchase_invoice_items FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','finance','super_admin'])));
CREATE POLICY "Exec and finance delete invoice items" ON purchase_invoice_items FOR DELETE USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','finance','super_admin'])));

-- purchase_invoices
CREATE POLICY "Exec and finance view invoices"   ON purchase_invoices FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','finance','super_admin'])));
CREATE POLICY "Exec and finance insert invoices" ON purchase_invoices FOR INSERT WITH CHECK (auth.uid() = created_by AND EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','finance','super_admin'])));
CREATE POLICY "Exec and finance update invoices" ON purchase_invoices FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','finance','super_admin'])));

-- sites
CREATE POLICY "All authenticated users see sites" ON sites FOR SELECT USING (auth.uid() IS NOT NULL);

-- sla_events
CREATE POLICY "Users can view events for tickets they can access" ON sla_events FOR SELECT USING (EXISTS (SELECT 1 FROM tickets WHERE tickets.id = sla_events.ticket_id));
CREATE POLICY "Users can insert events" ON sla_events FOR INSERT WITH CHECK (auth.uid() = created_by);

-- sla_rules
CREATE POLICY "Everyone can read SLA rules"      ON sla_rules FOR SELECT USING (true);
CREATE POLICY "Super admins can update SLA rules" ON sla_rules FOR UPDATE USING (is_super_admin()) WITH CHECK (is_super_admin());

-- suppliers
CREATE POLICY "suppliers_auth_select"   ON suppliers FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','finance','super_admin']) AND users.is_active = true));
CREATE POLICY "suppliers_public_insert" ON suppliers FOR INSERT WITH CHECK (true);  -- Public: no auth required
CREATE POLICY "suppliers_exec_update"   ON suppliers FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','super_admin']) AND users.is_active = true));

-- system_settings
CREATE POLICY "Everyone can read settings"        ON system_settings FOR SELECT USING (true);
CREATE POLICY "Super admins can insert settings"  ON system_settings FOR INSERT WITH CHECK (is_super_admin());
CREATE POLICY "Super admins can update settings"  ON system_settings FOR UPDATE USING (is_super_admin()) WITH CHECK (is_super_admin());

-- tickets
CREATE POLICY "Supervisors see own site tickets"      ON tickets FOR SELECT USING ((EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'supervisor')) AND site IN (SELECT s.name FROM (user_sites us JOIN sites s ON s.id = us.site_id) WHERE us.user_id = auth.uid()));
CREATE POLICY "Execs can see all tickets"             ON tickets FOR SELECT USING (is_maintenance_exec());
CREATE POLICY "Maintenance exec sees all tickets"     ON tickets FOR SELECT USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'maintenance_exec'));
CREATE POLICY "Supervisors and execs create tickets"  ON tickets FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['supervisor','maintenance_exec','super_admin'])));
CREATE POLICY "Execs can update tickets"              ON tickets FOR UPDATE USING (is_maintenance_exec());
CREATE POLICY "Maintenance exec updates tickets"      ON tickets FOR UPDATE USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'maintenance_exec'));
CREATE POLICY "Creators can rate tickets"             ON tickets FOR UPDATE TO authenticated USING (auth.uid() = created_by_user_id) WITH CHECK (auth.uid() = created_by_user_id);

-- user_settings
CREATE POLICY "Users can view their own settings"   ON user_settings FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own settings" ON user_settings FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own settings" ON user_settings FOR UPDATE USING (auth.uid() = user_id);

-- user_sites
CREATE POLICY "user_sites_select" ON user_sites FOR SELECT USING (user_id = auth.uid() OR is_maintenance_exec());
CREATE POLICY "user_sites_insert" ON user_sites FOR INSERT WITH CHECK (is_maintenance_exec());
CREATE POLICY "user_sites_delete" ON user_sites FOR DELETE USING (is_maintenance_exec());

-- users
CREATE POLICY "Users can read own profile"    ON users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Execs can read all profiles"   ON users FOR SELECT USING (is_maintenance_exec());
CREATE POLICY "Execs can update users"        ON users FOR UPDATE USING (is_maintenance_exec());

-- vehicle_sites
CREATE POLICY "Authenticated users can read vehicle_sites" ON vehicle_sites FOR SELECT USING (auth.role() = 'authenticated');

-- vehicles
CREATE POLICY "All authenticated users see vehicles" ON vehicles FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "Authenticated users view vehicles"    ON vehicles FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Exec and finance manage vehicles"     ON vehicles FOR ALL USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = ANY(ARRAY['maintenance_exec','finance','super_admin'])));

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION is_maintenance_exec()
RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec', 'super_admin')
  )
$$;

CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'super_admin'
  )
$$;

CREATE OR REPLACE FUNCTION check_pan_exists(p_pan text)
RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (
    SELECT 1 FROM suppliers WHERE upper(trim(pan_number)) = upper(trim(p_pan))
  );
$$;

-- Add n_days business days to start_date, skipping weekends and holidays.
-- Weekly offs configured in system_settings key 'sla_weekly_offs' (JSONB int array, 0=Sun..6=Sat).
CREATE OR REPLACE FUNCTION add_working_days(start_date date, n_days integer)
RETURNS date LANGUAGE plpgsql AS $$
DECLARE
  current_d   DATE := start_date;
  days_added  INT  := 0;
  weekly_offs JSONB;
  dow         INT;
  is_holiday  BOOLEAN;
BEGIN
  SELECT value::jsonb INTO weekly_offs FROM system_settings WHERE key = 'sla_weekly_offs';
  IF weekly_offs IS NULL THEN weekly_offs := '[0,6]'::jsonb; END IF;
  WHILE days_added < n_days LOOP
    current_d := current_d + 1;
    dow := EXTRACT(DOW FROM current_d)::INT;
    IF weekly_offs @> to_jsonb(dow) THEN CONTINUE; END IF;
    SELECT EXISTS (SELECT 1 FROM holidays WHERE date = current_d) INTO is_holiday;
    IF is_holiday THEN CONTINUE; END IF;
    days_added := days_added + 1;
  END LOOP;
  RETURN current_d;
END;
$$;

-- Evaluate whether acceptance SLA was adhered for a ticket.
CREATE OR REPLACE FUNCTION evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamptz)
RETURNS sla_status_enum LANGUAGE plpgsql AS $$
DECLARE
  v_created_at DATE;
  v_sla_days   INT;
  v_deadline   DATE;
BEGIN
  SELECT created_at::date INTO v_created_at FROM tickets WHERE id = p_ticket_id;
  SELECT value::INT INTO v_sla_days FROM system_settings WHERE key = 'acceptance_sla_days';
  IF v_sla_days IS NULL THEN v_sla_days := 2; END IF;
  v_deadline := add_working_days(v_created_at, v_sla_days);
  IF p_first_issue_created::date <= v_deadline THEN
    RETURN 'Adhered'::sla_status_enum;
  ELSE
    RETURN 'Violated'::sla_status_enum;
  END IF;
END;
$$;

-- Legacy SLA calculator (not used by active triggers; kept for reference).
CREATE OR REPLACE FUNCTION calculate_sla_days(p_impact text, p_category text)
RETURNS integer LANGUAGE plpgsql AS $$
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
$$;

-- ============================================================================
-- TRIGGER FUNCTIONS
-- ============================================================================

-- Auto-generate issue number (e.g. T-1434-01) on issue INSERT.
CREATE OR REPLACE FUNCTION generate_issue_number()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  ticket_num  INTEGER;
  issue_count INTEGER;
BEGIN
  SELECT COALESCE(ticket_number, 0) INTO ticket_num FROM tickets WHERE id = NEW.ticket_id;
  SELECT COUNT(*) + 1 INTO issue_count FROM issues WHERE ticket_id = NEW.ticket_id;
  NEW.issue_number := 'T-' || ticket_num || '-' || LPAD(issue_count::text, 2, '0');
  RETURN NEW;
END;
$$;

-- Calculate issue SLA from sla_rules_config on INSERT or category/severity change.
CREATE OR REPLACE FUNCTION calculate_issue_sla_dynamic()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  rule_days INTEGER;
BEGIN
  IF TG_OP = 'INSERT'
     OR (TG_OP = 'UPDATE' AND (
         NEW.category IS DISTINCT FROM OLD.category OR
         NEW.severity IS DISTINCT FROM OLD.severity
     ))
  THEN
    SELECT sla_days INTO rule_days FROM sla_rules_config
    WHERE category = NEW.category AND severity = NEW.severity;
    IF rule_days IS NULL THEN rule_days := 3; END IF;
    NEW.sla_days     := rule_days;
    NEW.sla_end_date := DATE(NEW.created_at) + rule_days;
  END IF;
  RETURN NEW;
END;
$$;

-- Update tickets.final_sla_end_date and overall_sla_status after issue SLA changes.
CREATE OR REPLACE FUNCTION calculate_ticket_overall_sla()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_final_sla   DATE;
  v_status      TEXT;
  v_resolved_at DATE;
BEGIN
  UPDATE tickets
  SET final_sla_end_date = (SELECT MAX(sla_end_date) FROM issues WHERE ticket_id = NEW.ticket_id)
  WHERE id = NEW.ticket_id
  RETURNING final_sla_end_date, status::text, COALESCE(resolved_at::date, closed_at::date)
  INTO v_final_sla, v_status, v_resolved_at;

  UPDATE tickets
  SET overall_sla_status = CASE
    WHEN v_final_sla IS NULL THEN 'Pending'::sla_status_enum
    WHEN v_status IN ('Resolved','Closed') AND v_final_sla >= COALESCE(v_resolved_at, CURRENT_DATE) THEN 'Adhered'::sla_status_enum
    WHEN v_status IN ('Resolved','Closed') THEN 'Violated'::sla_status_enum
    WHEN v_final_sla < CURRENT_DATE THEN 'Violated'::sla_status_enum
    ELSE 'Pending'::sla_status_enum
  END
  WHERE id = NEW.ticket_id;

  RETURN NEW;
END;
$$;

-- Advance ticket status automatically based on issue state.
-- New → Accepted (first issue created)
-- Accepted → Work In Progress (first job card assigned)
-- Work In Progress → Resolved (all issues Done)
-- Resolved → Closed (all issues rated)
CREATE OR REPLACE FUNCTION update_ticket_status_on_issue_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  ticket_status TEXT;
  total_issues  INTEGER;
  done_issues   INTEGER;
  rated_issues  INTEGER;
  has_job_cards BOOLEAN;
BEGIN
  SELECT status INTO ticket_status FROM tickets WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  SELECT COUNT(*),
         COUNT(*) FILTER (WHERE status = 'Done'),
         COUNT(*) FILTER (WHERE rating IS NOT NULL)
  INTO total_issues, done_issues, rated_issues
  FROM issues WHERE ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  SELECT EXISTS(SELECT 1 FROM issues i WHERE i.ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id) AND i.job_card_id IS NOT NULL) INTO has_job_cards;

  IF ticket_status = 'New' AND total_issues > 0 AND TG_OP = 'INSERT' THEN
    UPDATE tickets SET status = 'Accepted' WHERE id = NEW.ticket_id;
  END IF;
  IF ticket_status = 'Accepted' AND has_job_cards THEN
    UPDATE tickets SET status = 'Work In Progress' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  IF ticket_status = 'Work In Progress' AND total_issues > 0 AND done_issues = total_issues THEN
    UPDATE tickets SET status = 'Resolved' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  IF ticket_status = 'Resolved' AND total_issues > 0 AND rated_issues = total_issues THEN
    UPDATE tickets SET status = 'Closed' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Stamp acceptance_sla_status when the first issue is created on a ticket.
CREATE OR REPLACE FUNCTION trg_set_acceptance_sla_on_first_issue()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_prior_count INT;
BEGIN
  SELECT COUNT(*) INTO v_prior_count FROM issues WHERE ticket_id = NEW.ticket_id AND id != NEW.id;
  IF v_prior_count = 0 THEN
    UPDATE tickets SET acceptance_sla_status = evaluate_acceptance_sla(NEW.ticket_id, NEW.created_at)
    WHERE id = NEW.ticket_id;
  END IF;
  RETURN NEW;
END;
$$;

-- Recalculate overall_sla_status when ticket status changes (Resolved/Closed).
-- IMPORTANT: fires on UPDATE OF status only to prevent infinite recursion
-- (the function itself does UPDATE tickets SET overall_sla_status which would re-fire
-- an unrestricted trigger indefinitely).
CREATE OR REPLACE FUNCTION recalculate_ticket_sla_on_status_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_final_sla   DATE;
  v_resolved_at DATE;
BEGIN
  SELECT final_sla_end_date, COALESCE(resolved_at::date, closed_at::date)
  INTO v_final_sla, v_resolved_at
  FROM tickets WHERE id = NEW.id;

  UPDATE tickets
  SET overall_sla_status = CASE
    WHEN v_final_sla IS NULL THEN 'Pending'::sla_status_enum
    WHEN NEW.status::text IN ('Resolved','Closed') AND v_final_sla >= COALESCE(v_resolved_at, CURRENT_DATE) THEN 'Adhered'::sla_status_enum
    WHEN NEW.status::text IN ('Resolved','Closed') THEN 'Violated'::sla_status_enum
    WHEN v_final_sla < CURRENT_DATE THEN 'Violated'::sla_status_enum
    ELSE 'Pending'::sla_status_enum
  END
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- Stamp rejected_at and evaluate acceptance SLA when ticket is rejected.
CREATE OR REPLACE FUNCTION stamp_rejected_at_and_evaluate_acceptance_sla()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_sla_days    INT;
  v_deadline    DATE;
  v_first_issue TIMESTAMPTZ;
BEGIN
  IF NEW.status = 'Rejected' AND (OLD.status IS DISTINCT FROM 'Rejected') THEN
    NEW.rejected_at := NOW();
    IF NEW.acceptance_sla_status = 'Pending' THEN
      SELECT COALESCE(value::int, 2) INTO v_sla_days FROM system_settings WHERE key = 'acceptance_sla_days';
      v_deadline := add_working_days(NEW.created_at::date, COALESCE(v_sla_days, 2));
      SELECT MIN(created_at) INTO v_first_issue FROM issues WHERE ticket_id = NEW.id;
      IF v_first_issue IS NOT NULL THEN
        NEW.acceptance_sla_status := CASE WHEN v_first_issue::date <= v_deadline THEN 'Adhered' ELSE 'Violated' END;
      ELSE
        NEW.acceptance_sla_status := CASE WHEN NOW()::date <= v_deadline THEN 'Adhered' ELSE 'Violated' END;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Parts inventory: add stock on purchase invoice item INSERT.
CREATE OR REPLACE FUNCTION add_part_to_inventory()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE parts SET quantity_in_stock = quantity_in_stock + NEW.quantity WHERE id = NEW.part_id;
  RETURN NEW;
END;
$$;

-- Parts inventory: adjust stock when purchase invoice item is updated.
CREATE OR REPLACE FUNCTION adjust_part_inventory_on_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.part_id = OLD.part_id THEN
    UPDATE parts SET quantity_in_stock = quantity_in_stock + (NEW.quantity - OLD.quantity) WHERE id = NEW.part_id;
  ELSE
    UPDATE parts SET quantity_in_stock = quantity_in_stock - OLD.quantity WHERE id = OLD.part_id;
    UPDATE parts SET quantity_in_stock = quantity_in_stock + NEW.quantity WHERE id = NEW.part_id;
  END IF;
  RETURN NEW;
END;
$$;

-- Parts inventory: reverse stock on purchase invoice item DELETE.
CREATE OR REPLACE FUNCTION reverse_part_inventory_on_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE parts SET quantity_in_stock = quantity_in_stock - OLD.quantity WHERE id = OLD.part_id;
  RETURN OLD;
END;
$$;

-- Parts inventory: deduct stock when a part is used on an issue.
CREATE OR REPLACE FUNCTION deduct_part_from_inventory()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE parts SET quantity_in_stock = quantity_in_stock - NEW.quantity_used WHERE id = NEW.part_id;
  RETURN NEW;
END;
$$;

-- Parts inventory: restore stock when an issue_part row is deleted.
CREATE OR REPLACE FUNCTION restore_part_to_inventory()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE parts SET quantity_in_stock = quantity_in_stock + OLD.quantity_used WHERE id = OLD.part_id;
  RETURN OLD;
END;
$$;

-- Legacy ticket SLA function (kept; trigger was dropped during refactor).
CREATE OR REPLACE FUNCTION update_ticket_sla()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.impact IS NOT NULL AND NEW.category IS NOT NULL THEN
    NEW.sla_days     := calculate_sla_days(NEW.impact, NEW.category);
    NEW.sla_end_date := NEW.created_at::DATE + NEW.sla_days;
  END IF;
  RETURN NEW;
END;
$$;

-- Analytics RPC function (called from Analytics page).
CREATE OR REPLACE FUNCTION get_maintenance_stats(
  start_date_input date DEFAULT NULL,
  end_date_input   date DEFAULT NULL,
  site_filter      text DEFAULT NULL
)
RETURNS TABLE(
  total_tickets bigint, status_new bigint, status_pending bigint, status_accepted bigint,
  status_wip bigint, status_resolved bigint, status_closed bigint, status_rejected bigint,
  status_completed bigint, major_total bigint, major_electrical bigint, major_mechanical bigint,
  major_body bigint, major_tyre bigint, minor_total bigint, minor_electrical bigint,
  minor_mechanical bigint, minor_body bigint, minor_tyre bigint, type_in_house bigint,
  type_outsource bigint, accept_pending bigint, accept_adhered bigint, accept_violated bigint,
  comp_in_wip_within bigint, comp_in_adhered bigint, comp_in_violated bigint,
  comp_out_wip_within bigint, comp_out_adhered bigint, comp_out_violated bigint,
  rating_pending bigint, rating_collected bigint, rating_good bigint, rating_ok bigint,
  rating_bad bigint, csat_score_sum bigint, total_completed_tickets bigint
)
LANGUAGE plpgsql AS $$
DECLARE
  v_sla_days INT;
BEGIN
  SELECT COALESCE(value::int, 2) INTO v_sla_days FROM system_settings WHERE key = 'acceptance_sla_days';
  RETURN QUERY
  WITH ticket_data AS (
    SELECT t.id, t.status, t.created_at, t.resolved_at, t.closed_at,
           t.final_sla_end_date, t.overall_sla_status, t.acceptance_sla_status,
           CASE WHEN t.overall_sla_status IN ('Adhered','Violated') THEN t.overall_sla_status
                WHEN t.final_sla_end_date IS NOT NULL AND CURRENT_DATE > t.final_sla_end_date::date THEN 'Violated'
                ELSE 'Pending' END AS eff_overall,
           CASE WHEN t.acceptance_sla_status IN ('Adhered','Violated') THEN t.acceptance_sla_status
                WHEN NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id)
                     AND CURRENT_DATE > add_working_days(t.created_at::date, v_sla_days) THEN 'Violated'
                ELSE 'Pending' END AS eff_accept,
           CASE WHEN EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id AND i.work_type = 'Outsource')
                 AND NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id AND i.work_type = 'InHouse')
                THEN 'Outsource' ELSE 'InHouse' END AS dominant_work_type
    FROM tickets t
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter       IS NULL OR t.site = site_filter)
  ),
  issue_data AS (
    SELECT i.* FROM issues i JOIN tickets t ON i.ticket_id = t.id
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter       IS NULL OR t.site = site_filter)
  )
  SELECT
    COUNT(*)::BIGINT,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT,
    COUNT(*) FILTER (WHERE td.status = 'Accepted')::BIGINT,
    COUNT(*) FILTER (WHERE td.status = 'Work In Progress')::BIGINT,
    COUNT(*) FILTER (WHERE td.status = 'Resolved')::BIGINT,
    COUNT(*) FILTER (WHERE td.status = 'Closed')::BIGINT,
    COUNT(*) FILTER (WHERE td.status = 'Rejected')::BIGINT,
    COUNT(*) FILTER (WHERE td.status IN ('Resolved','Closed'))::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Electrical')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Mechanical')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Body')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Tyre')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Electrical')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Mechanical')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Body')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Tyre')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE work_type = 'InHouse')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE work_type = 'Outsource')::BIGINT,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Pending')::BIGINT,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Adhered')::BIGINT,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Violated')::BIGINT,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Pending'  AND td.dominant_work_type = 'InHouse')::BIGINT,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Adhered'  AND td.dominant_work_type = 'InHouse')::BIGINT,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Violated' AND td.dominant_work_type = 'InHouse')::BIGINT,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Pending'  AND td.dominant_work_type = 'Outsource')::BIGINT,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Adhered'  AND td.dominant_work_type = 'Outsource')::BIGINT,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Violated' AND td.dominant_work_type = 'Outsource')::BIGINT,
    (SELECT COUNT(*) FROM issue_data JOIN ticket_data td2 ON td2.id = issue_data.ticket_id WHERE issue_data.rating IS NULL AND td2.status IN ('Resolved','Closed'))::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE rating IS NOT NULL)::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Good')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Ok')::BIGINT,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Bad')::BIGINT,
    (SELECT COALESCE(SUM(CASE WHEN rating = 'Good' THEN 2 WHEN rating = 'Ok' THEN 1 ELSE 0 END), 0) FROM issue_data WHERE rating IS NOT NULL)::BIGINT,
    COUNT(*) FILTER (WHERE td.status IN ('Resolved','Closed'))::BIGINT
  FROM ticket_data td;
END;
$$;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- issues
CREATE TRIGGER trg_generate_issue_number
  BEFORE INSERT ON issues FOR EACH ROW
  WHEN (NEW.issue_number IS NULL)
  EXECUTE FUNCTION generate_issue_number();

CREATE TRIGGER trg_issue_sla_dynamic
  BEFORE INSERT OR UPDATE ON issues FOR EACH ROW
  EXECUTE FUNCTION calculate_issue_sla_dynamic();

CREATE TRIGGER trg_acceptance_sla_on_first_issue
  AFTER INSERT ON issues FOR EACH ROW
  EXECUTE FUNCTION trg_set_acceptance_sla_on_first_issue();

CREATE TRIGGER trg_update_ticket_sla_agg
  AFTER INSERT OR UPDATE OF sla_end_date, status, category, severity ON issues FOR EACH ROW
  EXECUTE FUNCTION calculate_ticket_overall_sla();

CREATE TRIGGER trigger_update_ticket_status
  AFTER INSERT OR UPDATE ON issues FOR EACH ROW
  EXECUTE FUNCTION update_ticket_status_on_issue_change();

-- issue_parts
CREATE TRIGGER trigger_deduct_part_inventory
  AFTER INSERT ON issue_parts FOR EACH ROW
  EXECUTE FUNCTION deduct_part_from_inventory();

CREATE TRIGGER trigger_restore_part_inventory
  AFTER DELETE ON issue_parts FOR EACH ROW
  EXECUTE FUNCTION restore_part_to_inventory();

-- purchase_invoice_items
CREATE TRIGGER trigger_add_part_inventory
  AFTER INSERT ON purchase_invoice_items FOR EACH ROW
  EXECUTE FUNCTION add_part_to_inventory();

CREATE TRIGGER trigger_adjust_part_inventory_on_update
  AFTER UPDATE ON purchase_invoice_items FOR EACH ROW
  EXECUTE FUNCTION adjust_part_inventory_on_update();

CREATE TRIGGER trigger_reverse_part_inventory_on_delete
  AFTER DELETE ON purchase_invoice_items FOR EACH ROW
  EXECUTE FUNCTION reverse_part_inventory_on_delete();

-- tickets
CREATE TRIGGER trg_stamp_rejected_at_and_acceptance_sla
  BEFORE UPDATE ON tickets FOR EACH ROW
  EXECUTE FUNCTION stamp_rejected_at_and_evaluate_acceptance_sla();

-- IMPORTANT: restricted to UPDATE OF status to prevent infinite recursion.
-- recalculate_ticket_sla_on_status_change() updates tickets.overall_sla_status;
-- if the trigger fired on ALL updates it would recurse indefinitely.
CREATE TRIGGER trg_ticket_sla_on_status_change
  AFTER UPDATE OF status ON tickets FOR EACH ROW
  EXECUTE FUNCTION recalculate_ticket_sla_on_status_change();

-- ============================================================================
-- SCHEDULED JOBS (pg_cron)
-- ============================================================================
-- Nightly Roorides vehicle sync — fires at 00:00 UTC daily.
-- Calls the sync-roorides-vehicles edge function via net.http_post.
-- Configured in migration: 20260419000000_schedule_roorides_vehicle_sync.sql
-- ============================================================================
