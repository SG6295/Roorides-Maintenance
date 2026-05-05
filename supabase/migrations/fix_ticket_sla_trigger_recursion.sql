-- Fix infinite recursion: trg_ticket_sla_on_status_change fired on ALL updates
-- to tickets, so when recalculate_ticket_sla_on_status_change() did its own
-- UPDATE tickets SET overall_sla_status = ..., it re-fired itself endlessly.
-- Restrict to UPDATE OF status so only actual status transitions trigger it.

DROP TRIGGER IF EXISTS trg_ticket_sla_on_status_change ON public.tickets;

CREATE TRIGGER trg_ticket_sla_on_status_change
AFTER UPDATE OF status ON public.tickets
FOR EACH ROW
EXECUTE FUNCTION recalculate_ticket_sla_on_status_change();
