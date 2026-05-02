-- Backfill final_sla_end_date for legacy tickets where it was never set
-- (created before the SLA aggregate trigger existed).
UPDATE tickets t
SET final_sla_end_date = (SELECT MAX(sla_end_date) FROM issues WHERE ticket_id = t.id)
WHERE final_sla_end_date IS NULL
  AND EXISTS (SELECT 1 FROM issues WHERE ticket_id = t.id AND sla_end_date IS NOT NULL);
