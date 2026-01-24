-- Part 3d: Drop Old Columns

BEGIN;

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
