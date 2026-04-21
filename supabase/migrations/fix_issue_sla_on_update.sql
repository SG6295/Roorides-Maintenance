-- Fix: recalculate issue sla_end_date when category or severity is edited.
-- Previously the trigger only fired on INSERT; editing an issue's category/severity
-- left sla_end_date (and therefore tickets.final_sla_end_date) stale.

CREATE OR REPLACE FUNCTION calculate_issue_sla_dynamic() RETURNS TRIGGER AS $$
DECLARE
    rule_days INTEGER;
BEGIN
    -- Recalculate on INSERT, or on UPDATE when category/severity actually changed.
    IF TG_OP = 'INSERT'
       OR (TG_OP = 'UPDATE' AND (
           NEW.category  IS DISTINCT FROM OLD.category OR
           NEW.severity  IS DISTINCT FROM OLD.severity
       ))
    THEN
        SELECT sla_days INTO rule_days
        FROM sla_rules_config
        WHERE category = NEW.category AND severity = NEW.severity;

        IF rule_days IS NULL THEN rule_days := 3; END IF;

        NEW.sla_days    := rule_days;
        NEW.sla_end_date := DATE(NEW.created_at) + rule_days;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Re-create trigger to also fire on UPDATE
DROP TRIGGER IF EXISTS trg_issue_sla_dynamic ON issues;
CREATE TRIGGER trg_issue_sla_dynamic
BEFORE INSERT OR UPDATE ON issues
FOR EACH ROW EXECUTE FUNCTION calculate_issue_sla_dynamic();
