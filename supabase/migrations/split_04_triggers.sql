-- Part 4: Triggers

BEGIN;

-- 1. Issue SLA Calculation Trigger
CREATE OR REPLACE FUNCTION calculate_issue_sla_dynamic() RETURNS TRIGGER AS $$
DECLARE
    rule_days INTEGER;
BEGIN
    IF NEW.sla_days IS NULL OR NEW.sla_end_date IS NULL THEN
        SELECT sla_days INTO rule_days
        FROM sla_rules_config
        WHERE category = NEW.category AND severity = NEW.severity;
        
        IF rule_days IS NULL THEN rule_days := 3; END IF;

        NEW.sla_days := rule_days;
        NEW.sla_end_date := DATE(NEW.created_at) + rule_days;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_issue_sla_dynamic ON issues;
CREATE TRIGGER trg_issue_sla_dynamic
BEFORE INSERT ON issues
FOR EACH ROW EXECUTE FUNCTION calculate_issue_sla_dynamic();

-- 2. Issue Number Generation Trigger
CREATE OR REPLACE FUNCTION generate_issue_number() RETURNS TRIGGER AS $$
DECLARE
    ticket_num INTEGER;
    issue_count INTEGER;
BEGIN
    SELECT COALESCE(ticket_number, 0) INTO ticket_num FROM tickets WHERE id = NEW.ticket_id;
    SELECT COUNT(*) + 1 INTO issue_count FROM issues WHERE ticket_id = NEW.ticket_id;
    NEW.issue_number := 'T-' || ticket_num || '-' || LPAD(issue_count::text, 2, '0');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_generate_issue_number ON issues;
CREATE TRIGGER trg_generate_issue_number
BEFORE INSERT ON issues
FOR EACH ROW
WHEN (NEW.issue_number IS NULL)
EXECUTE FUNCTION generate_issue_number();

-- 3. Ticket Aggregate SLA Trigger
CREATE OR REPLACE FUNCTION calculate_ticket_overall_sla() RETURNS TRIGGER AS $$
BEGIN
    UPDATE tickets
    SET final_sla_end_date = (
        SELECT MAX(sla_end_date) FROM issues WHERE ticket_id = NEW.ticket_id
    )
    WHERE id = NEW.ticket_id;

    UPDATE tickets 
    SET overall_sla_status = 
        CASE 
            WHEN final_sla_end_date < CURRENT_DATE AND status::text NOT IN ('Resolved', 'Closed') 
                THEN 'Violated'::sla_status_enum
            WHEN status::text IN ('Resolved', 'Closed') AND final_sla_end_date >= resolved_at::date
                THEN 'Adhered'::sla_status_enum
            ELSE 'Pending'::sla_status_enum
        END
    WHERE id = NEW.ticket_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_ticket_sla_agg ON issues;
CREATE TRIGGER trg_update_ticket_sla_agg
AFTER INSERT OR UPDATE OF sla_end_date, status ON issues
FOR EACH ROW EXECUTE FUNCTION calculate_ticket_overall_sla();

COMMIT;
