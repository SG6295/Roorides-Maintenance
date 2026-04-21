-- Fix: trg_update_ticket_sla_agg was declared as UPDATE OF sla_end_date only.
-- PostgreSQL column-specific triggers fire only when those columns appear in the
-- UPDATE SET clause — not when a BEFORE trigger modifies them internally.
-- Adding category/severity ensures the aggregate recalculates whenever an issue
-- is edited, even though sla_end_date is set by the BEFORE trigger, not the app.

DROP TRIGGER IF EXISTS trg_update_ticket_sla_agg ON issues;
CREATE TRIGGER trg_update_ticket_sla_agg
AFTER INSERT OR UPDATE OF sla_end_date, status, category, severity ON issues
FOR EACH ROW EXECUTE FUNCTION calculate_ticket_overall_sla();
