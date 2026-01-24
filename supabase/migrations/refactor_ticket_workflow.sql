-- Migration: Refactor Ticket Workflow (Robust Version v4 - Text Casting)

BEGIN;

-- ============================================================================
-- 0. PRE-MIGRATION CLEANUP
-- ============================================================================
DROP VIEW IF EXISTS supervisor_dashboard_stats;
DROP VIEW IF EXISTS maintenance_dashboard_stats;

-- ============================================================================
-- 1. CREATE ENUMS
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'issue_category') THEN
        CREATE TYPE issue_category AS ENUM ('Mechanical', 'Electrical', 'Body', 'Tyre', 'GPS', 'AdBlue', 'Other');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'issue_severity') THEN
        CREATE TYPE issue_severity AS ENUM ('Minor', 'Major');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'work_type_enum') THEN
        CREATE TYPE work_type_enum AS ENUM ('InHouse', 'Outsource');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'issue_status') THEN
        CREATE TYPE issue_status AS ENUM ('Open', 'Done');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_card_status') THEN
        CREATE TYPE job_card_status AS ENUM ('Open', 'Completed');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'ticket_status_new') THEN
        CREATE TYPE ticket_status_new AS ENUM ('Pending', 'Accepted', 'Rejected', 'Work in Progress', 'Resolved', 'Closed');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sla_status_enum') THEN
        CREATE TYPE sla_status_enum AS ENUM ('Pending', 'Adhered', 'Violated');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'rating_enum') THEN
        CREATE TYPE rating_enum AS ENUM ('Good', 'Ok', 'Bad');
    END IF;
END $$;

-- ============================================================================
-- 2. SLA CONFIGURATION
-- ============================================================================
CREATE TABLE IF NOT EXISTS sla_rules_config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category issue_category NOT NULL,
    severity issue_severity NOT NULL,
    sla_days INTEGER NOT NULL,
    UNIQUE(category, severity)
);

INSERT INTO sla_rules_config (category, severity, sla_days) VALUES
('Electrical', 'Major', 7),
('Mechanical', 'Major', 15),
('Body', 'Major', 30),
('Tyre', 'Major', 15),
('GPS', 'Major', 3),
('AdBlue', 'Major', 3),
('Other', 'Major', 7),
('Electrical', 'Minor', 3),
('Mechanical', 'Minor', 3),
('Body', 'Minor', 3),
('Tyre', 'Minor', 3),
('GPS', 'Minor', 3),
('AdBlue', 'Minor', 3),
('Other', 'Minor', 3)
ON CONFLICT (category, severity) DO UPDATE SET sla_days = EXCLUDED.sla_days;

-- ============================================================================
-- 3. CREATE NEW TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS job_cards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_card_number INTEGER GENERATED ALWAYS AS IDENTITY,
    created_at TIMESTAMP DEFAULT NOW(),
    
    type work_type_enum NOT NULL,
    
    assigned_mechanic_id UUID REFERENCES users(id),
    vendor_name TEXT,
    
    vehicle_number TEXT NOT NULL,
    site TEXT NOT NULL,
    
    status job_card_status DEFAULT 'Open',
    completed_at TIMESTAMP,
    remarks TEXT,
    
    CONSTRAINT check_assignment_strict CHECK (
        (type = 'InHouse'::work_type_enum AND assigned_mechanic_id IS NOT NULL AND vendor_name IS NULL) OR 
        (type = 'Outsource'::work_type_enum AND vendor_name IS NOT NULL AND assigned_mechanic_id IS NULL)
    ),
    CONSTRAINT check_completed_after_created CHECK (completed_at IS NULL OR completed_at >= created_at)
);

