-- Legacy Trigger Cleanup
-- Removes old SLA triggers from 'tickets' table that reference dropped columns (impact)

BEGIN;

-- 1. Explicitly drop known suspects if they exist
DROP TRIGGER IF EXISTS trg_set_sla_date ON tickets;
DROP TRIGGER IF EXISTS trg_log_sla_change ON tickets;
DROP TRIGGER IF EXISTS trg_calculate_ticket_sla ON tickets;
DROP TRIGGER IF EXISTS trg_update_sla_status ON tickets;

-- 2. Drop legacy functions associated with them
DROP FUNCTION IF EXISTS calculate_ticket_sla();
DROP FUNCTION IF EXISTS set_sla_date();
DROP FUNCTION IF EXISTS log_sla_change();

-- 3. Surgical Cleanup: Drop any trigger on tickets that looks like SLA logic
DO $$ 
DECLARE 
    trg_name TEXT;
BEGIN
    FOR trg_name IN 
        SELECT trigger_name 
        FROM information_schema.triggers 
        WHERE event_object_table = 'tickets' 
        AND trigger_name NOT IN ('handle_updated_at') -- Preserve necessary ones
    LOOP
        EXECUTE 'DROP TRIGGER IF EXISTS "' || trg_name || '" ON tickets CASCADE;';
        RAISE NOTICE 'Dropped legacy trigger: %', trg_name;
    END LOOP;
END $$;

COMMIT;
