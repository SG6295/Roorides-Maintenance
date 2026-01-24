-- Part 3: Tickets Modification & Data Migration

BEGIN;

-- 1. Add New Columns
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

-- 2. Convert Status Enum (Using Text Casting)
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

-- 3. Data Migration (Complaint -> Initial Remarks)
UPDATE tickets SET initial_remarks = complaint WHERE initial_remarks IS NULL AND complaint IS NOT NULL;

-- 4. Migrate Tickets -> Issues
INSERT INTO issues (ticket_id, description, category, severity, status, created_at, sla_end_date)
SELECT 
    id, 
    complaint, 
    -- Category Mapping
    CASE 
        WHEN category::text ILIKE '%electrical%' THEN 'Electrical'::issue_category
        WHEN category::text ILIKE '%mechanical%' THEN 'Mechanical'::issue_category
        WHEN category::text ILIKE '%body%' THEN 'Body'::issue_category
        WHEN category::text ILIKE '%tyre%' THEN 'Tyre'::issue_category
        WHEN category::text ILIKE '%gps%' THEN 'GPS'::issue_category
        WHEN category::text ILIKE '%adblue%' THEN 'AdBlue'::issue_category
        ELSE 'Other'::issue_category
    END,
    -- Severity Mapping
    CASE 
        WHEN impact::text ILIKE 'Major' THEN 'Major'::issue_severity
        ELSE 'Minor'::issue_severity
    END,
    -- Status Mapping
    CASE 
        WHEN status::text = 'Resolved' OR status::text = 'Closed' THEN 'Done'::issue_status 
        ELSE 'Open'::issue_status 
    END,
    created_at,
    sla_end_date
FROM tickets
WHERE NOT EXISTS (SELECT 1 FROM issues WHERE issues.ticket_id = tickets.id);

-- 5. Drop Old Columns
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

COMMIT;