CREATE TABLE IF NOT EXISTS issues (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    issue_number TEXT, 
    created_at TIMESTAMP DEFAULT NOW(),
    
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    job_card_id UUID REFERENCES job_cards(id) ON DELETE SET NULL,
    
    description TEXT NOT NULL,
    category issue_category NOT NULL,
    severity issue_severity DEFAULT 'Minor',
    work_type work_type_enum,
    
    status issue_status DEFAULT 'Open',
    
    sla_days INTEGER,
    sla_end_date DATE,
    sla_status sla_status_enum DEFAULT 'Pending',
    
    rating rating_enum,
    rating_remarks TEXT,
    rated_at TIMESTAMP,

    CONSTRAINT check_rated_at_after_created CHECK (rated_at IS NULL OR rated_at >= created_at)
);

-- ============================================================================
-- 4. MODIFY TICKETS TABLE
-- ============================================================================
ALTER TABLE tickets 
    ADD COLUMN IF NOT EXISTS initial_remarks TEXT,
    ADD COLUMN IF NOT EXISTS rejected_reason TEXT,
    ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS closed_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS final_sla_end_date DATE,
    ADD COLUMN IF NOT EXISTS overall_sla_status sla_status_enum;

ALTER TABLE tickets ADD CONSTRAINT check_resolved_after_created
    CHECK (resolved_at IS NULL OR resolved_at >= created_at);
    
ALTER TABLE tickets ADD CONSTRAINT check_closed_after_resolved
    CHECK (closed_at IS NULL OR resolved_at IS NULL OR closed_at >= resolved_at);

-- Convert Status with TEXT casting logic
ALTER TABLE tickets 
    ALTER COLUMN status DROP DEFAULT,
    ALTER COLUMN status TYPE ticket_status_new USING 
        CASE 
            WHEN status::text = 'Completed' THEN 'Resolved'::ticket_status_new
            WHEN status::text = 'Pending' THEN 'Pending'::ticket_status_new
            WHEN status::text = 'Team Assigned' THEN 'Accepted'::ticket_status_new
            WHEN status::text = 'Rejected' THEN 'Rejected'::ticket_status_new
            WHEN status::text = 'Work in Progress' THEN 'Work in Progress'::ticket_status_new
            ELSE 'Pending'::ticket_status_new 
        END,
    ALTER COLUMN status SET DEFAULT 'Pending'::ticket_status_new;

-- ============================================================================
-- 5. DATA MIGRATION
-- ============================================================================
UPDATE tickets SET initial_remarks = complaint WHERE initial_remarks IS NULL AND complaint IS NOT NULL;

-- Migrate Tickets -> Issues
INSERT INTO issues (ticket_id, description, category, severity, status, created_at, sla_end_date)
SELECT 
    id, 
    complaint, 
    CASE 
        WHEN category::text ILIKE '%electrical%' THEN 'Electrical'::issue_category
        WHEN category::text ILIKE '%mechanical%' THEN 'Mechanical'::issue_category
        WHEN category::text ILIKE '%body%' THEN 'Body'::issue_category
        WHEN category::text ILIKE '%tyre%' THEN 'Tyre'::issue_category
        WHEN category::text ILIKE '%gps%' THEN 'GPS'::issue_category
        WHEN category::text ILIKE '%adblue%' THEN 'AdBlue'::issue_category
        ELSE 'Other'::issue_category
    END,
    CASE 
        WHEN impact::text ILIKE 'Major' THEN 'Major'::issue_severity
        ELSE 'Minor'::issue_severity
    END,
    -- Comparision using text casting
    CASE 
        WHEN status::text = 'Resolved' OR status::text = 'Closed' THEN 'Done'::issue_status 
        ELSE 'Open'::issue_status 
    END,
    created_at,
    sla_end_date
FROM tickets
WHERE NOT EXISTS (SELECT 1 FROM issues WHERE issues.ticket_id = tickets.id);

