-- Part 3c: Alter Status Column (Safe Text Intermediate Step)

BEGIN;

-- 1. Drop Default
ALTER TABLE tickets ALTER COLUMN status DROP DEFAULT;

-- 2. Drop any constraints on status (if they exist, usually named tickets_status_check)
DO $$ BEGIN
    ALTER TABLE tickets DROP CONSTRAINT IF EXISTS tickets_status_check;
EXCEPTION
    WHEN undefined_object THEN null;
END $$;

-- 3. Convert to TEXT (Universal format)
ALTER TABLE tickets ALTER COLUMN status TYPE TEXT;

-- 4. Update Values (Map to new Enum values)
UPDATE tickets 
SET status = CASE 
    WHEN status = 'Completed' THEN 'Resolved'
    WHEN status = 'Team Assigned' THEN 'Accepted'
    WHEN status = 'Work in Progress' THEN 'Work in Progress'
    WHEN status = 'Resolved' THEN 'Resolved'
    WHEN status = 'Closed' THEN 'Closed'
    WHEN status = 'Rejected' THEN 'Rejected'
    WHEN status = 'Pending' THEN 'Pending'
    ELSE 'Pending' -- Fallback for unknowns
END;

-- 5. Convert to ENUM (Now safe as values match exactly)
ALTER TABLE tickets 
    ALTER COLUMN status TYPE ticket_status_new 
    USING status::ticket_status_new;

-- 6. Set Default
ALTER TABLE tickets ALTER COLUMN status SET DEFAULT 'Pending'::ticket_status_new;

COMMIT;
