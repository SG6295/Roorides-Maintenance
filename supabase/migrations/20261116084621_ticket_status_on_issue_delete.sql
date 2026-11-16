-- MAIN-135: deleting an issue re-evaluates its ticket's status too.
--
-- trigger_update_ticket_status fired on INSERT and UPDATE only, so deleting the last
-- unfinished issue left the ticket in Work In Progress with every issue Done, and deleting
-- the last unrated one left it Resolved. update_ticket_status_on_issue_change already
-- reads the ticket through COALESCE(NEW.ticket_id, OLD.ticket_id), so only the trigger
-- changes. A ticket whose issues are all deleted keeps its status (no transition applies
-- to zero issues). No ticket in prod or staging is in either state today.

DROP TRIGGER IF EXISTS trigger_update_ticket_status ON public.issues;
CREATE TRIGGER trigger_update_ticket_status
    AFTER INSERT OR DELETE OR UPDATE OF status, rating, job_card_id, ticket_id ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.update_ticket_status_on_issue_change();
