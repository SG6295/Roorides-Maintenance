-- Part 5: Recreate Views & Final Policies

BEGIN;

-- 1. Indexes & RLS
CREATE INDEX IF NOT EXISTS idx_issues_ticket_id ON issues(ticket_id);
CREATE INDEX IF NOT EXISTS idx_issues_job_card_id ON issues(job_card_id);
CREATE INDEX IF NOT EXISTS idx_issues_status ON issues(status);
CREATE INDEX IF NOT EXISTS idx_job_cards_status ON job_cards(status);
CREATE INDEX IF NOT EXISTS idx_job_cards_mechanic ON job_cards(assigned_mechanic_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status_new ON tickets(status);
CREATE INDEX IF NOT EXISTS idx_tickets_site_new ON tickets(site);

ALTER TABLE issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_cards ENABLE ROW LEVEL SECURITY;

-- Policies
DROP POLICY IF EXISTS "Supervisors view site issues" ON issues;
CREATE POLICY "Supervisors view site issues" ON issues 
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM tickets t
            JOIN users u ON u.id = auth.uid()
            WHERE t.id = issues.ticket_id AND u.role = 'supervisor' AND u.site = t.site
        )
    );

DROP POLICY IF EXISTS "Supervisors create issues" ON issues;
CREATE POLICY "Supervisors create issues" ON issues 
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM tickets t
            JOIN users u ON u.id = auth.uid()
            WHERE t.id = issues.ticket_id AND u.role = 'supervisor'
        )
    );

DROP POLICY IF EXISTS "Supervisors update own ratings" ON issues;
CREATE POLICY "Supervisors update own ratings" ON issues
    FOR UPDATE USING (
         EXISTS (
            SELECT 1 FROM tickets t
            JOIN users u ON u.id = auth.uid()
            WHERE t.id = issues.ticket_id AND u.role = 'supervisor' AND u.site = t.site
        )
    );

DROP POLICY IF EXISTS "Mechanics view assigned cards" ON job_cards;
CREATE POLICY "Mechanics view assigned cards" ON job_cards
    FOR SELECT USING (
        assigned_mechanic_id = auth.uid() OR
        EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'maintenance_exec')
    );
    
DROP POLICY IF EXISTS "Mechanics update assigned cards" ON job_cards;
CREATE POLICY "Mechanics update assigned cards" ON job_cards
    FOR UPDATE USING (assigned_mechanic_id = auth.uid());

DROP POLICY IF EXISTS "Execs manage issues" ON issues;
CREATE POLICY "Execs manage issues" ON issues FOR ALL
    USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'maintenance_exec'));

DROP POLICY IF EXISTS "Execs manage job cards" ON job_cards;
CREATE POLICY "Execs manage job cards" ON job_cards FOR ALL
    USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'maintenance_exec'));

-- 2. Recreate Views (Text Comparison)
CREATE OR REPLACE VIEW supervisor_dashboard_stats AS
SELECT
  t.site,
  COUNT(*) FILTER (WHERE t.status::text = 'Pending') as pending_count,
  COUNT(*) FILTER (WHERE t.status::text = 'Accepted') as accepted_count,
  COUNT(*) FILTER (WHERE t.status::text = 'Resolved') as completed_count,
  COUNT(*) FILTER (WHERE t.status::text = 'Rejected') as rejected_count,
  COUNT(*) FILTER (WHERE t.overall_sla_status::text = 'Violated') as sla_violated_count,
  COALESCE(AVG(
    CASE 
        WHEN i.rating::text = 'Good' THEN 2
        WHEN i.rating::text = 'Ok' THEN 1  
        WHEN i.rating::text = 'Bad' THEN 0
    END
  ), 0) as avg_csat_score
FROM tickets t
LEFT JOIN issues i ON i.ticket_id = t.id
GROUP BY t.site;

CREATE OR REPLACE VIEW maintenance_dashboard_stats AS
SELECT
  COUNT(*) as total_tickets,
  COUNT(*) FILTER (WHERE status::text = 'Pending') as pending_tickets,
  COUNT(*) FILTER (WHERE overall_sla_status::text = 'Violated') as completion_sla_violated,
  (SELECT COUNT(*) FROM job_cards WHERE type::text = 'InHouse') as inhouse_count,
  (SELECT COUNT(*) FROM job_cards WHERE type::text = 'Outsource') as outsource_count,
  COALESCE(AVG(EXTRACT(DAY FROM (CASE WHEN status::text = 'Resolved' THEN resolved_at ELSE NOW() END - created_at))), 0) as avg_tat_days
FROM tickets;

COMMIT;
