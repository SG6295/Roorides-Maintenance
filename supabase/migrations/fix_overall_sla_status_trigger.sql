-- Fix: overall_sla_status never updated when ticket status changes to Resolved/Closed.
-- Root cause 1: no trigger on the tickets table watching for status changes.
-- Root cause 2: calculate_ticket_overall_sla's Adhered check uses resolved_at which
--   can be NULL for directly-Closed tickets, making the CASE fall through to 'Pending'.

-- Step 1: Fix the issues-triggered function to handle NULL resolved_at / closed_at.
CREATE OR REPLACE FUNCTION calculate_ticket_overall_sla() RETURNS TRIGGER AS $$
DECLARE
    v_final_sla   DATE;
    v_status      TEXT;
    v_resolved_at DATE;
BEGIN
    -- Update final_sla_end_date = MAX(issues.sla_end_date) for this ticket
    UPDATE tickets
    SET final_sla_end_date = (
        SELECT MAX(sla_end_date) FROM issues WHERE ticket_id = NEW.ticket_id
    )
    WHERE id = NEW.ticket_id
    RETURNING final_sla_end_date, status::text, COALESCE(resolved_at::date, closed_at::date)
    INTO v_final_sla, v_status, v_resolved_at;

    UPDATE tickets
    SET overall_sla_status =
        CASE
            WHEN v_final_sla IS NULL
                THEN 'Pending'::sla_status_enum
            WHEN v_status IN ('Resolved', 'Closed') AND v_final_sla >= COALESCE(v_resolved_at, CURRENT_DATE)
                THEN 'Adhered'::sla_status_enum
            WHEN v_status IN ('Resolved', 'Closed')
                THEN 'Violated'::sla_status_enum
            WHEN v_final_sla < CURRENT_DATE
                THEN 'Violated'::sla_status_enum
            ELSE 'Pending'::sla_status_enum
        END
    WHERE id = NEW.ticket_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 2: New function for the tickets-table trigger (uses NEW.id, not NEW.ticket_id).
CREATE OR REPLACE FUNCTION recalculate_ticket_sla_on_status_change() RETURNS TRIGGER AS $$
DECLARE
    v_final_sla   DATE;
    v_resolved_at DATE;
BEGIN
    SELECT final_sla_end_date, COALESCE(resolved_at::date, closed_at::date)
    INTO v_final_sla, v_resolved_at
    FROM tickets WHERE id = NEW.id;

    UPDATE tickets
    SET overall_sla_status =
        CASE
            WHEN v_final_sla IS NULL
                THEN 'Pending'::sla_status_enum
            WHEN NEW.status::text IN ('Resolved', 'Closed') AND v_final_sla >= COALESCE(v_resolved_at, CURRENT_DATE)
                THEN 'Adhered'::sla_status_enum
            WHEN NEW.status::text IN ('Resolved', 'Closed')
                THEN 'Violated'::sla_status_enum
            WHEN v_final_sla < CURRENT_DATE
                THEN 'Violated'::sla_status_enum
            ELSE 'Pending'::sla_status_enum
        END
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 3: Trigger on tickets — fires whenever status (or resolved_at/closed_at) changes.
DROP TRIGGER IF EXISTS trg_ticket_sla_on_status_change ON tickets;
CREATE TRIGGER trg_ticket_sla_on_status_change
AFTER UPDATE OF status, resolved_at, closed_at ON tickets
FOR EACH ROW EXECUTE FUNCTION recalculate_ticket_sla_on_status_change();

-- Step 4: Backfill overall_sla_status for all existing tickets.
UPDATE tickets t
SET overall_sla_status =
    CASE
        WHEN t.final_sla_end_date IS NULL
            THEN 'Pending'::sla_status_enum
        WHEN t.status::text IN ('Resolved', 'Closed')
             AND t.final_sla_end_date >= COALESCE(t.resolved_at::date, t.closed_at::date, CURRENT_DATE)
            THEN 'Adhered'::sla_status_enum
        WHEN t.status::text IN ('Resolved', 'Closed')
            THEN 'Violated'::sla_status_enum
        WHEN t.final_sla_end_date < CURRENT_DATE
            THEN 'Violated'::sla_status_enum
        ELSE 'Pending'::sla_status_enum
    END;
