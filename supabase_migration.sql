-- Ticket Status System Enhancement - Database Migration
-- Run this SQL in Supabase SQL Editor

-- ===========================================
-- 0. First, add 'New' to the status enum
-- ===========================================
-- Check enum name first (might be ticket_status_new or similar)
-- You may need to adjust the enum name based on your schema
ALTER TYPE ticket_status_new ADD VALUE IF NOT EXISTS 'New';

-- ===========================================
-- 1. Add feedback column to issues table
-- ===========================================
ALTER TABLE issues ADD COLUMN IF NOT EXISTS feedback INTEGER DEFAULT NULL;
-- Values: 1 (positive), 0 (neutral), -1 (negative), NULL (no feedback)

-- ===========================================
-- 2. Add rejection columns to tickets table
-- ===========================================
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS rejection_reason TEXT DEFAULT NULL;
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS rejection_comment TEXT DEFAULT NULL;

-- ===========================================
-- 3. Migrate existing "Pending" status to "New"
-- ===========================================
UPDATE tickets SET status = 'New' WHERE status = 'Pending';

-- ===========================================
-- 4. Function to auto-update ticket status
-- ===========================================
CREATE OR REPLACE FUNCTION update_ticket_status_on_issue_change()
RETURNS TRIGGER AS $$
DECLARE
  ticket_status TEXT;
  total_issues INTEGER;
  done_issues INTEGER;
  feedback_issues INTEGER;
  has_job_cards BOOLEAN;
BEGIN
  -- Get current ticket status
  SELECT status INTO ticket_status FROM tickets WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  
  -- Count issues
  SELECT COUNT(*), 
         COUNT(*) FILTER (WHERE status = 'Done'),
         COUNT(*) FILTER (WHERE feedback IS NOT NULL)
  INTO total_issues, done_issues, feedback_issues
  FROM issues WHERE ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  
  -- Check if ticket has job cards
  SELECT EXISTS(
    SELECT 1 FROM issues i 
    WHERE i.ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id) 
    AND i.job_card_id IS NOT NULL
  ) INTO has_job_cards;
  
  -- New → Accepted (on first issue creation)
  IF ticket_status = 'New' AND total_issues > 0 AND TG_OP = 'INSERT' THEN
    UPDATE tickets SET status = 'Accepted' WHERE id = NEW.ticket_id;
  END IF;
  
  -- Accepted → Work In Progress (on job card assignment)
  IF ticket_status = 'Accepted' AND has_job_cards THEN
    UPDATE tickets SET status = 'Work In Progress' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  
  -- Work In Progress → Resolved (all issues done)
  IF ticket_status = 'Work In Progress' AND total_issues > 0 AND done_issues = total_issues THEN
    UPDATE tickets SET status = 'Resolved' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  
  -- Resolved → Closed (all issues have feedback)
  IF ticket_status = 'Resolved' AND total_issues > 0 AND feedback_issues = total_issues THEN
    UPDATE tickets SET status = 'Closed' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- ===========================================
-- 5. Create trigger on issues table
-- ===========================================
DROP TRIGGER IF EXISTS trigger_update_ticket_status ON issues;
CREATE TRIGGER trigger_update_ticket_status
  AFTER INSERT OR UPDATE ON issues
  FOR EACH ROW
  EXECUTE FUNCTION update_ticket_status_on_issue_change();

-- ===========================================
-- Verification queries (run after migration)
-- ===========================================
-- Check if columns exist:
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'issues' AND column_name = 'feedback';
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'tickets' AND column_name = 'rejection_reason';

-- Check if trigger exists:
-- SELECT trigger_name FROM information_schema.triggers WHERE trigger_name = 'trigger_update_ticket_status';

-- Check migrated statuses:
-- SELECT status, COUNT(*) FROM tickets GROUP BY status;
