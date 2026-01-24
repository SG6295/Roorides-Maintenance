-- Part 3a: Add New Columns & Basic Updates

BEGIN;

-- 1. Add New Columns
ALTER TABLE tickets 
    ADD COLUMN IF NOT EXISTS initial_remarks TEXT,
    ADD COLUMN IF NOT EXISTS rejected_reason TEXT,
    ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS closed_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS final_sla_end_date DATE,
    ADD COLUMN IF NOT EXISTS overall_sla_status sla_status_enum;

-- 2. Add Restrictions
ALTER TABLE tickets ADD CONSTRAINT check_resolved_after_created
    CHECK (resolved_at IS NULL OR resolved_at >= created_at);
    
ALTER TABLE tickets ADD CONSTRAINT check_closed_after_resolved
    CHECK (closed_at IS NULL OR resolved_at IS NULL OR closed_at >= resolved_at);

-- 3. Data Migration (Complaint -> Initial Remarks)
UPDATE tickets SET initial_remarks = complaint WHERE initial_remarks IS NULL AND complaint IS NOT NULL;

COMMIT;
