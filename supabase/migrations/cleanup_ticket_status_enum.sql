-- Remove legacy enum values 'Pending' and 'Work in Progress' (lowercase i)
-- from ticket_status_new. Postgres requires recreating the type.
-- Safe to run: no tickets use these values after the Pending→New migration.

-- 1. Drop views and triggers that depend on the status column
DROP VIEW IF EXISTS supervisor_dashboard_stats;
DROP VIEW IF EXISTS maintenance_dashboard_stats;
DROP TRIGGER IF EXISTS trg_ticket_sla_on_status_change ON tickets;
DROP TRIGGER IF EXISTS trg_stamp_rejected_at_and_acceptance_sla ON tickets;

-- 2. Drop column default so Postgres can alter the type freely
ALTER TABLE tickets ALTER COLUMN status DROP DEFAULT;

-- 3. Create the cleaned enum type
CREATE TYPE ticket_status_clean AS ENUM (
  'New',
  'Accepted',
  'Work In Progress',
  'Resolved',
  'Closed',
  'Rejected'
);

-- 4. Swap the column to the new type
ALTER TABLE tickets
  ALTER COLUMN status TYPE ticket_status_clean
  USING status::text::ticket_status_clean;

-- 5. Drop the old type and rename the new one
DROP TYPE ticket_status_new;
ALTER TYPE ticket_status_clean RENAME TO ticket_status_new;

-- 6. Restore the default
ALTER TABLE tickets ALTER COLUMN status SET DEFAULT 'New';

-- 7. Recreate supervisor_dashboard_stats (updated: 'Pending' → 'New')
CREATE VIEW supervisor_dashboard_stats AS
SELECT
  t.site,
  count(*) FILTER (WHERE t.status::text = 'New') AS pending_count,
  count(*) FILTER (WHERE t.status::text = 'Accepted') AS accepted_count,
  count(*) FILTER (WHERE t.status::text = 'Resolved') AS completed_count,
  count(*) FILTER (WHERE t.status::text = 'Rejected') AS rejected_count,
  count(*) FILTER (WHERE t.overall_sla_status::text = 'Violated') AS sla_violated_count,
  COALESCE(avg(
    CASE
      WHEN i.rating::text = 'Good' THEN 2
      WHEN i.rating::text = 'Ok'   THEN 1
      WHEN i.rating::text = 'Bad'  THEN 0
      ELSE NULL::integer
    END
  ), 0::numeric) AS avg_csat_score
FROM tickets t
LEFT JOIN issues i ON i.ticket_id = t.id
GROUP BY t.site;

-- 9. Recreate triggers
CREATE TRIGGER trg_stamp_rejected_at_and_acceptance_sla
  BEFORE UPDATE ON tickets
  FOR EACH ROW EXECUTE FUNCTION stamp_rejected_at_and_evaluate_acceptance_sla();

CREATE TRIGGER trg_ticket_sla_on_status_change
  AFTER UPDATE ON tickets
  FOR EACH ROW EXECUTE FUNCTION recalculate_ticket_sla_on_status_change();

-- 8. Recreate maintenance_dashboard_stats (updated: 'Pending' → 'New')
CREATE VIEW maintenance_dashboard_stats AS
SELECT
  count(*) AS total_tickets,
  count(*) FILTER (WHERE status::text = 'New') AS pending_tickets,
  count(*) FILTER (WHERE overall_sla_status::text = 'Violated') AS completion_sla_violated,
  (SELECT count(*) FROM job_cards WHERE job_cards.type::text = 'InHouse') AS inhouse_count,
  (SELECT count(*) FROM job_cards WHERE job_cards.type::text = 'Outsource') AS outsource_count,
  COALESCE(avg(EXTRACT(day FROM
    CASE
      WHEN status::text = 'Resolved' THEN resolved_at::timestamp with time zone
      ELSE now()
    END - created_at::timestamp with time zone
  )), 0::numeric) AS avg_tat_days
FROM tickets;