-- ============================================================================
-- 6. DROP OLD COLUMNS
-- ============================================================================
ALTER TABLE tickets
    DROP COLUMN IF EXISTS category,
    DROP COLUMN IF EXISTS complaint,
    DROP COLUMN IF EXISTS remarks,
    DROP COLUMN IF EXISTS impact,
    DROP COLUMN IF EXISTS job_sheet_id,
    DROP COLUMN IF EXISTS assigned_mechanic_id,
    DROP COLUMN IF EXISTS assigned_date,
    DROP COLUMN IF EXISTS activity_plan_date,
    DROP COLUMN IF EXISTS work_type,
    DROP COLUMN IF EXISTS completed_date,
    DROP COLUMN IF EXISTS completion_remarks,
    DROP COLUMN IF EXISTS sla_days,
    DROP COLUMN IF EXISTS sla_end_date,
    DROP COLUMN IF EXISTS assignment_sla_status,
    DROP COLUMN IF EXISTS completion_sla_status,
    DROP COLUMN IF EXISTS rating,
    DROP COLUMN IF EXISTS csat_score;

-- ============================================================================
-- 7. TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_issue_sla_dynamic() RETURNS TRIGGER AS $$
DECLARE
    rule_days INTEGER;
BEGIN
    IF NEW.sla_days IS NULL OR NEW.sla_end_date IS NULL THEN
        SELECT sla_days INTO rule_days
        FROM sla_rules_config
        WHERE category = NEW.category AND severity = NEW.severity;
        
        IF rule_days IS NULL THEN rule_days := 3; END IF;

        NEW.sla_days := rule_days;
        NEW.sla_end_date := DATE(NEW.created_at) + rule_days;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_issue_sla_dynamic ON issues;
CREATE TRIGGER trg_issue_sla_dynamic
BEFORE INSERT ON issues
FOR EACH ROW EXECUTE FUNCTION calculate_issue_sla_dynamic();

CREATE OR REPLACE FUNCTION generate_issue_number() RETURNS TRIGGER AS $$
DECLARE
    ticket_num INTEGER;
    issue_count INTEGER;
BEGIN
    SELECT COALESCE(ticket_number, 0) INTO ticket_num FROM tickets WHERE id = NEW.ticket_id;
    SELECT COUNT(*) + 1 INTO issue_count FROM issues WHERE ticket_id = NEW.ticket_id;
    NEW.issue_number := 'T-' || ticket_num || '-' || LPAD(issue_count::text, 2, '0');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_generate_issue_number ON issues;
CREATE TRIGGER trg_generate_issue_number
BEFORE INSERT ON issues
FOR EACH ROW
WHEN (NEW.issue_number IS NULL)
EXECUTE FUNCTION generate_issue_number();

CREATE OR REPLACE FUNCTION calculate_ticket_overall_sla() RETURNS TRIGGER AS $$
BEGIN
    UPDATE tickets
    SET final_sla_end_date = (
        SELECT MAX(sla_end_date) FROM issues WHERE ticket_id = NEW.ticket_id
    )
    WHERE id = NEW.ticket_id;

    -- Update overall_sla_status using TEXT comparisons
    UPDATE tickets 
    SET overall_sla_status = 
        CASE 
            WHEN final_sla_end_date < CURRENT_DATE AND status::text NOT IN ('Resolved', 'Closed') 
                THEN 'Violated'::sla_status_enum
            WHEN status::text IN ('Resolved', 'Closed') AND final_sla_end_date >= resolved_at::date
                THEN 'Adhered'::sla_status_enum
            ELSE 'Pending'::sla_status_enum
        END
    WHERE id = NEW.ticket_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_ticket_sla_agg ON issues;
CREATE TRIGGER trg_update_ticket_sla_agg
AFTER INSERT OR UPDATE OF sla_end_date, status ON issues
FOR EACH ROW EXECUTE FUNCTION calculate_ticket_overall_sla();

-- ============================================================================
-- 8. INDEXES & RLS
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_issues_ticket_id ON issues(ticket_id);
CREATE INDEX IF NOT EXISTS idx_issues_job_card_id ON issues(job_card_id);
CREATE INDEX IF NOT EXISTS idx_issues_status ON issues(status);
CREATE INDEX IF NOT EXISTS idx_job_cards_status ON job_cards(status);
CREATE INDEX IF NOT EXISTS idx_job_cards_mechanic ON job_cards(assigned_mechanic_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status_new ON tickets(status);
CREATE INDEX IF NOT EXISTS idx_tickets_site_new ON tickets(site);

ALTER TABLE issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_cards ENABLE ROW LEVEL SECURITY;

-- Re-applying logic with IF NOT EXISTS logic handled manually by Supabase usually, but we use safe names
DROP POLICY IF EXISTS "Supervisors view site issues" ON issues;
CREATE POLICY "Supervisors view site issues" ON issues 
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM tickets t
            JOIN users u ON u.id = auth.uid()
            WHERE t.id = issues.ticket_id AND u.role = 'supervisor' AND u.site = t.site
        )
    );

