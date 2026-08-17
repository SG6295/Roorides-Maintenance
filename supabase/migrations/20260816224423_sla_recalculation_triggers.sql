-- MAIN-45, part 3 of 4: editing SLA configuration recalculates open work.
--
-- Until now a deadline was computed once and never revisited. calculate_issue_sla_dynamic
-- only fires when an issue's own category/severity changes, so changing a rule's day
-- count, the weekly offs, or the holiday calendar left every existing deadline untouched
-- and the settings page had no visible effect on anything already raised.
--
-- Per the ticket's 2026-08-17 decision, configuration changes now reach work that is
-- still in flight. Finished work is never retouched: a closed ticket's verdict is a
-- historical measurement, not a derived value.
--
-- Accepted consequence, recorded on the ticket: shortening a rule can move a deadline
-- into the past and flip an open ticket to Violated the moment the setting is saved.

CREATE OR REPLACE FUNCTION public.recalculate_open_slas()
    RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    -- Issue deadlines. Scoped by BOTH the issue and its ticket: production carries a
    -- handful of issues left Open on tickets that were long since Resolved or Rejected,
    -- and a rule edit should not resurrect deadlines on work nobody is doing.
    --
    -- Every open issue is recomputed, not just those matching the rule that changed.
    -- Recomputation reads each issue's own current rule, so rows the edit did not touch
    -- come out unchanged - it is idempotent, and far simpler than working out which rows
    -- a given configuration change could have affected.
    UPDATE issues i
    SET sla_days     = r.sla_days,
        sla_end_date = add_working_days(i.created_at AT TIME ZONE 'UTC', r.sla_days)
    FROM tickets t, sla_rules_config r
    WHERE i.ticket_id = t.id
      AND r.category  = i.category
      AND r.severity  = i.severity
      AND i.status <> 'Done'
      AND t.status NOT IN ('Resolved', 'Closed', 'Rejected');

    -- Acceptance deadlines, for tickets still waiting to be accepted. Once acceptance has
    -- been judged Adhered or Violated the measurement stands.
    UPDATE tickets t
    SET acceptance_sla_end_date = acceptance_deadline(t.created_at AT TIME ZONE 'UTC')
    WHERE t.acceptance_sla_status = 'Pending'
      AND t.status NOT IN ('Resolved', 'Closed', 'Rejected');

    -- The issue UPDATE above fires trg_update_ticket_sla_agg, which rolls each changed
    -- sla_end_date up into tickets.final_sla_end_date and re-derives overall_sla_status.
    -- Nothing further is needed here.
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_recalculate_open_slas()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    PERFORM recalculate_open_slas();
    RETURN NULL;
END;
$$;

-- Rule day-counts. Statement-level: a settings save touches one row, but a bulk correction
-- should still trigger exactly one recalculation pass.
DROP TRIGGER IF EXISTS trg_sla_rules_config_recalc ON public.sla_rules_config;
CREATE TRIGGER trg_sla_rules_config_recalc
    AFTER INSERT OR UPDATE OR DELETE ON public.sla_rules_config
    FOR EACH STATEMENT EXECUTE FUNCTION public.trg_recalculate_open_slas();

-- Holiday calendar: adding or removing a non-working day moves every open deadline that
-- spans it.
DROP TRIGGER IF EXISTS trg_holidays_recalc ON public.holidays;
CREATE TRIGGER trg_holidays_recalc
    AFTER INSERT OR UPDATE OR DELETE ON public.holidays
    FOR EACH STATEMENT EXECUTE FUNCTION public.trg_recalculate_open_slas();

-- Weekly offs and the acceptance threshold. Row-level with a WHEN clause so that saving
-- an unrelated setting does not walk every open ticket.
DROP TRIGGER IF EXISTS trg_system_settings_sla_recalc ON public.system_settings;
CREATE TRIGGER trg_system_settings_sla_recalc
    AFTER INSERT OR UPDATE ON public.system_settings
    FOR EACH ROW
    WHEN (NEW.key IN ('sla_weekly_offs', 'acceptance_sla_days'))
    EXECUTE FUNCTION public.trg_recalculate_open_slas();
