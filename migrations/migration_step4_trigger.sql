-- Migration Step 4: Create trigger for automatic status transitions
-- Run this LAST after all previous steps complete

-- Function to auto-update ticket status
CREATE OR REPLACE FUNCTION update_ticket_status_on_issue_change()
RETURNS TRIGGER AS $$
DECLARE
  ticket_status TEXT;
  total_issues INTEGER;
  done_issues INTEGER;
  feedback_issues INTEGER;
  has_job_cards BOOLEAN;
BEGIN
  SELECT status INTO ticket_status FROM tickets WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  
  SELECT COUNT(*), 
         COUNT(*) FILTER (WHERE status = 'Done'),
         COUNT(*) FILTER (WHERE feedback IS NOT NULL)
  INTO total_issues, done_issues, feedback_issues
  FROM issues WHERE ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  
  SELECT EXISTS(
    SELECT 1 FROM issues i 
    WHERE i.ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id) 
    AND i.job_card_id IS NOT NULL
  ) INTO has_job_cards;
  
  -- New → Accepted (on issue creation)
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

-- Create trigger
DROP TRIGGER IF EXISTS trigger_update_ticket_status ON issues;
CREATE TRIGGER trigger_update_ticket_status
  AFTER INSERT OR UPDATE ON issues
  FOR EACH ROW
  EXECUTE FUNCTION update_ticket_status_on_issue_change();

-- Migration complete!