DROP POLICY IF EXISTS "Supervisors create issues" ON issues;
CREATE POLICY "Supervisors create issues" ON issues 
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM tickets t
            JOIN users u ON u.id = auth.uid()
            WHERE t.id = issues.ticket_id AND u.role = 'supervisor'
        )
    );

DROP POLICY IF EXISTS "Supervisors update own ratings" ON issues;
CREATE POLICY "Supervisors update own ratings" ON issues
    FOR UPDATE USING (
         EXISTS (
            SELECT 1 FROM tickets t
            JOIN users u ON u.id = auth.uid()
            WHERE t.id = issues.ticket_id AND u.role = 'supervisor' AND u.site = t.site
        )
    );

DROP POLICY IF EXISTS "Mechanics view assigned cards" ON job_cards;
CREATE POLICY "Mechanics view assigned cards" ON job_cards
    FOR SELECT USING (
        assigned_mechanic_id = auth.uid() OR
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'maintenance_exec')
    );
    
DROP POLICY IF EXISTS "Mechanics update assigned cards" ON job_cards;
CREATE POLICY "Mechanics update assigned cards" ON job_cards
    FOR UPDATE USING (assigned_mechanic_id = auth.uid());

DROP POLICY IF EXISTS "Execs manage issues" ON issues;
CREATE POLICY "Execs manage issues" ON issues FOR ALL
    USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'maintenance_exec'));

DROP POLICY IF EXISTS "Execs manage job cards" ON job_cards;
CREATE POLICY "Execs manage job cards" ON job_cards FOR ALL
    USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'maintenance_exec'));

-- ============================================================================
-- 9. RECREATE VIEWS (Text Comparison)
-- ============================================================================

CREATE OR REPLACE VIEW supervisor_dashboard_stats AS
SELECT
  t.site,
  COUNT(*) FILTER (WHERE t.status::text = 'Pending') as pending_count,
  COUNT(*) FILTER (WHERE t.status::text = 'Accepted') as accepted_count,
  COUNT(*) FILTER (WHERE t.status::text = 'Resolved') as completed_count,
  COUNT(*) FILTER (WHERE t.status::text = 'Rejected') as rejected_count,
  COUNT(*) FILTER (WHERE t.overall_sla_status::text = 'Violated') as sla_violated_count,
  COALESCE(AVG(
    CASE 
        WHEN i.rating::text = 'Good' THEN 2
        WHEN i.rating::text = 'Ok' THEN 1  
        WHEN i.rating::text = 'Bad' THEN 0
    END
  ), 0) as avg_csat_score
FROM tickets t
LEFT JOIN issues i ON i.ticket_id = t.id
GROUP BY t.site;

CREATE OR REPLACE VIEW maintenance_dashboard_stats AS
SELECT
  COUNT(*) as total_tickets,
  COUNT(*) FILTER (WHERE status::text = 'Pending') as pending_tickets,
  COUNT(*) FILTER (WHERE overall_sla_status::text = 'Violated') as completion_sla_violated,
  (SELECT COUNT(*) FROM job_cards WHERE type::text = 'InHouse') as inhouse_count,
  (SELECT COUNT(*) FROM job_cards WHERE type::text = 'Outsource') as outsource_count,
  COALESCE(AVG(EXTRACT(DAY FROM (CASE WHEN status::text = 'Resolved' THEN resolved_at ELSE NOW() END - created_at))), 0) as avg_tat_days
FROM tickets;

COMMIT;
