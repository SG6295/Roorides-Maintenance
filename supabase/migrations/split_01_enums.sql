-- Part 1: Cleanup, Enums, and SLA Config

BEGIN;

-- 1. Cleanup old views (Dependencies)
DROP VIEW IF EXISTS supervisor_dashboard_stats;
DROP VIEW IF EXISTS maintenance_dashboard_stats;

-- 2. Create Enums (Idempotent)
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

-- 3. SLA Config Table
CREATE TABLE IF NOT EXISTS sla_rules_config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category issue_category NOT NULL,
    severity issue_severity NOT NULL,
    sla_days INTEGER NOT NULL,
    UNIQUE(category, severity)
);

-- Seed SLA Rules
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

COMMIT;
