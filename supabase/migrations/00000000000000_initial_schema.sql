--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_cron; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION pg_cron; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_cron IS 'Job scheduler for PostgreSQL';


--
-- Name: pg_net; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;


--
-- Name: EXTENSION pg_net; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_net IS 'Async HTTP';


--
-- Name: issue_category; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.issue_category AS ENUM (
    'Mechanical',
    'Electrical',
    'Body',
    'Tyre',
    'GPS',
    'AdBlue',
    'Other'
);


ALTER TYPE public.issue_category OWNER TO postgres;

--
-- Name: issue_severity; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.issue_severity AS ENUM (
    'Minor',
    'Major'
);


ALTER TYPE public.issue_severity OWNER TO postgres;

--
-- Name: issue_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.issue_status AS ENUM (
    'Open',
    'Done',
    'Blocked'
);


ALTER TYPE public.issue_status OWNER TO postgres;

--
-- Name: job_card_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.job_card_status AS ENUM (
    'Open',
    'Completed'
);


ALTER TYPE public.job_card_status OWNER TO postgres;

--
-- Name: outsource_part_disposition; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.outsource_part_disposition AS ENUM (
    'returned_to_nvs',
    'retained_by_vendor',
    'retained_by_vendor_with_credit'
);


ALTER TYPE public.outsource_part_disposition OWNER TO postgres;

--
-- Name: rating_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.rating_enum AS ENUM (
    'Good',
    'Ok',
    'Bad'
);


ALTER TYPE public.rating_enum OWNER TO postgres;

--
-- Name: scrap_exclusion_reason; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.scrap_exclusion_reason AS ENUM (
    'consumable',
    'destroyed_on_removal',
    'retained_by_vendor',
    'other'
);


ALTER TYPE public.scrap_exclusion_reason OWNER TO postgres;

--
-- Name: scrap_item_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.scrap_item_status AS ENUM (
    'in_storage',
    'sent_for_refurbishment',
    'refurbished',
    'sold',
    'written_off',
    'reversed'
);


ALTER TYPE public.scrap_item_status OWNER TO postgres;

--
-- Name: scrap_payment_mode; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.scrap_payment_mode AS ENUM (
    'cash',
    'upi',
    'bank_transfer',
    'cheque',
    'other'
);


ALTER TYPE public.scrap_payment_mode OWNER TO postgres;

--
-- Name: scrap_writeoff_reason; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.scrap_writeoff_reason AS ENUM (
    'lost',
    'damaged_unsaleable',
    'hazmat_disposal',
    'stocktake_adjustment',
    'donated',
    'other'
);


ALTER TYPE public.scrap_writeoff_reason OWNER TO postgres;

--
-- Name: sla_status_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.sla_status_enum AS ENUM (
    'Pending',
    'Adhered',
    'Violated'
);


ALTER TYPE public.sla_status_enum OWNER TO postgres;

--
-- Name: ticket_status_new; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.ticket_status_new AS ENUM (
    'New',
    'Accepted',
    'Work In Progress',
    'Resolved',
    'Closed',
    'Rejected'
);


ALTER TYPE public.ticket_status_new OWNER TO postgres;

--
-- Name: work_type_enum; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.work_type_enum AS ENUM (
    'InHouse',
    'Outsource'
);


ALTER TYPE public.work_type_enum OWNER TO postgres;

--
-- Name: add_part_to_inventory(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_part_to_inventory() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    UPDATE parts
    SET quantity_in_stock = quantity_in_stock + NEW.quantity
    WHERE id = NEW.part_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.add_part_to_inventory() OWNER TO postgres;

--
-- Name: add_working_days(date, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_working_days(start_date date, n_days integer) RETURNS date
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    current_d   DATE := start_date;
    days_added  INT  := 0;
    weekly_offs JSONB;
    dow         INT;
    is_holiday  BOOLEAN;
BEGIN
    SELECT value::jsonb INTO weekly_offs
    FROM system_settings WHERE key = 'sla_weekly_offs';
    IF weekly_offs IS NULL THEN weekly_offs := '[0,6]'::jsonb; END IF;

    WHILE days_added < n_days LOOP
        current_d := current_d + 1;
        dow := EXTRACT(DOW FROM current_d)::INT;

        -- Skip weekly offs (day-of-week integers: 0=Sun … 6=Sat)
        IF weekly_offs @> to_jsonb(dow) THEN CONTINUE; END IF;

        -- Skip holidays
        SELECT EXISTS (SELECT 1 FROM holidays WHERE date = current_d) INTO is_holiday;
        IF is_holiday THEN CONTINUE; END IF;

        days_added := days_added + 1;
    END LOOP;

    RETURN current_d;
END;
$$;


ALTER FUNCTION public.add_working_days(start_date date, n_days integer) OWNER TO postgres;

--
-- Name: adjust_part_inventory_on_update(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.adjust_part_inventory_on_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    IF NEW.part_id = OLD.part_id THEN
        -- Same part: apply the quantity delta
        UPDATE parts
        SET quantity_in_stock = quantity_in_stock + (NEW.quantity - OLD.quantity)
        WHERE id = NEW.part_id;
    ELSE
        -- Part changed: reverse old part stock, add to new part stock
        UPDATE parts SET quantity_in_stock = quantity_in_stock - OLD.quantity WHERE id = OLD.part_id;
        UPDATE parts SET quantity_in_stock = quantity_in_stock + NEW.quantity WHERE id = NEW.part_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.adjust_part_inventory_on_update() OWNER TO postgres;

--
-- Name: calculate_issue_sla_dynamic(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_issue_sla_dynamic() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.calculate_issue_sla_dynamic() OWNER TO postgres;

--
-- Name: calculate_sla_days(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_sla_days(p_impact text, p_category text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN CASE
    WHEN p_impact = 'Major' AND p_category = 'Electrical' THEN 7
    WHEN p_impact = 'Major' AND p_category = 'Mechanical' THEN 15
    WHEN p_impact = 'Major' AND p_category = 'Body' THEN 30
    WHEN p_impact = 'Major' AND p_category = 'Tyre' THEN 15
    WHEN p_impact = 'Major' AND p_category = 'GPS/Camera' THEN 3
    WHEN p_impact = 'Minor' THEN 3
    ELSE 3
  END;
END;
$$;


ALTER FUNCTION public.calculate_sla_days(p_impact text, p_category text) OWNER TO postgres;

--
-- Name: calculate_ticket_overall_sla(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_ticket_overall_sla() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.calculate_ticket_overall_sla() OWNER TO postgres;

--
-- Name: check_pan_exists(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_pan_exists(p_pan text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM suppliers WHERE upper(trim(pan_number)) = upper(trim(p_pan))
  );
$$;


ALTER FUNCTION public.check_pan_exists(p_pan text) OWNER TO postgres;

--
-- Name: close_job_card_with_scrap(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card              job_cards%ROWTYPE;
    v_decision              jsonb;
    v_issue_part_id         uuid;
    v_action                text;
    v_scrap_ids             uuid[] := '{}';
    v_exclusion_ids         uuid[] := '{}';
    v_reversed_scrap_ids    uuid[] := '{}';
    v_reversed_id           uuid;
    v_new_id                uuid;
    v_issue_part_ids        uuid[];
    v_group_a_ids           uuid[];
    v_required_part_ids     uuid[];
    v_decision_part_ids     uuid[];
    v_missing_ids           uuid[];
    v_extra_ids             uuid[];
    v_extra_permanent_ids   uuid[];
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can close job cards.',
            'details',       null
        )::text;
    END IF;

    SELECT * INTO v_job_card
    FROM   public.job_cards
    WHERE  id = p_job_card_id AND status = 'Open';

    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'JOB_CARD_NOT_FOUND_OR_NOT_OPEN',
            'error_message', 'Job card not found or is not currently Open.',
            'details',       null
        )::text;
    END IF;

    IF v_job_card.type = 'Outsource' AND v_job_card.invoice_url IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_REQUIRED',
            'error_message', 'Outsource job cards require an invoice before closure.',
            'details',       null
        )::text;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.issues
        WHERE  job_card_id = p_job_card_id
          AND  status <> 'Done'::issue_status
    ) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'ISSUES_NOT_DONE',
            'error_message', 'All issues must be marked Done before closing the job card.',
            'details',       null
        )::text;
    END IF;

    SELECT coalesce(array_agg(ip.id), '{}')
    INTO   v_issue_part_ids
    FROM   public.issue_parts ip
    JOIN   public.issues      i  ON i.id = ip.issue_id
    WHERE  i.job_card_id = p_job_card_id;

    SELECT coalesce(array_agg(ip.id), '{}')
    INTO   v_group_a_ids
    FROM   public.issue_parts ip
    JOIN   public.issues      i  ON i.id = ip.issue_id
    WHERE  i.job_card_id = p_job_card_id
      AND  public.get_blocking_scrap_for_issue_part(ip.id) IS NOT NULL;

    SELECT coalesce(array_agg(id), '{}')
    INTO   v_required_part_ids
    FROM   unnest(v_issue_part_ids) AS id
    WHERE  id != ALL(v_group_a_ids);

    SELECT coalesce(array_agg((d->>'issue_part_id')::uuid), '{}')
    INTO   v_decision_part_ids
    FROM   jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb)) AS d;

    SELECT array_agg(id)
    INTO   v_extra_permanent_ids
    FROM   unnest(v_decision_part_ids) AS id
    WHERE  id = ANY(v_group_a_ids);

    IF v_extra_permanent_ids IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DECISIONS_EXTRA_PART_PERMANENT_SCRAP',
            'error_message', 'A decision was provided for a part whose scrap has already been permanently recorded. Remove it from the decisions array.',
            'details',       json_build_object('extra_part_ids', v_extra_permanent_ids)
        )::text;
    END IF;

    SELECT array_agg(id)
    INTO   v_missing_ids
    FROM   unnest(v_required_part_ids) AS id
    WHERE  id != ALL(v_decision_part_ids);

    IF v_missing_ids IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DECISIONS_MISSING_PART',
            'error_message', 'A part was added to this job card while you were entering decisions. The card will refresh — please review and re-submit.',
            'details',       json_build_object('missing_part_ids', v_missing_ids)
        )::text;
    END IF;

    SELECT array_agg(id)
    INTO   v_extra_ids
    FROM   unnest(v_decision_part_ids) AS id
    WHERE  id != ALL(v_issue_part_ids);

    IF v_extra_ids IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DECISIONS_EXTRA_PART',
            'error_message', 'A part was removed from this job card while you were entering decisions. The card will refresh — please review and re-submit.',
            'details',       json_build_object('extra_part_ids', v_extra_ids)
        )::text;
    END IF;

    FOR v_decision IN
        SELECT * FROM jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb))
    LOOP
        v_action        := v_decision->>'action';
        v_issue_part_id := (v_decision->>'issue_part_id')::uuid;

        IF v_action = 'exclude' AND (v_decision->>'exclusion_reason') IS NULL THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'MISSING_EXCLUSION_REASON',
                'error_message', 'Exclusion reason is required for excluded parts.',
                'details',       json_build_object('issue_part_id', v_issue_part_id)
            )::text;
        END IF;

        IF v_action = 'scrap'
           AND v_job_card.type = 'Outsource'
           AND (v_decision->>'outsource_disposition') IS NULL
        THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'MISSING_DISPOSITION',
                'error_message', 'Outsource disposition is required for scrapped parts on Outsource job cards.',
                'details',       json_build_object('issue_part_id', v_issue_part_id)
            )::text;
        END IF;

        IF (v_decision->>'outsource_disposition') = 'retained_by_vendor_with_credit' THEN
            IF (v_decision->>'outsource_credit_amount') IS NULL
               OR (v_decision->>'outsource_credit_amount')::numeric <= 0
            THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'INVALID_CREDIT_AMOUNT',
                    'error_message', 'Credit amount must be a positive number when disposition is "retained by vendor with credit".',
                    'details',       json_build_object('issue_part_id', v_issue_part_id)
                )::text;
            END IF;
        END IF;
    END LOOP;

    UPDATE public.job_cards
    SET    status       = 'Completed',
           completed_at = now(),
           remarks      = p_remarks
    WHERE  id = p_job_card_id;

    FOR v_decision IN
        SELECT * FROM jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb))
    LOOP
        v_action        := v_decision->>'action';
        v_issue_part_id := (v_decision->>'issue_part_id')::uuid;

        FOR v_reversed_id IN
            UPDATE public.scrap_inventory
            SET    status     = 'reversed',
                   updated_at = now(),
                   updated_by = auth.uid()
            WHERE  source_issue_part_id = v_issue_part_id
              AND  status = 'in_storage'
            RETURNING id
        LOOP
            v_reversed_scrap_ids := v_reversed_scrap_ids || v_reversed_id;
        END LOOP;

        IF v_action = 'scrap' THEN

            IF v_job_card.type = 'Outsource' THEN
                UPDATE public.issue_parts
                SET    outsource_part_disposition     = (v_decision->>'outsource_disposition')::outsource_part_disposition,
                       outsource_vendor_credit_amount =
                           CASE
                               WHEN (v_decision->>'outsource_disposition') = 'retained_by_vendor_with_credit'
                               THEN (v_decision->>'outsource_credit_amount')::numeric
                               ELSE NULL
                           END
                WHERE  id = v_issue_part_id;
            END IF;

            INSERT INTO public.scrap_inventory (
                source_ticket_id, source_job_card_id, source_issue_id,
                source_issue_part_id, source_vehicle_number,
                part_id_snapshot, part_name_snapshot, part_number_snapshot,
                quantity_snapshot, unit_snapshot, status,
                outsource_part_disposition_snapshot,
                outsource_vendor_credit_amount_snapshot, created_by
            )
            SELECT
                i.ticket_id, jc.id, ip.issue_id, ip.id, jc.vehicle_number,
                p.id, p.name, p.part_number, ip.quantity_used, p.unit,
                'in_storage'::scrap_item_status,
                CASE WHEN jc.type = 'Outsource'
                     THEN (v_decision->>'outsource_disposition')::outsource_part_disposition
                     ELSE NULL END,
                CASE WHEN jc.type = 'Outsource'
                          AND (v_decision->>'outsource_disposition') = 'retained_by_vendor_with_credit'
                     THEN (v_decision->>'outsource_credit_amount')::numeric
                     ELSE NULL END,
                auth.uid()
            FROM  public.issue_parts ip
            JOIN  public.issues      i  ON i.id  = ip.issue_id
            JOIN  public.job_cards   jc ON jc.id = i.job_card_id
            JOIN  public.parts       p  ON p.id  = ip.part_id
            WHERE ip.id = v_issue_part_id
            RETURNING id INTO v_new_id;

            v_scrap_ids := v_scrap_ids || v_new_id;

        ELSIF v_action = 'exclude' THEN

            INSERT INTO public.scrap_excluded_parts (
                source_job_card_id, source_issue_id, source_issue_part_id,
                part_id_snapshot, part_name_snapshot, quantity_snapshot,
                reason, notes, excluded_by
            )
            SELECT
                jc.id, ip.issue_id, ip.id, p.id, p.name, ip.quantity_used,
                (v_decision->>'exclusion_reason')::scrap_exclusion_reason,
                v_decision->>'exclusion_notes',
                auth.uid()
            FROM  public.issue_parts ip
            JOIN  public.issues      i  ON i.id  = ip.issue_id
            JOIN  public.job_cards   jc ON jc.id = i.job_card_id
            JOIN  public.parts       p  ON p.id  = ip.part_id
            WHERE ip.id = v_issue_part_id
            RETURNING id INTO v_new_id;

            v_exclusion_ids := v_exclusion_ids || v_new_id;

        END IF;
    END LOOP;

    RETURN json_build_object(
        'success',            true,
        'job_card_id',        p_job_card_id,
        'scrap_entry_ids',    v_scrap_ids,
        'exclusion_ids',      v_exclusion_ids,
        'reversed_scrap_ids', v_reversed_scrap_ids
    );
END;
$$;


ALTER FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) OWNER TO postgres;

--
-- Name: deduct_part_from_inventory(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.deduct_part_from_inventory() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card_type text;
BEGIN
    SELECT jc.type INTO v_job_card_type
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  i.id = NEW.issue_id;

    IF v_job_card_type = 'Outsource' THEN
        RETURN NEW;
    END IF;

    UPDATE public.parts
    SET    quantity_in_stock = quantity_in_stock - NEW.quantity_used
    WHERE  id = NEW.part_id;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.deduct_part_from_inventory() OWNER TO postgres;

--
-- Name: delete_issue_part_with_scrap_check(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_blocking_scrap jsonb;
    v_reversed_ids   uuid[] := '{}';
    v_reversed_id    uuid;
BEGIN
    -- (a) Caller must be maintenance_exec or super_admin
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can remove parts.',
            'details',       null
        )::text;
    END IF;

    -- (b) Detect permanent-status scrap that would be orphaned by the delete
    SELECT public.get_blocking_scrap_for_issue_part(p_issue_part_id)
    INTO   v_blocking_scrap;

    IF v_blocking_scrap IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'SCRAP_BLOCKING_DELETE',
            'error_message', 'Cannot remove this part — the associated scrap record has been '
                             || (v_blocking_scrap->>'status')
                             || ' and cannot be undone.',
            'details',       v_blocking_scrap
                             || jsonb_build_object('issue_part_id', p_issue_part_id)
        )::text;
    END IF;

    -- (c) Auto-reverse any in_storage scrap entries for this part line.
    FOR v_reversed_id IN
        UPDATE public.scrap_inventory
        SET    status     = 'reversed',
               updated_at = now(),
               updated_by = auth.uid()
        WHERE  source_issue_part_id = p_issue_part_id
          AND  status = 'in_storage'
        RETURNING id
    LOOP
        v_reversed_ids := v_reversed_ids || v_reversed_id;
    END LOOP;

    -- (d) Delete the issue_part.  The existing trigger restores inventory stock.
    DELETE FROM public.issue_parts WHERE id = p_issue_part_id;

    RETURN jsonb_build_object(
        'success',               true,
        'deleted_issue_part_id', p_issue_part_id,
        'reversed_scrap_ids',    v_reversed_ids
    );
END;
$$;


ALTER FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) OWNER TO postgres;

--
-- Name: evaluate_acceptance_sla(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone) RETURNS public.sla_status_enum
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_created_at  DATE;
    v_sla_days    INT;
    v_deadline    DATE;
BEGIN
    SELECT created_at::date INTO v_created_at FROM tickets WHERE id = p_ticket_id;
    SELECT value::INT INTO v_sla_days FROM system_settings WHERE key = 'acceptance_sla_days';
    IF v_sla_days IS NULL THEN v_sla_days := 2; END IF;
    v_deadline := add_working_days(v_created_at, v_sla_days);
    IF p_first_issue_created::date <= v_deadline THEN
        RETURN 'Adhered'::sla_status_enum;
    ELSE
        RETURN 'Violated'::sla_status_enum;
    END IF;
END;
$$;


ALTER FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone) OWNER TO postgres;

--
-- Name: generate_issue_number(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_issue_number() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    ticket_num INTEGER;
    issue_count INTEGER;
BEGIN
    SELECT COALESCE(ticket_number, 0) INTO ticket_num FROM tickets WHERE id = NEW.ticket_id;
    SELECT COUNT(*) + 1 INTO issue_count FROM issues WHERE ticket_id = NEW.ticket_id;
    NEW.issue_number := 'T-' || ticket_num || '-' || LPAD(issue_count::text, 2, '0');
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.generate_issue_number() OWNER TO postgres;

--
-- Name: get_blocking_scrap_for_issue_part(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_blocking_scrap_for_issue_part(p_issue_part_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
    SELECT jsonb_build_object(
        'is_blocking',           true,
        'scrap_inventory_id',    si.id,
        'part_name',             si.part_name_snapshot,
        'status',                si.status,
        'downstream_record_type', CASE
            WHEN si.status = 'sold'                  THEN 'disposal'
            WHEN si.status = 'written_off'           THEN 'writeoff'
            WHEN si.status IN ('refurbished',
                               'sent_for_refurbishment') THEN 'refurbishment'
            ELSE NULL
        END,
        'downstream_record_id', CASE
            WHEN si.status = 'sold' THEN (
                SELECT sdi.disposal_id
                FROM   public.scrap_disposal_items sdi
                WHERE  sdi.scrap_inventory_id = si.id
                LIMIT  1
            )
            WHEN si.status = 'written_off' THEN (
                SELECT swi.writeoff_id
                FROM   public.scrap_writeoff_items swi
                WHERE  swi.scrap_inventory_id = si.id
                LIMIT  1
            )
            ELSE NULL
        END
    )
    FROM  public.scrap_inventory si
    WHERE si.source_issue_part_id = p_issue_part_id
      AND si.status IN (
              'sold', 'written_off',
              'refurbished', 'sent_for_refurbishment'
          )
    LIMIT 1
$$;


ALTER FUNCTION public.get_blocking_scrap_for_issue_part(p_issue_part_id uuid) OWNER TO postgres;

--
-- Name: get_maintenance_stats(date, date, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_maintenance_stats(start_date_input date DEFAULT NULL::date, end_date_input date DEFAULT NULL::date, site_filter text DEFAULT NULL::text) RETURNS TABLE(total_tickets bigint, status_new bigint, status_pending bigint, status_accepted bigint, status_wip bigint, status_resolved bigint, status_closed bigint, status_rejected bigint, status_completed bigint, major_total bigint, major_electrical bigint, major_mechanical bigint, major_body bigint, major_tyre bigint, minor_total bigint, minor_electrical bigint, minor_mechanical bigint, minor_body bigint, minor_tyre bigint, type_in_house bigint, type_outsource bigint, accept_pending bigint, accept_adhered bigint, accept_violated bigint, comp_in_wip_within bigint, comp_in_adhered bigint, comp_in_violated bigint, comp_out_wip_within bigint, comp_out_adhered bigint, comp_out_violated bigint, rating_pending bigint, rating_collected bigint, rating_good bigint, rating_ok bigint, rating_bad bigint, csat_score_sum bigint, total_completed_tickets bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_sla_days INT;
BEGIN
  SELECT COALESCE(value::int, 2)
    INTO v_sla_days
    FROM system_settings
   WHERE key = 'acceptance_sla_days';

  RETURN QUERY
  WITH ticket_data AS (
    SELECT
      t.id,
      t.status,
      t.created_at,
      t.resolved_at,
      t.closed_at,
      t.final_sla_end_date,
      t.overall_sla_status,
      t.acceptance_sla_status,
      CASE
        WHEN t.overall_sla_status IN ('Adhered', 'Violated') THEN t.overall_sla_status
        WHEN t.final_sla_end_date IS NOT NULL
             AND CURRENT_DATE > t.final_sla_end_date::date THEN 'Violated'
        ELSE 'Pending'
      END AS eff_overall,
      CASE
        WHEN t.acceptance_sla_status IN ('Adhered', 'Violated') THEN t.acceptance_sla_status
        WHEN NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id)
             AND CURRENT_DATE > add_working_days(t.created_at::date, v_sla_days) THEN 'Violated'
        ELSE 'Pending'
      END AS eff_accept,
      CASE
        WHEN EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id AND i.work_type = 'Outsource')
         AND NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id AND i.work_type = 'InHouse')
        THEN 'Outsource'
        ELSE 'InHouse'
      END AS dominant_work_type
    FROM tickets t
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter       IS NULL OR t.site = site_filter)
  ),
  issue_data AS (
    SELECT i.*
    FROM issues i
    JOIN tickets t ON i.ticket_id = t.id
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter       IS NULL OR t.site = site_filter)
  )
  SELECT
    COUNT(*)::BIGINT AS total_tickets,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT AS status_new,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT AS status_pending,
    COUNT(*) FILTER (WHERE td.status = 'Accepted')::BIGINT AS status_accepted,
    COUNT(*) FILTER (WHERE td.status = 'Work In Progress')::BIGINT AS status_wip,
    COUNT(*) FILTER (WHERE td.status = 'Resolved')::BIGINT AS status_resolved,
    COUNT(*) FILTER (WHERE td.status = 'Closed')::BIGINT AS status_closed,
    COUNT(*) FILTER (WHERE td.status = 'Rejected')::BIGINT AS status_rejected,
    COUNT(*) FILTER (WHERE td.status IN ('Resolved', 'Closed'))::BIGINT AS status_completed,

    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major')::BIGINT AS major_total,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Electrical')::BIGINT AS major_electrical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Mechanical')::BIGINT AS major_mechanical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Body')::BIGINT AS major_body,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Tyre')::BIGINT AS major_tyre,

    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor')::BIGINT AS minor_total,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Electrical')::BIGINT AS minor_electrical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Mechanical')::BIGINT AS minor_mechanical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Body')::BIGINT AS minor_body,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Tyre')::BIGINT AS minor_tyre,

    (SELECT COUNT(*) FROM issue_data WHERE work_type = 'InHouse')::BIGINT AS type_in_house,
    (SELECT COUNT(*) FROM issue_data WHERE work_type = 'Outsource')::BIGINT AS type_outsource,

    COUNT(*) FILTER (WHERE td.eff_accept = 'Pending')::BIGINT AS accept_pending,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Adhered')::BIGINT AS accept_adhered,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Violated')::BIGINT AS accept_violated,

    COUNT(*) FILTER (WHERE td.eff_overall = 'Pending'  AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_wip_within,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Adhered'  AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_adhered,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Violated' AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_violated,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Pending'  AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_wip_within,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Adhered'  AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_adhered,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Violated' AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_violated,

    (SELECT COUNT(*) FROM issue_data
      JOIN ticket_data td2 ON td2.id = issue_data.ticket_id
      WHERE issue_data.rating IS NULL AND td2.status IN ('Resolved', 'Closed'))::BIGINT AS rating_pending,
    (SELECT COUNT(*) FROM issue_data WHERE rating IS NOT NULL)::BIGINT AS rating_collected,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Good')::BIGINT AS rating_good,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Ok')::BIGINT AS rating_ok,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Bad')::BIGINT AS rating_bad,
    (SELECT COALESCE(SUM(CASE WHEN rating = 'Good' THEN 2 WHEN rating = 'Ok' THEN 1 ELSE 0 END), 0)
       FROM issue_data WHERE rating IS NOT NULL)::BIGINT AS csat_score_sum,
    COUNT(*) FILTER (WHERE td.status IN ('Resolved', 'Closed'))::BIGINT AS total_completed_tickets

  FROM ticket_data td;

END;
$$;


ALTER FUNCTION public.get_maintenance_stats(start_date_input date, end_date_input date, site_filter text) OWNER TO postgres;

--
-- Name: get_outsource_invoice_summary(text[], text[], date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_outsource_invoice_summary(p_payment_status text[] DEFAULT NULL::text[], p_paid_by text[] DEFAULT NULL::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date) RETURNS TABLE(total_unpaid_payable numeric, overdue_count bigint, pending_approval_count bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    WITH paid_sums AS (
        SELECT outsource_invoice_id,
               SUM(amount_paid) AS total_paid
        FROM   outsource_invoice_payments
        GROUP  BY outsource_invoice_id
    )
    SELECT
        COALESCE(SUM(
            GREATEST(0,
                (oi.approved_amount - oi.advance_amount) - COALESCE(ps.total_paid, 0)
            )
        ) FILTER (WHERE
            COALESCE(ps.total_paid, 0) < (oi.approved_amount - oi.advance_amount)
        ), 0)                                                    AS total_unpaid_payable,

        COUNT(*) FILTER (WHERE
            oi.payby_date < CURRENT_DATE
            AND COALESCE(ps.total_paid, 0) < (oi.approved_amount - oi.advance_amount)
        )                                                        AS overdue_count,

        COUNT(*) FILTER (WHERE oi.payment_status = 'Hold')      AS pending_approval_count

    FROM  outsource_invoices     oi
    JOIN  job_cards              jc ON jc.id = oi.job_card_id
    LEFT JOIN paid_sums          ps ON ps.outsource_invoice_id = oi.id
    WHERE jc.status = 'Completed'
      AND (p_payment_status IS NULL OR oi.payment_status   = ANY(p_payment_status))
      AND (p_paid_by        IS NULL OR oi.paid_by          = ANY(p_paid_by))
      AND (p_date_from      IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to        IS NULL OR oi.date_of_activity <= p_date_to)
$$;


ALTER FUNCTION public.get_outsource_invoice_summary(p_payment_status text[], p_paid_by text[], p_date_from date, p_date_to date) OWNER TO postgres;

--
-- Name: is_maintenance_exec(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_maintenance_exec() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec', 'super_admin')
  )
$$;


ALTER FUNCTION public.is_maintenance_exec() OWNER TO postgres;

--
-- Name: is_super_admin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_super_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'super_admin'
  )
$$;


ALTER FUNCTION public.is_super_admin() OWNER TO postgres;

--
-- Name: job_card_site_accessible_to_user(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.job_cards jc
        WHERE jc.id = p_job_card_id
          AND jc.site IN (
              SELECT s.name
              FROM public.user_sites us
              JOIN public.sites s ON s.id = us.site_id
              WHERE us.user_id = auth.uid()
          )
    );
$$;


ALTER FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) OWNER TO postgres;

--
-- Name: recalculate_ticket_sla_on_status_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.recalculate_ticket_sla_on_status_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.recalculate_ticket_sla_on_status_change() OWNER TO postgres;

--
-- Name: record_scrap_disposal(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_disposal_id       uuid;
    v_item              jsonb;
    v_scrap_id          uuid;
    v_item_id           uuid;
    v_disposal_item_ids uuid[] := '{}';
    v_payment_mode      text;
    v_total_value       numeric(10,2);
    v_items_sum         numeric(10,2) := 0;
    v_scrap_ids         uuid[];
    v_bad_items         jsonb := '[]'::jsonb;
    v_dup_check         uuid[] := '{}';
BEGIN
    -- (a) Caller must be maintenance_exec or super_admin
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can record scrap disposals.',
            'details',       null
        )::text;
    END IF;

    -- (b) buyer_name must be non-empty
    IF trim(coalesce(p_header->>'buyer_name', '')) = '' THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_BUYER_NAME',
            'error_message', 'Buyer name is required.',
            'details',       null
        )::text;
    END IF;

    -- (c) payment_mode must be a valid enum value
    v_payment_mode := p_header->>'payment_mode';
    IF v_payment_mode NOT IN ('cash', 'upi', 'bank_transfer', 'cheque', 'other') THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_PAYMENT_MODE',
            'error_message', 'Invalid payment mode.',
            'details',       json_build_object('received', v_payment_mode)
        )::text;
    END IF;

    -- (d) non-cash payments require a non-empty payment_reference
    IF v_payment_mode <> 'cash'
       AND trim(coalesce(p_header->>'payment_reference', '')) = ''
    THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_PAYMENT_REFERENCE',
            'error_message', 'Payment reference is required for non-cash payments.',
            'details',       json_build_object('payment_mode', v_payment_mode)
        )::text;
    END IF;

    -- (e) receipt_photos must have at least one non-empty URL
    IF (
        SELECT count(*)
        FROM jsonb_array_elements_text(coalesce(p_header->'receipt_photos', '[]'::jsonb)) AS url
        WHERE trim(url) <> ''
    ) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_RECEIPT_PHOTO',
            'error_message', 'At least one receipt photo is required.',
            'details',       null
        )::text;
    END IF;

    -- (f) p_items must be non-empty
    IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_ITEMS_SELECTED',
            'error_message', 'At least one scrap item must be selected.',
            'details',       null
        )::text;
    END IF;

    -- (g) every scrap_inventory_id must exist and have status = 'in_storage'
    SELECT array_agg((item->>'scrap_inventory_id')::uuid)
    INTO v_scrap_ids
    FROM jsonb_array_elements(p_items) AS item;

    -- Check for non-existent or wrong-status IDs in one pass
    SELECT jsonb_agg(json_build_object('id', si.id::text, 'status', si.status::text))
    INTO v_bad_items
    FROM public.scrap_inventory si
    WHERE si.id = ANY(v_scrap_ids)
      AND si.status <> 'in_storage';

    IF (
        SELECT count(*)
        FROM unnest(v_scrap_ids) AS rid
        WHERE NOT EXISTS (SELECT 1 FROM public.scrap_inventory WHERE id = rid)
    ) > 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_SCRAP_ITEM',
            'error_message', 'One or more scrap inventory IDs do not exist.',
            'details',       json_build_object('offending_items', coalesce(v_bad_items, '[]'::jsonb))
        )::text;
    END IF;

    IF v_bad_items IS NOT NULL AND jsonb_array_length(v_bad_items) > 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_SCRAP_ITEM',
            'error_message', 'One or more scrap items are not in_storage status.',
            'details',       json_build_object('offending_items', v_bad_items)
        )::text;
    END IF;

    -- (h) no duplicate scrap_inventory_id in p_items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;
        IF v_scrap_id = ANY(v_dup_check) THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'DUPLICATE_SCRAP_ITEM',
                'error_message', 'The same scrap item appears more than once.',
                'details',       json_build_object('duplicate_id', v_scrap_id)
            )::text;
        END IF;
        v_dup_check := v_dup_check || v_scrap_id;
    END LOOP;

    -- (i) every value_allocated > 0; accumulate sum for step j
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF (v_item->>'value_allocated')::numeric <= 0 THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVALID_VALUE_ALLOCATED',
                'error_message', 'value_allocated must be greater than zero.',
                'details',       json_build_object(
                    'offending_item_id', v_item->>'scrap_inventory_id',
                    'value',             v_item->>'value_allocated'
                )
            )::text;
        END IF;
        v_items_sum := v_items_sum + (v_item->>'value_allocated')::numeric(10,2);
    END LOOP;

    -- (j) sum(value_allocated) must equal p_header.total_value
    v_total_value := (p_header->>'total_value')::numeric(10,2);
    IF round(v_items_sum, 2) <> round(v_total_value, 2) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'TOTAL_VALUE_MISMATCH',
            'error_message', 'Sum of value_allocated does not match total_value.',
            'details',       json_build_object('expected', v_items_sum, 'received', v_total_value)
        )::text;
    END IF;

    -- ── All validation passed. Execute operations atomically. ─────────────────

    -- Step 1: Insert scrap_disposal header
    INSERT INTO public.scrap_disposal (
        disposal_date,
        buyer_name,
        buyer_contact,
        payment_mode,
        payment_reference,
        total_value,
        receipt_photos,
        notes,
        recorded_by
    ) VALUES (
        (p_header->>'disposal_date')::date,
        p_header->>'buyer_name',
        p_header->>'buyer_contact',
        (p_header->>'payment_mode')::scrap_payment_mode,
        CASE WHEN v_payment_mode = 'cash' THEN NULL ELSE p_header->>'payment_reference' END,
        v_total_value,
        ARRAY(SELECT jsonb_array_elements_text(coalesce(p_header->'receipt_photos', '[]'::jsonb))),
        p_header->>'notes',
        auth.uid()
    )
    RETURNING id INTO v_disposal_id;

    -- Step 2: For each item, insert line + update scrap_inventory status
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;

        INSERT INTO public.scrap_disposal_items (
            disposal_id,
            scrap_inventory_id,
            value_allocated,
            part_name_snapshot,
            quantity_snapshot,
            unit_snapshot
        )
        SELECT
            v_disposal_id,
            si.id,
            (v_item->>'value_allocated')::numeric(10,2),
            si.part_name_snapshot,
            si.quantity_snapshot,
            si.unit_snapshot
        FROM public.scrap_inventory si
        WHERE si.id = v_scrap_id
        RETURNING id INTO v_item_id;

        v_disposal_item_ids := v_disposal_item_ids || v_item_id;

        UPDATE public.scrap_inventory
        SET
            status     = 'sold',
            updated_at = now(),
            updated_by = auth.uid()
        WHERE id = v_scrap_id;
    END LOOP;

    RETURN json_build_object(
        'success',           true,
        'disposal_id',       v_disposal_id,
        'disposal_item_ids', v_disposal_item_ids
    );
END;
$$;


ALTER FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) OWNER TO postgres;

--
-- Name: record_scrap_writeoff(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_writeoff_id        uuid;
    v_item               jsonb;
    v_scrap_id           uuid;
    v_item_id            uuid;
    v_writeoff_item_ids  uuid[] := '{}';
    v_scrap_ids          uuid[];
    v_bad_items          jsonb := '[]'::jsonb;
    v_dup_check          uuid[] := '{}';
BEGIN
    -- (a) Caller must be maintenance_exec or super_admin
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can record scrap write-offs.',
            'details',       null
        )::text;
    END IF;

    -- (b) reason must be a valid enum value
    IF (p_header->>'reason') NOT IN (
        'lost', 'damaged_unsaleable', 'hazmat_disposal',
        'stocktake_adjustment', 'donated', 'other'
    ) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_REASON',
            'error_message', 'Invalid write-off reason.',
            'details',       json_build_object('received', p_header->>'reason')
        )::text;
    END IF;

    -- (c) description must be non-empty
    IF trim(coalesce(p_header->>'description', '')) = '' THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_DESCRIPTION',
            'error_message', 'Description is required.',
            'details',       null
        )::text;
    END IF;

    -- (d) evidence_photos must have at least one non-empty URL
    IF (
        SELECT count(*)
        FROM jsonb_array_elements_text(coalesce(p_header->'evidence_photos', '[]'::jsonb)) AS url
        WHERE trim(url) <> ''
    ) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_EVIDENCE_PHOTO',
            'error_message', 'At least one evidence photo is required.',
            'details',       null
        )::text;
    END IF;

    -- (e) p_items must be non-empty
    IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_ITEMS_SELECTED',
            'error_message', 'At least one scrap item must be selected.',
            'details',       null
        )::text;
    END IF;

    -- (f) every scrap_inventory_id must exist and have status = 'in_storage'
    SELECT array_agg((item->>'scrap_inventory_id')::uuid)
    INTO v_scrap_ids
    FROM jsonb_array_elements(p_items) AS item;

    IF (
        SELECT count(*)
        FROM unnest(v_scrap_ids) AS rid
        WHERE NOT EXISTS (SELECT 1 FROM public.scrap_inventory WHERE id = rid)
    ) > 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_SCRAP_ITEM',
            'error_message', 'One or more scrap inventory IDs do not exist.',
            'details',       json_build_object('offending_items', coalesce(v_bad_items, '[]'::jsonb))
        )::text;
    END IF;

    SELECT jsonb_agg(json_build_object('id', si.id::text, 'status', si.status::text))
    INTO v_bad_items
    FROM public.scrap_inventory si
    WHERE si.id = ANY(v_scrap_ids)
      AND si.status <> 'in_storage';

    IF v_bad_items IS NOT NULL AND jsonb_array_length(v_bad_items) > 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_SCRAP_ITEM',
            'error_message', 'One or more scrap items are not in_storage status.',
            'details',       json_build_object('offending_items', v_bad_items)
        )::text;
    END IF;

    -- (g) no duplicate scrap_inventory_id in p_items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;
        IF v_scrap_id = ANY(v_dup_check) THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'DUPLICATE_SCRAP_ITEM',
                'error_message', 'The same scrap item appears more than once.',
                'details',       json_build_object('duplicate_id', v_scrap_id)
            )::text;
        END IF;
        v_dup_check := v_dup_check || v_scrap_id;
    END LOOP;

    -- ── All validation passed. Execute operations atomically. ─────────────────

    -- Step 1: Insert scrap_writeoff header
    INSERT INTO public.scrap_writeoff (
        writeoff_date,
        reason,
        description,
        evidence_photos,
        notes,
        recorded_by
    ) VALUES (
        (p_header->>'writeoff_date')::date,
        (p_header->>'reason')::scrap_writeoff_reason,
        p_header->>'description',
        ARRAY(SELECT jsonb_array_elements_text(coalesce(p_header->'evidence_photos', '[]'::jsonb))),
        p_header->>'notes',
        auth.uid()
    )
    RETURNING id INTO v_writeoff_id;

    -- Step 2: For each item, insert line + update scrap_inventory status
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;

        INSERT INTO public.scrap_writeoff_items (
            writeoff_id,
            scrap_inventory_id,
            part_name_snapshot,
            quantity_snapshot,
            unit_snapshot
        )
        SELECT
            v_writeoff_id,
            si.id,
            si.part_name_snapshot,
            si.quantity_snapshot,
            si.unit_snapshot
        FROM public.scrap_inventory si
        WHERE si.id = v_scrap_id
        RETURNING id INTO v_item_id;

        v_writeoff_item_ids := v_writeoff_item_ids || v_item_id;

        UPDATE public.scrap_inventory
        SET
            status     = 'written_off',
            updated_at = now(),
            updated_by = auth.uid()
        WHERE id = v_scrap_id;
    END LOOP;

    RETURN json_build_object(
        'success',            true,
        'writeoff_id',        v_writeoff_id,
        'writeoff_item_ids',  v_writeoff_item_ids
    );
END;
$$;


ALTER FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) OWNER TO postgres;

--
-- Name: restore_part_to_inventory(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.restore_part_to_inventory() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card_type text;
BEGIN
    SELECT jc.type INTO v_job_card_type
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  i.id = OLD.issue_id;

    IF v_job_card_type = 'Outsource' THEN
        RETURN OLD;
    END IF;

    UPDATE public.parts
    SET    quantity_in_stock = quantity_in_stock + OLD.quantity_used
    WHERE  id = OLD.part_id;

    RETURN OLD;
END;
$$;


ALTER FUNCTION public.restore_part_to_inventory() OWNER TO postgres;

--
-- Name: reverse_part_inventory_on_delete(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.reverse_part_inventory_on_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
    UPDATE parts
    SET quantity_in_stock = quantity_in_stock - OLD.quantity
    WHERE id = OLD.part_id;
    RETURN OLD;
END;
$$;


ALTER FUNCTION public.reverse_part_inventory_on_delete() OWNER TO postgres;

--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.set_updated_at() OWNER TO postgres;

--
-- Name: stamp_rejected_at_and_evaluate_acceptance_sla(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_sla_days      INT;
  v_deadline      DATE;
  v_first_issue   TIMESTAMPTZ;
BEGIN
  -- Only act when status transitions TO Rejected
  IF NEW.status = 'Rejected' AND (OLD.status IS DISTINCT FROM 'Rejected') THEN

    -- Stamp the rejection timestamp
    NEW.rejected_at := NOW();

    -- Only evaluate acceptance SLA if it is still Pending (not already resolved by first-issue trigger)
    IF NEW.acceptance_sla_status = 'Pending' THEN

      SELECT COALESCE(value::int, 2)
        INTO v_sla_days
        FROM system_settings
       WHERE key = 'acceptance_sla_days';

      v_deadline := add_working_days(NEW.created_at::date, COALESCE(v_sla_days, 2));

      -- Check whether any issue was ever created
      SELECT MIN(created_at)
        INTO v_first_issue
        FROM issues
       WHERE ticket_id = NEW.id;

      IF v_first_issue IS NOT NULL THEN
        -- First issue exists; evaluate against its creation time
        IF v_first_issue::date <= v_deadline THEN
          NEW.acceptance_sla_status := 'Adhered';
        ELSE
          NEW.acceptance_sla_status := 'Violated';
        END IF;
      ELSE
        -- No issues ever created; evaluate against rejection time (NOW())
        IF NOW()::date <= v_deadline THEN
          NEW.acceptance_sla_status := 'Adhered';
        ELSE
          NEW.acceptance_sla_status := 'Violated';
        END IF;
      END IF;

    END IF;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla() OWNER TO postgres;

--
-- Name: trg_set_acceptance_sla_on_first_issue(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_set_acceptance_sla_on_first_issue() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_prior_count INT;
BEGIN
    SELECT COUNT(*) INTO v_prior_count
    FROM issues WHERE ticket_id = NEW.ticket_id AND id != NEW.id;
    IF v_prior_count = 0 THEN
        UPDATE tickets
        SET acceptance_sla_status = evaluate_acceptance_sla(NEW.ticket_id, NEW.created_at)
        WHERE id = NEW.ticket_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_set_acceptance_sla_on_first_issue() OWNER TO postgres;

--
-- Name: update_ticket_sla(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_ticket_sla() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Calculate SLA days and end date when impact is assigned
  IF NEW.impact IS NOT NULL AND NEW.category IS NOT NULL THEN
    NEW.sla_days := calculate_sla_days(NEW.impact, NEW.category);
    NEW.sla_end_date := NEW.created_at::DATE + NEW.sla_days;
  END IF;

  -- Update assignment SLA status
  IF NEW.assigned_date IS NOT NULL THEN
    IF (NEW.assigned_date - NEW.created_at::DATE) <= 1 THEN
      NEW.assignment_sla_status := 'Adhered';
    ELSE
      NEW.assignment_sla_status := 'Violated';
    END IF;
  ELSIF (CURRENT_DATE - NEW.created_at::DATE) > 1 THEN
    NEW.assignment_sla_status := 'Violated';
  END IF;

  -- Update completion SLA status
  IF NEW.status = 'Completed' AND NEW.completed_date IS NOT NULL AND NEW.sla_end_date IS NOT NULL THEN
    IF NEW.completed_date <= NEW.sla_end_date THEN
      NEW.completion_sla_status := 'Adhered';
    ELSE
      NEW.completion_sla_status := 'Violated';
    END IF;

    -- Calculate TAT
    NEW.tat_days := NEW.completed_date - NEW.created_at::DATE;
  ELSIF NEW.sla_end_date IS NOT NULL AND CURRENT_DATE > NEW.sla_end_date AND NEW.status != 'Completed' THEN
    NEW.completion_sla_status := 'Violated';
  END IF;

  -- Update CSAT score based on rating
  IF NEW.rating IS NOT NULL THEN
    NEW.csat_score := CASE
      WHEN NEW.rating = 'Good' THEN 2
      WHEN NEW.rating = 'Ok' THEN 1
      WHEN NEW.rating = 'Bad' THEN 0
    END;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_ticket_sla() OWNER TO postgres;

--
-- Name: update_ticket_status_on_issue_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_ticket_status_on_issue_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  ticket_status TEXT;
  total_issues INTEGER;
  done_issues INTEGER;
  rated_issues INTEGER;
  has_job_cards BOOLEAN;
BEGIN
  SELECT status INTO ticket_status FROM tickets WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  
  SELECT COUNT(*), 
         COUNT(*) FILTER (WHERE status = 'Done'),
         COUNT(*) FILTER (WHERE rating IS NOT NULL)
  INTO total_issues, done_issues, rated_issues
  FROM issues WHERE ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  
  SELECT EXISTS(
    SELECT 1 FROM issues i 
    WHERE i.ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id) 
    AND i.job_card_id IS NOT NULL
  ) INTO has_job_cards;
  
  -- New → Accepted (on issue creation)
  IF ticket_status = 'New' AND total_issues > 0 AND TG_OP = 'INSERT' THEN
    UPDATE tickets SET status = 'Accepted' WHERE id = NEW.ticket_id;
  END IF;
  
  -- Accepted → Work In Progress (on job card assignment)
  IF ticket_status = 'Accepted' AND has_job_cards THEN
    UPDATE tickets SET status = 'Work In Progress' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  
  -- Work In Progress → Resolved (all issues done)
  IF ticket_status = 'Work In Progress' AND total_issues > 0 AND done_issues = total_issues THEN
    UPDATE tickets SET status = 'Resolved' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  
  -- Resolved → Closed (all issues have rating/feedback)
  IF ticket_status = 'Resolved' AND total_issues > 0 AND rated_issues = total_issues THEN
    UPDATE tickets SET status = 'Closed' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION public.update_ticket_status_on_issue_change() OWNER TO postgres;

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    table_name text NOT NULL,
    record_id uuid NOT NULL,
    action text NOT NULL,
    old_data jsonb,
    new_data jsonb,
    changed_fields text[],
    performed_by uuid,
    performed_at timestamp with time zone DEFAULT now(),
    CONSTRAINT audit_logs_action_check CHECK ((action = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


ALTER TABLE public.audit_logs OWNER TO postgres;

--
-- Name: finance_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.finance_entries (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    work_type text NOT NULL,
    activity_date date NOT NULL,
    vehicle_number text,
    job_sheet_id text,
    ticket_id uuid,
    site text,
    vendor_name text,
    vendor_contact text,
    work_description text NOT NULL,
    approved_amount numeric,
    invoice_number text,
    km_reading integer,
    work_inspected_by text,
    payable_amount numeric,
    advance_amount numeric,
    invoice_value numeric,
    paid_amount numeric,
    payment_date date,
    payment_status text DEFAULT 'Pending'::text,
    transaction_details text,
    payment_via text,
    bill_attachment text,
    approval_screenshot text,
    job_card_upload text,
    created_by_user_id uuid NOT NULL,
    accounting_status text DEFAULT 'Pending'::text,
    CONSTRAINT finance_entries_accounting_status_check CHECK ((accounting_status = ANY (ARRAY['Pending'::text, 'Processed'::text, 'Closed'::text]))),
    CONSTRAINT finance_entries_payment_status_check CHECK ((payment_status = ANY (ARRAY['Pending'::text, 'Partial'::text, 'Paid'::text]))),
    CONSTRAINT finance_entries_work_type_check CHECK ((work_type = ANY (ARRAY['Spare Purchases'::text, 'Outsourced Work'::text, 'Job Card'::text])))
);


ALTER TABLE public.finance_entries OWNER TO postgres;

--
-- Name: holidays; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.holidays (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    date date NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.holidays OWNER TO postgres;

--
-- Name: issue_parts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.issue_parts (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    issue_id uuid NOT NULL,
    part_id uuid NOT NULL,
    quantity_used numeric(10,2) NOT NULL,
    added_by uuid,
    added_at timestamp without time zone DEFAULT now(),
    outsource_part_disposition public.outsource_part_disposition,
    outsource_vendor_credit_amount numeric(10,2),
    CONSTRAINT issue_parts_outsource_credit_consistency CHECK (((outsource_part_disposition = 'retained_by_vendor_with_credit'::public.outsource_part_disposition) = (outsource_vendor_credit_amount IS NOT NULL))),
    CONSTRAINT issue_parts_quantity_used_check CHECK ((quantity_used > (0)::numeric))
);


ALTER TABLE public.issue_parts OWNER TO postgres;

--
-- Name: issues; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.issues (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    issue_number text,
    created_at timestamp without time zone DEFAULT now(),
    ticket_id uuid NOT NULL,
    job_card_id uuid,
    description text NOT NULL,
    category public.issue_category NOT NULL,
    severity public.issue_severity DEFAULT 'Minor'::public.issue_severity,
    work_type public.work_type_enum,
    status public.issue_status DEFAULT 'Open'::public.issue_status,
    sla_days integer,
    sla_end_date date,
    sla_status public.sla_status_enum DEFAULT 'Pending'::public.sla_status_enum,
    rating public.rating_enum,
    rating_remarks text,
    rated_at timestamp without time zone,
    labour_hours numeric(5,2),
    CONSTRAINT check_rated_at_after_created CHECK (((rated_at IS NULL) OR (rated_at >= created_at)))
);


ALTER TABLE public.issues OWNER TO postgres;

--
-- Name: job_cards; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.job_cards (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    job_card_number integer NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    type public.work_type_enum NOT NULL,
    assigned_mechanic_id uuid,
    vehicle_number text NOT NULL,
    site text NOT NULL,
    status public.job_card_status DEFAULT 'Open'::public.job_card_status,
    completed_at timestamp without time zone,
    remarks text,
    supplier_id uuid,
    invoice_url text,
    odometer integer,
    CONSTRAINT check_completed_after_created CHECK (((completed_at IS NULL) OR (completed_at >= created_at))),
    CONSTRAINT job_cards_odometer_check CHECK (((odometer IS NULL) OR (odometer >= 0))),
    CONSTRAINT outsource_completion_requires_invoice CHECK (((status <> 'Completed'::public.job_card_status) OR (type <> 'Outsource'::public.work_type_enum) OR (invoice_url IS NOT NULL)))
);


ALTER TABLE public.job_cards OWNER TO postgres;

--
-- Name: job_cards_job_card_number_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.job_cards ALTER COLUMN job_card_number ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.job_cards_job_card_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tickets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tickets (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    ticket_number integer NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    site text NOT NULL,
    vehicle_number text NOT NULL,
    supervisor_name text NOT NULL,
    supervisor_id text NOT NULL,
    supervisor_contact text,
    photos text[],
    status public.ticket_status_new DEFAULT 'New'::public.ticket_status_new,
    tat_days integer,
    is_duplicate boolean DEFAULT false,
    merged_into_ticket_id uuid,
    created_by_user_id uuid NOT NULL,
    rating_comment text,
    rated_at timestamp with time zone,
    initial_remarks text,
    rejected_reason text,
    resolved_at timestamp without time zone,
    closed_at timestamp without time zone,
    final_sla_end_date date,
    overall_sla_status public.sla_status_enum,
    rejection_reason text,
    rejection_comment text,
    acceptance_sla_status public.sla_status_enum DEFAULT 'Pending'::public.sla_status_enum,
    rejected_at timestamp with time zone,
    CONSTRAINT check_closed_after_resolved CHECK (((closed_at IS NULL) OR (resolved_at IS NULL) OR (closed_at >= resolved_at))),
    CONSTRAINT check_resolved_after_created CHECK (((resolved_at IS NULL) OR (resolved_at >= created_at)))
);


ALTER TABLE public.tickets OWNER TO postgres;

--
-- Name: maintenance_dashboard_stats; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.maintenance_dashboard_stats AS
 SELECT count(*) AS total_tickets,
    count(*) FILTER (WHERE ((status)::text = 'New'::text)) AS pending_tickets,
    count(*) FILTER (WHERE ((overall_sla_status)::text = 'Violated'::text)) AS completion_sla_violated,
    ( SELECT count(*) AS count
           FROM public.job_cards
          WHERE ((job_cards.type)::text = 'InHouse'::text)) AS inhouse_count,
    ( SELECT count(*) AS count
           FROM public.job_cards
          WHERE ((job_cards.type)::text = 'Outsource'::text)) AS outsource_count,
    COALESCE(avg(EXTRACT(day FROM (
        CASE
            WHEN ((status)::text = 'Resolved'::text) THEN (resolved_at)::timestamp with time zone
            ELSE now()
        END - (created_at)::timestamp with time zone))), (0)::numeric) AS avg_tat_days
   FROM public.tickets;


ALTER VIEW public.maintenance_dashboard_stats OWNER TO postgres;

--
-- Name: outsource_invoice_payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.outsource_invoice_payments (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    outsource_invoice_id uuid NOT NULL,
    paid_on date NOT NULL,
    amount_paid numeric(12,2) NOT NULL,
    notes text,
    attachment_urls text[] DEFAULT '{}'::text[] NOT NULL,
    recorded_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.outsource_invoice_payments OWNER TO postgres;

--
-- Name: outsource_invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.outsource_invoices (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    job_card_id uuid,
    date_of_activity date,
    invoice_no text,
    paid_by text,
    invoice_value numeric(12,2),
    approved_amount numeric(12,2),
    advance_amount numeric(12,2),
    payment_status text,
    payby_date date,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT outsource_invoices_paid_by_check CHECK ((paid_by = ANY (ARRAY['Accounts'::text, 'Nithin'::text, 'Manjunath'::text]))),
    CONSTRAINT outsource_invoices_payment_status_check CHECK ((payment_status = ANY (ARRAY['Approved'::text, 'Hold'::text, 'Reject'::text])))
);


ALTER TABLE public.outsource_invoices OWNER TO postgres;

--
-- Name: part_units; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.part_units (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    sort_order integer DEFAULT 0,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.part_units OWNER TO postgres;

--
-- Name: parts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.parts (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    part_number text,
    unit text DEFAULT 'pcs'::text,
    quantity_in_stock numeric(10,2) DEFAULT 0 NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    created_via text DEFAULT 'manual'::text NOT NULL,
    CONSTRAINT parts_created_via_check CHECK ((created_via = ANY (ARRAY['manual'::text, 'outsource_jobcard'::text])))
);


ALTER TABLE public.parts OWNER TO postgres;

--
-- Name: purchase_invoice_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchase_invoice_items (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    invoice_id uuid NOT NULL,
    part_id uuid NOT NULL,
    quantity numeric(10,2) NOT NULL,
    unit_price numeric(12,2) NOT NULL,
    gst_rate numeric(5,2) DEFAULT 0 NOT NULL,
    line_total numeric(12,2) GENERATED ALWAYS AS (round(((quantity * unit_price) * ((1)::numeric + (gst_rate / 100.0))), 2)) STORED,
    CONSTRAINT purchase_invoice_items_quantity_check CHECK ((quantity > (0)::numeric)),
    CONSTRAINT purchase_invoice_items_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


ALTER TABLE public.purchase_invoice_items OWNER TO postgres;

--
-- Name: purchase_invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchase_invoices (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    invoice_number text NOT NULL,
    supplier_name text NOT NULL,
    invoice_date date NOT NULL,
    total_amount numeric(12,2),
    notes text,
    created_by uuid,
    created_at timestamp without time zone DEFAULT now(),
    invoice_file_url text
);


ALTER TABLE public.purchase_invoices OWNER TO postgres;

--
-- Name: scrap_disposal; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_disposal (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    disposal_date date NOT NULL,
    buyer_name text NOT NULL,
    buyer_contact text,
    payment_mode public.scrap_payment_mode NOT NULL,
    payment_reference text,
    total_value numeric(10,2) NOT NULL,
    receipt_photos text[] DEFAULT '{}'::text[] NOT NULL,
    notes text,
    recorded_by uuid NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT scrap_disposal_payment_reference_consistency CHECK ((((payment_mode = 'cash'::public.scrap_payment_mode) AND (payment_reference IS NULL)) OR ((payment_mode <> 'cash'::public.scrap_payment_mode) AND (payment_reference IS NOT NULL))))
);


ALTER TABLE public.scrap_disposal OWNER TO postgres;

--
-- Name: scrap_disposal_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_disposal_items (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    disposal_id uuid NOT NULL,
    scrap_inventory_id uuid NOT NULL,
    value_allocated numeric(10,2) NOT NULL,
    part_name_snapshot text NOT NULL,
    quantity_snapshot numeric(10,2) NOT NULL,
    unit_snapshot text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT scrap_disposal_items_value_allocated_positive CHECK ((value_allocated > (0)::numeric))
);


ALTER TABLE public.scrap_disposal_items OWNER TO postgres;

--
-- Name: scrap_excluded_parts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_excluded_parts (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    source_job_card_id uuid NOT NULL,
    source_issue_id uuid NOT NULL,
    source_issue_part_id uuid,
    part_id_snapshot uuid,
    part_name_snapshot text NOT NULL,
    quantity_snapshot numeric(10,2) NOT NULL,
    reason public.scrap_exclusion_reason NOT NULL,
    notes text,
    excluded_by uuid NOT NULL,
    excluded_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.scrap_excluded_parts OWNER TO postgres;

--
-- Name: scrap_inventory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_inventory (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    source_ticket_id uuid NOT NULL,
    source_job_card_id uuid NOT NULL,
    source_issue_id uuid NOT NULL,
    source_issue_part_id uuid,
    source_vehicle_number text NOT NULL,
    part_id_snapshot uuid,
    part_name_snapshot text NOT NULL,
    part_number_snapshot text,
    quantity_snapshot numeric(10,2) NOT NULL,
    unit_snapshot text NOT NULL,
    description text,
    notes text,
    estimated_value numeric(10,2),
    photos text[] DEFAULT '{}'::text[] NOT NULL,
    status public.scrap_item_status DEFAULT 'in_storage'::public.scrap_item_status NOT NULL,
    received_by uuid,
    received_at timestamp with time zone,
    current_location text,
    outsource_part_disposition_snapshot public.outsource_part_disposition,
    outsource_vendor_credit_amount_snapshot numeric(10,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid
);


ALTER TABLE public.scrap_inventory OWNER TO postgres;

--
-- Name: scrap_writeoff; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_writeoff (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    writeoff_date date NOT NULL,
    reason public.scrap_writeoff_reason NOT NULL,
    description text NOT NULL,
    evidence_photos text[] DEFAULT '{}'::text[] NOT NULL,
    notes text,
    recorded_by uuid NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.scrap_writeoff OWNER TO postgres;

--
-- Name: scrap_writeoff_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scrap_writeoff_items (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    writeoff_id uuid NOT NULL,
    scrap_inventory_id uuid NOT NULL,
    part_name_snapshot text NOT NULL,
    quantity_snapshot numeric(10,2) NOT NULL,
    unit_snapshot text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.scrap_writeoff_items OWNER TO postgres;

--
-- Name: sites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sites (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.sites OWNER TO postgres;

--
-- Name: sla_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sla_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ticket_id uuid,
    event_type text NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    metadata jsonb DEFAULT '{}'::jsonb,
    CONSTRAINT sla_events_event_type_check CHECK ((event_type = ANY (ARRAY['CREATED'::text, 'ASSIGNED'::text, 'COMPLETED'::text, 'STATUS_CHANGE'::text, 'REJECTED'::text, 'COMMENT'::text])))
);


ALTER TABLE public.sla_events OWNER TO postgres;

--
-- Name: sla_rules; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sla_rules (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    impact text NOT NULL,
    category text NOT NULL,
    days integer DEFAULT 3 NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.sla_rules OWNER TO postgres;

--
-- Name: sla_rules_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sla_rules_config (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    category public.issue_category NOT NULL,
    severity public.issue_severity NOT NULL,
    sla_days integer NOT NULL
);


ALTER TABLE public.sla_rules_config OWNER TO postgres;

--
-- Name: supervisor_dashboard_stats; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.supervisor_dashboard_stats AS
 SELECT t.site,
    count(*) FILTER (WHERE ((t.status)::text = 'New'::text)) AS pending_count,
    count(*) FILTER (WHERE ((t.status)::text = 'Accepted'::text)) AS accepted_count,
    count(*) FILTER (WHERE ((t.status)::text = 'Resolved'::text)) AS completed_count,
    count(*) FILTER (WHERE ((t.status)::text = 'Rejected'::text)) AS rejected_count,
    count(*) FILTER (WHERE ((t.overall_sla_status)::text = 'Violated'::text)) AS sla_violated_count,
    COALESCE(avg(
        CASE
            WHEN ((i.rating)::text = 'Good'::text) THEN 2
            WHEN ((i.rating)::text = 'Ok'::text) THEN 1
            WHEN ((i.rating)::text = 'Bad'::text) THEN 0
            ELSE NULL::integer
        END), (0)::numeric) AS avg_csat_score
   FROM (public.tickets t
     LEFT JOIN public.issues i ON ((i.ticket_id = t.id)))
  GROUP BY t.site;


ALTER VIEW public.supervisor_dashboard_stats OWNER TO postgres;

--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    status text DEFAULT 'pending'::text,
    email text,
    entity_name text NOT NULL,
    entity_type text,
    entity_type_other text,
    registered_office_address text NOT NULL,
    nature_of_work text NOT NULL,
    workshop_address text,
    owner_name text NOT NULL,
    owner_contact text NOT NULL,
    owner_email text,
    accounts_contact_name text,
    accounts_contact_number text,
    accounts_email text,
    sales_contact_name text,
    sales_contact_number text,
    sales_email text,
    po_communication_emails text,
    pan_number text,
    pan_copy_url text,
    gstin text,
    gst_registration_type text,
    gst_certificate_url text,
    msme_udyam_number text,
    udyam_certificate_url text,
    pf_registration_number text,
    pf_certificate_url text,
    esi_registration_number text,
    esi_certificate_url text,
    labour_license_number text,
    bank_name text,
    bank_branch text,
    account_holder_name text,
    account_number text,
    ifsc_code text,
    account_type text,
    cancelled_cheque_url text,
    years_of_experience text,
    major_clients text,
    skilled_manpower_available boolean,
    brand_spares_usage text,
    payment_terms_days text,
    submitted_by text,
    created_via text DEFAULT 'registration'::text NOT NULL,
    created_by uuid,
    CONSTRAINT suppliers_created_via_check CHECK ((created_via = ANY (ARRAY['registration'::text, 'quick_add'::text]))),
    CONSTRAINT suppliers_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


ALTER TABLE public.suppliers OWNER TO postgres;

--
-- Name: system_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.system_settings (
    key text NOT NULL,
    value text NOT NULL,
    description text,
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.system_settings OWNER TO postgres;

--
-- Name: tickets_ticket_number_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tickets ALTER COLUMN ticket_number ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.tickets_ticket_number_seq
    START WITH 1434
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: user_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_settings (
    user_id uuid NOT NULL,
    notify_daily_digest boolean DEFAULT false,
    digest_preferences jsonb DEFAULT '{"created_24h": true, "rejected_24h": true, "sla_expiring": true}'::jsonb,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
);


ALTER TABLE public.user_settings OWNER TO postgres;

--
-- Name: user_sites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_sites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    site_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.user_sites OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    email text NOT NULL,
    name text NOT NULL,
    employee_id text,
    contact text,
    role text NOT NULL,
    site text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT users_role_check CHECK ((role = ANY (ARRAY['supervisor'::text, 'maintenance_exec'::text, 'finance'::text, 'mechanic'::text, 'electrician'::text, 'super_admin'::text])))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: vehicle_sites; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vehicle_sites (
    vehicle_id uuid NOT NULL,
    site_name text NOT NULL
);


ALTER TABLE public.vehicle_sites OWNER TO postgres;

--
-- Name: vehicles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.vehicles (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    registration_number text NOT NULL,
    type text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT now(),
    make text,
    model text,
    year integer,
    notes text,
    raw_data jsonb
);


ALTER TABLE public.vehicles OWNER TO postgres;

--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: finance_entries finance_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finance_entries
    ADD CONSTRAINT finance_entries_pkey PRIMARY KEY (id);


--
-- Name: holidays holidays_date_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.holidays
    ADD CONSTRAINT holidays_date_key UNIQUE (date);


--
-- Name: holidays holidays_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.holidays
    ADD CONSTRAINT holidays_pkey PRIMARY KEY (id);


--
-- Name: issue_parts issue_parts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issue_parts
    ADD CONSTRAINT issue_parts_pkey PRIMARY KEY (id);


--
-- Name: issues issues_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issues
    ADD CONSTRAINT issues_pkey PRIMARY KEY (id);


--
-- Name: job_cards job_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.job_cards
    ADD CONSTRAINT job_cards_pkey PRIMARY KEY (id);


--
-- Name: outsource_invoice_payments outsource_invoice_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoice_payments
    ADD CONSTRAINT outsource_invoice_payments_pkey PRIMARY KEY (id);


--
-- Name: outsource_invoices outsource_invoices_job_card_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoices
    ADD CONSTRAINT outsource_invoices_job_card_id_key UNIQUE (job_card_id);


--
-- Name: outsource_invoices outsource_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoices
    ADD CONSTRAINT outsource_invoices_pkey PRIMARY KEY (id);


--
-- Name: part_units part_units_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.part_units
    ADD CONSTRAINT part_units_name_key UNIQUE (name);


--
-- Name: part_units part_units_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.part_units
    ADD CONSTRAINT part_units_pkey PRIMARY KEY (id);


--
-- Name: parts parts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.parts
    ADD CONSTRAINT parts_pkey PRIMARY KEY (id);


--
-- Name: purchase_invoice_items purchase_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_pkey PRIMARY KEY (id);


--
-- Name: purchase_invoices purchase_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoices
    ADD CONSTRAINT purchase_invoices_pkey PRIMARY KEY (id);


--
-- Name: scrap_disposal_items scrap_disposal_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal_items
    ADD CONSTRAINT scrap_disposal_items_pkey PRIMARY KEY (id);


--
-- Name: scrap_disposal_items scrap_disposal_items_unique_item_per_disposal; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal_items
    ADD CONSTRAINT scrap_disposal_items_unique_item_per_disposal UNIQUE (disposal_id, scrap_inventory_id);


--
-- Name: scrap_disposal scrap_disposal_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal
    ADD CONSTRAINT scrap_disposal_pkey PRIMARY KEY (id);


--
-- Name: scrap_excluded_parts scrap_excluded_parts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_pkey PRIMARY KEY (id);


--
-- Name: scrap_inventory scrap_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_pkey PRIMARY KEY (id);


--
-- Name: scrap_writeoff_items scrap_writeoff_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff_items
    ADD CONSTRAINT scrap_writeoff_items_pkey PRIMARY KEY (id);


--
-- Name: scrap_writeoff_items scrap_writeoff_items_unique_item_per_writeoff; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff_items
    ADD CONSTRAINT scrap_writeoff_items_unique_item_per_writeoff UNIQUE (writeoff_id, scrap_inventory_id);


--
-- Name: scrap_writeoff scrap_writeoff_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff
    ADD CONSTRAINT scrap_writeoff_pkey PRIMARY KEY (id);


--
-- Name: sites sites_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT sites_name_key UNIQUE (name);


--
-- Name: sites sites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT sites_pkey PRIMARY KEY (id);


--
-- Name: sla_events sla_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_events
    ADD CONSTRAINT sla_events_pkey PRIMARY KEY (id);


--
-- Name: sla_rules_config sla_rules_config_category_severity_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_rules_config
    ADD CONSTRAINT sla_rules_config_category_severity_key UNIQUE (category, severity);


--
-- Name: sla_rules_config sla_rules_config_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_rules_config
    ADD CONSTRAINT sla_rules_config_pkey PRIMARY KEY (id);


--
-- Name: sla_rules sla_rules_impact_category_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_rules
    ADD CONSTRAINT sla_rules_impact_category_key UNIQUE (impact, category);


--
-- Name: sla_rules sla_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_rules
    ADD CONSTRAINT sla_rules_pkey PRIMARY KEY (id);


--
-- Name: suppliers suppliers_pan_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pan_number_key UNIQUE (pan_number);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_pkey PRIMARY KEY (key);


--
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (id);


--
-- Name: user_settings user_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_settings
    ADD CONSTRAINT user_settings_pkey PRIMARY KEY (user_id);


--
-- Name: user_sites user_sites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sites
    ADD CONSTRAINT user_sites_pkey PRIMARY KEY (id);


--
-- Name: user_sites user_sites_user_id_site_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sites
    ADD CONSTRAINT user_sites_user_id_site_id_key UNIQUE (user_id, site_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: vehicle_sites vehicle_sites_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle_sites
    ADD CONSTRAINT vehicle_sites_pkey PRIMARY KEY (vehicle_id, site_name);


--
-- Name: vehicles vehicles_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_number_key UNIQUE (registration_number);


--
-- Name: vehicles vehicles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_pkey PRIMARY KEY (id);


--
-- Name: idx_finance_job_sheet_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_finance_job_sheet_id ON public.finance_entries USING btree (job_sheet_id);


--
-- Name: idx_finance_site; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_finance_site ON public.finance_entries USING btree (site);


--
-- Name: idx_finance_ticket_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_finance_ticket_id ON public.finance_entries USING btree (ticket_id);


--
-- Name: idx_issues_job_card_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_issues_job_card_id ON public.issues USING btree (job_card_id);


--
-- Name: idx_issues_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_issues_status ON public.issues USING btree (status);


--
-- Name: idx_issues_ticket_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_issues_ticket_id ON public.issues USING btree (ticket_id);


--
-- Name: idx_job_cards_mechanic; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_job_cards_mechanic ON public.job_cards USING btree (assigned_mechanic_id);


--
-- Name: idx_job_cards_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_job_cards_status ON public.job_cards USING btree (status);


--
-- Name: idx_scrap_disposal_disposal_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_disposal_disposal_date ON public.scrap_disposal USING btree (disposal_date DESC);


--
-- Name: idx_scrap_disposal_items_disposal_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_disposal_items_disposal_id ON public.scrap_disposal_items USING btree (disposal_id);


--
-- Name: idx_scrap_disposal_items_scrap_inventory_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_disposal_items_scrap_inventory_id ON public.scrap_disposal_items USING btree (scrap_inventory_id);


--
-- Name: idx_scrap_disposal_recorded_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_disposal_recorded_by ON public.scrap_disposal USING btree (recorded_by);


--
-- Name: idx_scrap_excluded_parts_issue_part_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_excluded_parts_issue_part_id ON public.scrap_excluded_parts USING btree (source_issue_part_id);


--
-- Name: idx_scrap_excluded_parts_job_card_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_excluded_parts_job_card_id ON public.scrap_excluded_parts USING btree (source_job_card_id);


--
-- Name: idx_scrap_inventory_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_inventory_created_at ON public.scrap_inventory USING btree (created_at DESC);


--
-- Name: idx_scrap_inventory_issue_part_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_inventory_issue_part_id ON public.scrap_inventory USING btree (source_issue_part_id);


--
-- Name: idx_scrap_inventory_job_card_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_inventory_job_card_id ON public.scrap_inventory USING btree (source_job_card_id);


--
-- Name: idx_scrap_inventory_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_inventory_status ON public.scrap_inventory USING btree (status);


--
-- Name: idx_scrap_inventory_ticket_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_inventory_ticket_id ON public.scrap_inventory USING btree (source_ticket_id);


--
-- Name: idx_scrap_writeoff_items_scrap_inventory_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_writeoff_items_scrap_inventory_id ON public.scrap_writeoff_items USING btree (scrap_inventory_id);


--
-- Name: idx_scrap_writeoff_items_writeoff_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_writeoff_items_writeoff_id ON public.scrap_writeoff_items USING btree (writeoff_id);


--
-- Name: idx_scrap_writeoff_recorded_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_writeoff_recorded_by ON public.scrap_writeoff USING btree (recorded_by);


--
-- Name: idx_scrap_writeoff_writeoff_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scrap_writeoff_writeoff_date ON public.scrap_writeoff USING btree (writeoff_date DESC);


--
-- Name: idx_sla_events_ticket_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_sla_events_ticket_id ON public.sla_events USING btree (ticket_id);


--
-- Name: idx_tickets_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_created_at ON public.tickets USING btree (created_at DESC);


--
-- Name: idx_tickets_created_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_created_by ON public.tickets USING btree (created_by_user_id);


--
-- Name: idx_tickets_site; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_site ON public.tickets USING btree (site);


--
-- Name: idx_tickets_site_new; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_site_new ON public.tickets USING btree (site);


--
-- Name: idx_tickets_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_status ON public.tickets USING btree (status);


--
-- Name: idx_tickets_status_new; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_status_new ON public.tickets USING btree (status);


--
-- Name: idx_tickets_vehicle_number; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_tickets_vehicle_number ON public.tickets USING btree (vehicle_number);


--
-- Name: outsource_invoice_payments_invoice_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX outsource_invoice_payments_invoice_id_idx ON public.outsource_invoice_payments USING btree (outsource_invoice_id);


--
-- Name: outsource_invoices_job_card_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX outsource_invoices_job_card_id_idx ON public.outsource_invoices USING btree (job_card_id);


--
-- Name: outsource_invoices_paid_by_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX outsource_invoices_paid_by_idx ON public.outsource_invoices USING btree (paid_by);


--
-- Name: outsource_invoices_payby_date_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX outsource_invoices_payby_date_idx ON public.outsource_invoices USING btree (payby_date);


--
-- Name: outsource_invoices_payment_status_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX outsource_invoices_payment_status_idx ON public.outsource_invoices USING btree (payment_status);


--
-- Name: outsource_invoices outsource_invoices_set_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER outsource_invoices_set_updated_at BEFORE UPDATE ON public.outsource_invoices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: issues trg_acceptance_sla_on_first_issue; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_acceptance_sla_on_first_issue AFTER INSERT ON public.issues FOR EACH ROW EXECUTE FUNCTION public.trg_set_acceptance_sla_on_first_issue();


--
-- Name: issues trg_generate_issue_number; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_generate_issue_number BEFORE INSERT ON public.issues FOR EACH ROW WHEN ((new.issue_number IS NULL)) EXECUTE FUNCTION public.generate_issue_number();


--
-- Name: issues trg_issue_sla_dynamic; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_issue_sla_dynamic BEFORE INSERT OR UPDATE ON public.issues FOR EACH ROW EXECUTE FUNCTION public.calculate_issue_sla_dynamic();


--
-- Name: tickets trg_stamp_rejected_at_and_acceptance_sla; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_stamp_rejected_at_and_acceptance_sla BEFORE UPDATE ON public.tickets FOR EACH ROW EXECUTE FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla();


--
-- Name: tickets trg_ticket_sla_on_status_change; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_ticket_sla_on_status_change AFTER UPDATE OF status ON public.tickets FOR EACH ROW EXECUTE FUNCTION public.recalculate_ticket_sla_on_status_change();


--
-- Name: issues trg_update_ticket_sla_agg; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_update_ticket_sla_agg AFTER INSERT OR UPDATE OF sla_end_date, status, category, severity ON public.issues FOR EACH ROW EXECUTE FUNCTION public.calculate_ticket_overall_sla();


--
-- Name: purchase_invoice_items trigger_add_part_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_add_part_inventory AFTER INSERT ON public.purchase_invoice_items FOR EACH ROW EXECUTE FUNCTION public.add_part_to_inventory();


--
-- Name: purchase_invoice_items trigger_adjust_part_inventory_on_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_adjust_part_inventory_on_update AFTER UPDATE ON public.purchase_invoice_items FOR EACH ROW EXECUTE FUNCTION public.adjust_part_inventory_on_update();


--
-- Name: issue_parts trigger_deduct_part_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_deduct_part_inventory AFTER INSERT ON public.issue_parts FOR EACH ROW EXECUTE FUNCTION public.deduct_part_from_inventory();


--
-- Name: issue_parts trigger_restore_part_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_restore_part_inventory AFTER DELETE ON public.issue_parts FOR EACH ROW EXECUTE FUNCTION public.restore_part_to_inventory();


--
-- Name: purchase_invoice_items trigger_reverse_part_inventory_on_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_reverse_part_inventory_on_delete AFTER DELETE ON public.purchase_invoice_items FOR EACH ROW EXECUTE FUNCTION public.reverse_part_inventory_on_delete();


--
-- Name: issues trigger_update_ticket_status; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_ticket_status AFTER INSERT OR UPDATE ON public.issues FOR EACH ROW EXECUTE FUNCTION public.update_ticket_status_on_issue_change();


--
-- Name: audit_logs audit_logs_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id);


--
-- Name: finance_entries finance_entries_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finance_entries
    ADD CONSTRAINT finance_entries_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.users(id);


--
-- Name: finance_entries finance_entries_site_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finance_entries
    ADD CONSTRAINT finance_entries_site_fkey FOREIGN KEY (site) REFERENCES public.sites(name) ON UPDATE CASCADE;


--
-- Name: finance_entries finance_entries_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.finance_entries
    ADD CONSTRAINT finance_entries_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id);


--
-- Name: issue_parts issue_parts_added_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issue_parts
    ADD CONSTRAINT issue_parts_added_by_fkey FOREIGN KEY (added_by) REFERENCES public.users(id);


--
-- Name: issue_parts issue_parts_issue_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issue_parts
    ADD CONSTRAINT issue_parts_issue_id_fkey FOREIGN KEY (issue_id) REFERENCES public.issues(id) ON DELETE CASCADE;


--
-- Name: issue_parts issue_parts_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issue_parts
    ADD CONSTRAINT issue_parts_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.parts(id);


--
-- Name: issues issues_job_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issues
    ADD CONSTRAINT issues_job_card_id_fkey FOREIGN KEY (job_card_id) REFERENCES public.job_cards(id) ON DELETE SET NULL;


--
-- Name: issues issues_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.issues
    ADD CONSTRAINT issues_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id) ON DELETE CASCADE;


--
-- Name: job_cards job_cards_assigned_mechanic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.job_cards
    ADD CONSTRAINT job_cards_assigned_mechanic_id_fkey FOREIGN KEY (assigned_mechanic_id) REFERENCES public.users(id);


--
-- Name: job_cards job_cards_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.job_cards
    ADD CONSTRAINT job_cards_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;


--
-- Name: outsource_invoice_payments outsource_invoice_payments_outsource_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoice_payments
    ADD CONSTRAINT outsource_invoice_payments_outsource_invoice_id_fkey FOREIGN KEY (outsource_invoice_id) REFERENCES public.outsource_invoices(id) ON DELETE CASCADE;


--
-- Name: outsource_invoice_payments outsource_invoice_payments_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoice_payments
    ADD CONSTRAINT outsource_invoice_payments_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.users(id);


--
-- Name: outsource_invoices outsource_invoices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoices
    ADD CONSTRAINT outsource_invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: outsource_invoices outsource_invoices_job_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.outsource_invoices
    ADD CONSTRAINT outsource_invoices_job_card_id_fkey FOREIGN KEY (job_card_id) REFERENCES public.job_cards(id) ON DELETE CASCADE;


--
-- Name: purchase_invoice_items purchase_invoice_items_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.purchase_invoices(id) ON DELETE CASCADE;


--
-- Name: purchase_invoice_items purchase_invoice_items_part_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoice_items
    ADD CONSTRAINT purchase_invoice_items_part_id_fkey FOREIGN KEY (part_id) REFERENCES public.parts(id);


--
-- Name: purchase_invoices purchase_invoices_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_invoices
    ADD CONSTRAINT purchase_invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: scrap_disposal_items scrap_disposal_items_disposal_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal_items
    ADD CONSTRAINT scrap_disposal_items_disposal_fkey FOREIGN KEY (disposal_id) REFERENCES public.scrap_disposal(id);


--
-- Name: scrap_disposal_items scrap_disposal_items_scrap_inventory_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal_items
    ADD CONSTRAINT scrap_disposal_items_scrap_inventory_fkey FOREIGN KEY (scrap_inventory_id) REFERENCES public.scrap_inventory(id);


--
-- Name: scrap_disposal scrap_disposal_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_disposal
    ADD CONSTRAINT scrap_disposal_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.users(id);


--
-- Name: scrap_excluded_parts scrap_excluded_parts_excluded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_excluded_by_fkey FOREIGN KEY (excluded_by) REFERENCES public.users(id);


--
-- Name: scrap_excluded_parts scrap_excluded_parts_source_issue_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_source_issue_fkey FOREIGN KEY (source_issue_id) REFERENCES public.issues(id);


--
-- Name: scrap_excluded_parts scrap_excluded_parts_source_issue_part_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_source_issue_part_fkey FOREIGN KEY (source_issue_part_id) REFERENCES public.issue_parts(id) ON DELETE SET NULL;


--
-- Name: scrap_excluded_parts scrap_excluded_parts_source_job_card_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_source_job_card_fkey FOREIGN KEY (source_job_card_id) REFERENCES public.job_cards(id);


--
-- Name: scrap_inventory scrap_inventory_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: scrap_inventory scrap_inventory_received_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_received_by_fkey FOREIGN KEY (received_by) REFERENCES public.users(id);


--
-- Name: scrap_inventory scrap_inventory_source_issue_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_source_issue_fkey FOREIGN KEY (source_issue_id) REFERENCES public.issues(id);


--
-- Name: scrap_inventory scrap_inventory_source_issue_part_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_source_issue_part_fkey FOREIGN KEY (source_issue_part_id) REFERENCES public.issue_parts(id) ON DELETE SET NULL;


--
-- Name: scrap_inventory scrap_inventory_source_job_card_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_source_job_card_fkey FOREIGN KEY (source_job_card_id) REFERENCES public.job_cards(id);


--
-- Name: scrap_inventory scrap_inventory_source_ticket_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_source_ticket_fkey FOREIGN KEY (source_ticket_id) REFERENCES public.tickets(id);


--
-- Name: scrap_inventory scrap_inventory_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.users(id);


--
-- Name: scrap_writeoff_items scrap_writeoff_items_scrap_inventory_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff_items
    ADD CONSTRAINT scrap_writeoff_items_scrap_inventory_fkey FOREIGN KEY (scrap_inventory_id) REFERENCES public.scrap_inventory(id);


--
-- Name: scrap_writeoff_items scrap_writeoff_items_writeoff_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff_items
    ADD CONSTRAINT scrap_writeoff_items_writeoff_fkey FOREIGN KEY (writeoff_id) REFERENCES public.scrap_writeoff(id);


--
-- Name: scrap_writeoff scrap_writeoff_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scrap_writeoff
    ADD CONSTRAINT scrap_writeoff_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.users(id);


--
-- Name: sla_events sla_events_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_events
    ADD CONSTRAINT sla_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: sla_events sla_events_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sla_events
    ADD CONSTRAINT sla_events_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id) ON DELETE CASCADE;


--
-- Name: suppliers suppliers_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: tickets tickets_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES public.users(id);


--
-- Name: tickets tickets_merged_into_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_merged_into_ticket_id_fkey FOREIGN KEY (merged_into_ticket_id) REFERENCES public.tickets(id);


--
-- Name: tickets tickets_site_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_site_fkey FOREIGN KEY (site) REFERENCES public.sites(name) ON UPDATE CASCADE;


--
-- Name: user_settings user_settings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_settings
    ADD CONSTRAINT user_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);


--
-- Name: user_sites user_sites_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sites
    ADD CONSTRAINT user_sites_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE CASCADE;


--
-- Name: user_sites user_sites_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sites
    ADD CONSTRAINT user_sites_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: users users_site_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_site_fkey FOREIGN KEY (site) REFERENCES public.sites(name) ON UPDATE CASCADE;


--
-- Name: vehicle_sites vehicle_sites_site_name_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle_sites
    ADD CONSTRAINT vehicle_sites_site_name_fkey FOREIGN KEY (site_name) REFERENCES public.sites(name) ON DELETE CASCADE;


--
-- Name: vehicle_sites vehicle_sites_vehicle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.vehicle_sites
    ADD CONSTRAINT vehicle_sites_vehicle_id_fkey FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id) ON DELETE CASCADE;


--
-- Name: sites All authenticated users see sites; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "All authenticated users see sites" ON public.sites FOR SELECT USING ((auth.uid() IS NOT NULL));


--
-- Name: vehicles All authenticated users see vehicles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "All authenticated users see vehicles" ON public.vehicles FOR SELECT USING ((auth.uid() IS NOT NULL));


--
-- Name: part_units Authenticated read part_units; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated read part_units" ON public.part_units FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: vehicle_sites Authenticated users can read vehicle_sites; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users can read vehicle_sites" ON public.vehicle_sites FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: parts Authenticated users view parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users view parts" ON public.parts FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: vehicles Authenticated users view vehicles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users view vehicles" ON public.vehicles FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: outsource_invoice_payments Authenticated view invoice payments; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated view invoice payments" ON public.outsource_invoice_payments FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: outsource_invoices Authenticated view outsource invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated view outsource invoices" ON public.outsource_invoices FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: tickets Creators can rate tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Creators can rate tickets" ON public.tickets FOR UPDATE TO authenticated USING ((auth.uid() = created_by_user_id)) WITH CHECK ((auth.uid() = created_by_user_id));


--
-- Name: sla_rules Everyone can read SLA rules; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Everyone can read SLA rules" ON public.sla_rules FOR SELECT USING (true);


--
-- Name: holidays Everyone can read holidays; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Everyone can read holidays" ON public.holidays FOR SELECT USING (true);


--
-- Name: system_settings Everyone can read settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Everyone can read settings" ON public.system_settings FOR SELECT USING (true);


--
-- Name: purchase_invoice_items Exec and finance delete invoice items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance delete invoice items" ON public.purchase_invoice_items FOR DELETE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoice_items Exec and finance insert invoice items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance insert invoice items" ON public.purchase_invoice_items FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoices Exec and finance insert invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance insert invoices" ON public.purchase_invoices FOR INSERT WITH CHECK (((auth.uid() = created_by) AND (EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text])))))));


--
-- Name: parts Exec and finance manage parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance manage parts" ON public.parts USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: vehicles Exec and finance manage vehicles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance manage vehicles" ON public.vehicles USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoice_items Exec and finance update invoice items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance update invoice items" ON public.purchase_invoice_items FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoices Exec and finance update invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance update invoices" ON public.purchase_invoices FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoice_items Exec and finance view invoice items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance view invoice items" ON public.purchase_invoice_items FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: purchase_invoices Exec and finance view invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec and finance view invoices" ON public.purchase_invoices FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text]))))));


--
-- Name: outsource_invoice_payments Exec finance insert invoice payments; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec finance insert invoice payments" ON public.outsource_invoice_payments FOR INSERT WITH CHECK ((public.is_maintenance_exec() OR (EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'finance'::text))))));


--
-- Name: outsource_invoices Exec finance supervisor insert outsource invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec finance supervisor insert outsource invoices" ON public.outsource_invoices FOR INSERT WITH CHECK ((public.is_maintenance_exec() OR (EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['finance'::text, 'supervisor'::text])))))));


--
-- Name: outsource_invoices Exec finance supervisor update outsource invoices; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Exec finance supervisor update outsource invoices" ON public.outsource_invoices FOR UPDATE USING ((public.is_maintenance_exec() OR (EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['finance'::text, 'supervisor'::text]))))))) WITH CHECK ((public.is_maintenance_exec() OR (EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = ANY (ARRAY['finance'::text, 'supervisor'::text])))))));


--
-- Name: users Execs can read all profiles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs can read all profiles" ON public.users FOR SELECT USING (public.is_maintenance_exec());


--
-- Name: tickets Execs can see all tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs can see all tickets" ON public.tickets FOR SELECT USING (public.is_maintenance_exec());


--
-- Name: tickets Execs can update tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs can update tickets" ON public.tickets FOR UPDATE USING (public.is_maintenance_exec());


--
-- Name: users Execs can update users; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs can update users" ON public.users FOR UPDATE USING (public.is_maintenance_exec());


--
-- Name: issues Execs manage issues; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage issues" ON public.issues USING (public.is_maintenance_exec());


--
-- Name: job_cards Execs manage job cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage job cards" ON public.job_cards USING (public.is_maintenance_exec());


--
-- Name: part_units Execs manage part_units; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage part_units" ON public.part_units USING (public.is_maintenance_exec());


--
-- Name: scrap_disposal Execs manage scrap_disposal; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage scrap_disposal" ON public.scrap_disposal TO authenticated USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());


--
-- Name: scrap_disposal_items Execs manage scrap_disposal_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage scrap_disposal_items" ON public.scrap_disposal_items TO authenticated USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());


--
-- Name: scrap_inventory Execs manage scrap_inventory; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage scrap_inventory" ON public.scrap_inventory TO authenticated USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());


--
-- Name: scrap_writeoff Execs manage scrap_writeoff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage scrap_writeoff" ON public.scrap_writeoff TO authenticated USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());


--
-- Name: scrap_writeoff_items Execs manage scrap_writeoff_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs manage scrap_writeoff_items" ON public.scrap_writeoff_items TO authenticated USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());


--
-- Name: scrap_excluded_parts Execs view scrap_excluded_parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Execs view scrap_excluded_parts" ON public.scrap_excluded_parts FOR SELECT TO authenticated USING (public.is_maintenance_exec());


--
-- Name: finance_entries Finance creates entries; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance creates entries" ON public.finance_entries FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['finance'::text, 'super_admin'::text]))))));


--
-- Name: finance_entries Finance sees all entries; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance sees all entries" ON public.finance_entries FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['finance'::text, 'maintenance_exec'::text, 'super_admin'::text]))))));


--
-- Name: finance_entries Finance updates entries; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance updates entries" ON public.finance_entries FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['finance'::text, 'super_admin'::text]))))));


--
-- Name: job_cards Finance view job cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view job cards" ON public.job_cards FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_disposal Finance view scrap_disposal; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_disposal" ON public.scrap_disposal FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_disposal_items Finance view scrap_disposal_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_disposal_items" ON public.scrap_disposal_items FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_excluded_parts Finance view scrap_excluded_parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_excluded_parts" ON public.scrap_excluded_parts FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_inventory Finance view scrap_inventory; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_inventory" ON public.scrap_inventory FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_writeoff Finance view scrap_writeoff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_writeoff" ON public.scrap_writeoff FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: scrap_writeoff_items Finance view scrap_writeoff_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Finance view scrap_writeoff_items" ON public.scrap_writeoff_items FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'finance'::text)))));


--
-- Name: tickets Maintenance exec sees all tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Maintenance exec sees all tickets" ON public.tickets FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'maintenance_exec'::text)))));


--
-- Name: tickets Maintenance exec updates tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Maintenance exec updates tickets" ON public.tickets FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'maintenance_exec'::text)))));


--
-- Name: issue_parts Mechanics delete issue parts on assigned cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics delete issue parts on assigned cards" ON public.issue_parts FOR DELETE USING ((EXISTS ( SELECT 1
   FROM (public.issues i
     JOIN public.job_cards jc ON ((jc.id = i.job_card_id)))
  WHERE ((i.id = issue_parts.issue_id) AND ((jc.assigned_mechanic_id = auth.uid()) OR public.is_maintenance_exec())))));


--
-- Name: issue_parts Mechanics insert issue parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics insert issue parts" ON public.issue_parts FOR INSERT WITH CHECK (((auth.uid() = added_by) AND (EXISTS ( SELECT 1
   FROM (public.issues i
     JOIN public.job_cards jc ON ((jc.id = i.job_card_id)))
  WHERE ((i.id = issue_parts.issue_id) AND ((jc.assigned_mechanic_id = auth.uid()) OR public.is_maintenance_exec()))))));


--
-- Name: job_cards Mechanics update assigned cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics update assigned cards" ON public.job_cards FOR UPDATE USING ((assigned_mechanic_id = auth.uid()));


--
-- Name: issues Mechanics update issues on assigned cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics update issues on assigned cards" ON public.issues FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.job_cards
  WHERE ((job_cards.id = issues.job_card_id) AND (job_cards.assigned_mechanic_id = auth.uid())))));


--
-- Name: job_cards Mechanics view assigned cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics view assigned cards" ON public.job_cards FOR SELECT USING (((assigned_mechanic_id = auth.uid()) OR public.is_maintenance_exec()));


--
-- Name: issues Mechanics view issues on assigned cards; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Mechanics view issues on assigned cards" ON public.issues FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.job_cards
  WHERE ((job_cards.id = issues.job_card_id) AND (job_cards.assigned_mechanic_id = auth.uid())))));


--
-- Name: holidays Super admins can delete holidays; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can delete holidays" ON public.holidays FOR DELETE USING (public.is_super_admin());


--
-- Name: holidays Super admins can insert holidays; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can insert holidays" ON public.holidays FOR INSERT WITH CHECK (public.is_super_admin());


--
-- Name: system_settings Super admins can insert settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can insert settings" ON public.system_settings FOR INSERT WITH CHECK (public.is_super_admin());


--
-- Name: sla_rules Super admins can update SLA rules; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update SLA rules" ON public.sla_rules FOR UPDATE USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());


--
-- Name: holidays Super admins can update holidays; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update holidays" ON public.holidays FOR UPDATE USING (public.is_super_admin());


--
-- Name: system_settings Super admins can update settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update settings" ON public.system_settings FOR UPDATE USING (public.is_super_admin()) WITH CHECK (public.is_super_admin());


--
-- Name: tickets Supervisors and execs create tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors and execs create tickets" ON public.tickets FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['supervisor'::text, 'maintenance_exec'::text, 'super_admin'::text]))))));


--
-- Name: issues Supervisors create issues; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors create issues" ON public.issues FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM (public.tickets t
     JOIN public.users u ON ((u.id = auth.uid())))
  WHERE ((t.id = issues.ticket_id) AND (u.role = 'supervisor'::text) AND (t.site IN ( SELECT s.name
           FROM (public.user_sites us
             JOIN public.sites s ON ((s.id = us.site_id)))
          WHERE (us.user_id = auth.uid())))))));


--
-- Name: tickets Supervisors see own site tickets; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors see own site tickets" ON public.tickets FOR SELECT USING (((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = 'supervisor'::text)))) AND (site IN ( SELECT s.name
   FROM (public.user_sites us
     JOIN public.sites s ON ((s.id = us.site_id)))
  WHERE (us.user_id = auth.uid())))));


--
-- Name: issues Supervisors update own ratings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors update own ratings" ON public.issues FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.tickets t
  WHERE ((t.id = issues.ticket_id) AND (EXISTS ( SELECT 1
           FROM public.users
          WHERE ((users.id = auth.uid()) AND (users.role = 'supervisor'::text)))) AND (t.site IN ( SELECT s.name
           FROM (public.user_sites us
             JOIN public.sites s ON ((s.id = us.site_id)))
          WHERE (us.user_id = auth.uid())))))));


--
-- Name: issues Supervisors view site issues; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site issues" ON public.issues FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.tickets t
  WHERE ((t.id = issues.ticket_id) AND (EXISTS ( SELECT 1
           FROM public.users
          WHERE ((users.id = auth.uid()) AND (users.role = 'supervisor'::text)))) AND (t.site IN ( SELECT s.name
           FROM (public.user_sites us
             JOIN public.sites s ON ((s.id = us.site_id)))
          WHERE (us.user_id = auth.uid())))))));


--
-- Name: scrap_inventory Supervisors view site scrap; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap" ON public.scrap_inventory FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND public.job_card_site_accessible_to_user(source_job_card_id)));


--
-- Name: scrap_excluded_parts Supervisors view site scrap excluded; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap excluded" ON public.scrap_excluded_parts FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND public.job_card_site_accessible_to_user(source_job_card_id)));


--
-- Name: scrap_disposal Supervisors view site scrap_disposal; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap_disposal" ON public.scrap_disposal FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND (EXISTS ( SELECT 1
   FROM (public.scrap_disposal_items sdi
     JOIN public.scrap_inventory si ON ((si.id = sdi.scrap_inventory_id)))
  WHERE ((sdi.disposal_id = scrap_disposal.id) AND public.job_card_site_accessible_to_user(si.source_job_card_id))))));


--
-- Name: scrap_disposal_items Supervisors view site scrap_disposal_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap_disposal_items" ON public.scrap_disposal_items FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND (EXISTS ( SELECT 1
   FROM public.scrap_inventory si
  WHERE ((si.id = scrap_disposal_items.scrap_inventory_id) AND public.job_card_site_accessible_to_user(si.source_job_card_id))))));


--
-- Name: scrap_writeoff Supervisors view site scrap_writeoff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap_writeoff" ON public.scrap_writeoff FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND (EXISTS ( SELECT 1
   FROM (public.scrap_writeoff_items swi
     JOIN public.scrap_inventory si ON ((si.id = swi.scrap_inventory_id)))
  WHERE ((swi.writeoff_id = scrap_writeoff.id) AND public.job_card_site_accessible_to_user(si.source_job_card_id))))));


--
-- Name: scrap_writeoff_items Supervisors view site scrap_writeoff_items; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Supervisors view site scrap_writeoff_items" ON public.scrap_writeoff_items FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1
   FROM public.users u
  WHERE ((u.id = auth.uid()) AND (u.role = 'supervisor'::text)))) AND (EXISTS ( SELECT 1
   FROM public.scrap_inventory si
  WHERE ((si.id = scrap_writeoff_items.scrap_inventory_id) AND public.job_card_site_accessible_to_user(si.source_job_card_id))))));


--
-- Name: audit_logs Users can insert audit logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert audit logs" ON public.audit_logs FOR INSERT WITH CHECK ((auth.uid() = performed_by));


--
-- Name: sla_events Users can insert events; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert events" ON public.sla_events FOR INSERT WITH CHECK ((auth.uid() = created_by));


--
-- Name: user_settings Users can insert their own settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert their own settings" ON public.user_settings FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: users Users can read own profile; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can read own profile" ON public.users FOR SELECT USING ((auth.uid() = id));


--
-- Name: user_settings Users can update their own settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update their own settings" ON public.user_settings FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: audit_logs Users can view audit logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view audit logs" ON public.audit_logs FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: sla_events Users can view events for tickets they can access; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view events for tickets they can access" ON public.sla_events FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.tickets
  WHERE (tickets.id = sla_events.ticket_id))));


--
-- Name: user_settings Users can view their own settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view their own settings" ON public.user_settings FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: issue_parts View issue parts; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "View issue parts" ON public.issue_parts FOR SELECT USING ((EXISTS ( SELECT 1
   FROM (public.issues i
     JOIN public.job_cards jc ON ((jc.id = i.job_card_id)))
  WHERE ((i.id = issue_parts.issue_id) AND ((jc.assigned_mechanic_id = auth.uid()) OR public.is_maintenance_exec())))));


--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: finance_entries; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.finance_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: holidays; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;

--
-- Name: issue_parts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.issue_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: issues; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.issues ENABLE ROW LEVEL SECURITY;

--
-- Name: job_cards; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.job_cards ENABLE ROW LEVEL SECURITY;

--
-- Name: outsource_invoice_payments; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.outsource_invoice_payments ENABLE ROW LEVEL SECURITY;

--
-- Name: outsource_invoices; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.outsource_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: part_units; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.part_units ENABLE ROW LEVEL SECURITY;

--
-- Name: parts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.parts ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_invoice_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_invoice_items ENABLE ROW LEVEL SECURITY;

--
-- Name: purchase_invoices; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.purchase_invoices ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_disposal; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_disposal ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_disposal_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_disposal_items ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_excluded_parts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_excluded_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_inventory; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_inventory ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_writeoff; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_writeoff ENABLE ROW LEVEL SECURITY;

--
-- Name: scrap_writeoff_items; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.scrap_writeoff_items ENABLE ROW LEVEL SECURITY;

--
-- Name: sites; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sites ENABLE ROW LEVEL SECURITY;

--
-- Name: sla_events; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sla_events ENABLE ROW LEVEL SECURITY;

--
-- Name: sla_rules; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.sla_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: suppliers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

--
-- Name: suppliers suppliers_auth_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY suppliers_auth_select ON public.suppliers FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'finance'::text, 'super_admin'::text])) AND (users.is_active = true)))));


--
-- Name: suppliers suppliers_exec_update; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY suppliers_exec_update ON public.suppliers FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM public.users
  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['maintenance_exec'::text, 'super_admin'::text])) AND (users.is_active = true)))));


--
-- Name: suppliers suppliers_public_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY suppliers_public_insert ON public.suppliers FOR INSERT WITH CHECK (true);


--
-- Name: system_settings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: tickets; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;

--
-- Name: user_settings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: user_sites; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.user_sites ENABLE ROW LEVEL SECURITY;

--
-- Name: user_sites user_sites_delete; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY user_sites_delete ON public.user_sites FOR DELETE USING (public.is_maintenance_exec());


--
-- Name: user_sites user_sites_insert; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY user_sites_insert ON public.user_sites FOR INSERT WITH CHECK (public.is_maintenance_exec());


--
-- Name: user_sites user_sites_select; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY user_sites_select ON public.user_sites FOR SELECT USING (((user_id = auth.uid()) OR public.is_maintenance_exec()));


--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: vehicle_sites; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.vehicle_sites ENABLE ROW LEVEL SECURITY;

--
-- Name: vehicles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;

--
-- Name: supabase_realtime; Type: PUBLICATION; Schema: -; Owner: postgres
--

CREATE PUBLICATION supabase_realtime WITH (publish = 'insert, update, delete, truncate');


ALTER PUBLICATION supabase_realtime OWNER TO postgres;

--
-- Name: SCHEMA cron; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA cron TO postgres WITH GRANT OPTION;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: SCHEMA net; Type: ACL; Schema: -; Owner: supabase_admin
--

GRANT USAGE ON SCHEMA net TO supabase_functions_admin;
GRANT USAGE ON SCHEMA net TO postgres;
GRANT USAGE ON SCHEMA net TO anon;
GRANT USAGE ON SCHEMA net TO authenticated;
GRANT USAGE ON SCHEMA net TO service_role;


--
-- Name: FUNCTION alter_job(job_id bigint, schedule text, command text, database text, username text, active boolean); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.alter_job(job_id bigint, schedule text, command text, database text, username text, active boolean) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION job_cache_invalidate(); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.job_cache_invalidate() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION schedule(schedule text, command text); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.schedule(schedule text, command text) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION schedule(job_name text, schedule text, command text); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.schedule(job_name text, schedule text, command text) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION schedule_in_database(job_name text, schedule text, command text, database text, username text, active boolean); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.schedule_in_database(job_name text, schedule text, command text, database text, username text, active boolean) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION unschedule(job_id bigint); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.unschedule(job_id bigint) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION unschedule(job_name text); Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON FUNCTION cron.unschedule(job_name text) TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION pg_reload_conf(); Type: ACL; Schema: pg_catalog; Owner: supabase_admin
--

GRANT ALL ON FUNCTION pg_catalog.pg_reload_conf() TO postgres WITH GRANT OPTION;


--
-- Name: FUNCTION add_part_to_inventory(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.add_part_to_inventory() TO anon;
GRANT ALL ON FUNCTION public.add_part_to_inventory() TO authenticated;
GRANT ALL ON FUNCTION public.add_part_to_inventory() TO service_role;


--
-- Name: FUNCTION add_working_days(start_date date, n_days integer); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.add_working_days(start_date date, n_days integer) TO anon;
GRANT ALL ON FUNCTION public.add_working_days(start_date date, n_days integer) TO authenticated;
GRANT ALL ON FUNCTION public.add_working_days(start_date date, n_days integer) TO service_role;


--
-- Name: FUNCTION adjust_part_inventory_on_update(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.adjust_part_inventory_on_update() TO anon;
GRANT ALL ON FUNCTION public.adjust_part_inventory_on_update() TO authenticated;
GRANT ALL ON FUNCTION public.adjust_part_inventory_on_update() TO service_role;


--
-- Name: FUNCTION calculate_issue_sla_dynamic(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_issue_sla_dynamic() TO anon;
GRANT ALL ON FUNCTION public.calculate_issue_sla_dynamic() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_issue_sla_dynamic() TO service_role;


--
-- Name: FUNCTION calculate_sla_days(p_impact text, p_category text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_sla_days(p_impact text, p_category text) TO anon;
GRANT ALL ON FUNCTION public.calculate_sla_days(p_impact text, p_category text) TO authenticated;
GRANT ALL ON FUNCTION public.calculate_sla_days(p_impact text, p_category text) TO service_role;


--
-- Name: FUNCTION calculate_ticket_overall_sla(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.calculate_ticket_overall_sla() TO anon;
GRANT ALL ON FUNCTION public.calculate_ticket_overall_sla() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_ticket_overall_sla() TO service_role;


--
-- Name: FUNCTION check_pan_exists(p_pan text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.check_pan_exists(p_pan text) TO anon;
GRANT ALL ON FUNCTION public.check_pan_exists(p_pan text) TO authenticated;
GRANT ALL ON FUNCTION public.check_pan_exists(p_pan text) TO service_role;


--
-- Name: FUNCTION close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) TO anon;
GRANT ALL ON FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb) TO service_role;


--
-- Name: FUNCTION deduct_part_from_inventory(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.deduct_part_from_inventory() TO anon;
GRANT ALL ON FUNCTION public.deduct_part_from_inventory() TO authenticated;
GRANT ALL ON FUNCTION public.deduct_part_from_inventory() TO service_role;


--
-- Name: FUNCTION delete_issue_part_with_scrap_check(p_issue_part_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) TO anon;
GRANT ALL ON FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_issue_part_with_scrap_check(p_issue_part_id uuid) TO service_role;


--
-- Name: FUNCTION evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone) TO service_role;


--
-- Name: FUNCTION generate_issue_number(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.generate_issue_number() TO anon;
GRANT ALL ON FUNCTION public.generate_issue_number() TO authenticated;
GRANT ALL ON FUNCTION public.generate_issue_number() TO service_role;


--
-- Name: FUNCTION get_blocking_scrap_for_issue_part(p_issue_part_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_blocking_scrap_for_issue_part(p_issue_part_id uuid) TO anon;
GRANT ALL ON FUNCTION public.get_blocking_scrap_for_issue_part(p_issue_part_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_blocking_scrap_for_issue_part(p_issue_part_id uuid) TO service_role;


--
-- Name: FUNCTION get_maintenance_stats(start_date_input date, end_date_input date, site_filter text); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_maintenance_stats(start_date_input date, end_date_input date, site_filter text) TO anon;
GRANT ALL ON FUNCTION public.get_maintenance_stats(start_date_input date, end_date_input date, site_filter text) TO authenticated;
GRANT ALL ON FUNCTION public.get_maintenance_stats(start_date_input date, end_date_input date, site_filter text) TO service_role;


--
-- Name: FUNCTION get_outsource_invoice_summary(p_payment_status text[], p_paid_by text[], p_date_from date, p_date_to date); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.get_outsource_invoice_summary(p_payment_status text[], p_paid_by text[], p_date_from date, p_date_to date) TO anon;
GRANT ALL ON FUNCTION public.get_outsource_invoice_summary(p_payment_status text[], p_paid_by text[], p_date_from date, p_date_to date) TO authenticated;
GRANT ALL ON FUNCTION public.get_outsource_invoice_summary(p_payment_status text[], p_paid_by text[], p_date_from date, p_date_to date) TO service_role;


--
-- Name: FUNCTION is_maintenance_exec(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.is_maintenance_exec() TO anon;
GRANT ALL ON FUNCTION public.is_maintenance_exec() TO authenticated;
GRANT ALL ON FUNCTION public.is_maintenance_exec() TO service_role;


--
-- Name: FUNCTION is_super_admin(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.is_super_admin() TO anon;
GRANT ALL ON FUNCTION public.is_super_admin() TO authenticated;
GRANT ALL ON FUNCTION public.is_super_admin() TO service_role;


--
-- Name: FUNCTION job_card_site_accessible_to_user(p_job_card_id uuid); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) TO anon;
GRANT ALL ON FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid) TO service_role;


--
-- Name: FUNCTION recalculate_ticket_sla_on_status_change(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.recalculate_ticket_sla_on_status_change() TO anon;
GRANT ALL ON FUNCTION public.recalculate_ticket_sla_on_status_change() TO authenticated;
GRANT ALL ON FUNCTION public.recalculate_ticket_sla_on_status_change() TO service_role;


--
-- Name: FUNCTION record_scrap_disposal(p_header jsonb, p_items jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) TO anon;
GRANT ALL ON FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.record_scrap_disposal(p_header jsonb, p_items jsonb) TO service_role;


--
-- Name: FUNCTION record_scrap_writeoff(p_header jsonb, p_items jsonb); Type: ACL; Schema: public; Owner: postgres
--

REVOKE ALL ON FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) TO anon;
GRANT ALL ON FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.record_scrap_writeoff(p_header jsonb, p_items jsonb) TO service_role;


--
-- Name: FUNCTION restore_part_to_inventory(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.restore_part_to_inventory() TO anon;
GRANT ALL ON FUNCTION public.restore_part_to_inventory() TO authenticated;
GRANT ALL ON FUNCTION public.restore_part_to_inventory() TO service_role;


--
-- Name: FUNCTION reverse_part_inventory_on_delete(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.reverse_part_inventory_on_delete() TO anon;
GRANT ALL ON FUNCTION public.reverse_part_inventory_on_delete() TO authenticated;
GRANT ALL ON FUNCTION public.reverse_part_inventory_on_delete() TO service_role;


--
-- Name: FUNCTION set_updated_at(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.set_updated_at() TO anon;
GRANT ALL ON FUNCTION public.set_updated_at() TO authenticated;
GRANT ALL ON FUNCTION public.set_updated_at() TO service_role;


--
-- Name: FUNCTION stamp_rejected_at_and_evaluate_acceptance_sla(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla() TO anon;
GRANT ALL ON FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla() TO authenticated;
GRANT ALL ON FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla() TO service_role;


--
-- Name: FUNCTION trg_set_acceptance_sla_on_first_issue(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.trg_set_acceptance_sla_on_first_issue() TO anon;
GRANT ALL ON FUNCTION public.trg_set_acceptance_sla_on_first_issue() TO authenticated;
GRANT ALL ON FUNCTION public.trg_set_acceptance_sla_on_first_issue() TO service_role;


--
-- Name: FUNCTION update_ticket_sla(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_ticket_sla() TO anon;
GRANT ALL ON FUNCTION public.update_ticket_sla() TO authenticated;
GRANT ALL ON FUNCTION public.update_ticket_sla() TO service_role;


--
-- Name: FUNCTION update_ticket_status_on_issue_change(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION public.update_ticket_status_on_issue_change() TO anon;
GRANT ALL ON FUNCTION public.update_ticket_status_on_issue_change() TO authenticated;
GRANT ALL ON FUNCTION public.update_ticket_status_on_issue_change() TO service_role;


--
-- Name: TABLE job; Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT SELECT ON TABLE cron.job TO postgres WITH GRANT OPTION;


--
-- Name: TABLE job_run_details; Type: ACL; Schema: cron; Owner: supabase_admin
--

GRANT ALL ON TABLE cron.job_run_details TO postgres WITH GRANT OPTION;


--
-- Name: TABLE audit_logs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.audit_logs TO anon;
GRANT ALL ON TABLE public.audit_logs TO authenticated;
GRANT ALL ON TABLE public.audit_logs TO service_role;


--
-- Name: TABLE finance_entries; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.finance_entries TO anon;
GRANT ALL ON TABLE public.finance_entries TO authenticated;
GRANT ALL ON TABLE public.finance_entries TO service_role;


--
-- Name: TABLE holidays; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.holidays TO anon;
GRANT ALL ON TABLE public.holidays TO authenticated;
GRANT ALL ON TABLE public.holidays TO service_role;


--
-- Name: TABLE issue_parts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.issue_parts TO anon;
GRANT ALL ON TABLE public.issue_parts TO authenticated;
GRANT ALL ON TABLE public.issue_parts TO service_role;


--
-- Name: TABLE issues; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.issues TO anon;
GRANT ALL ON TABLE public.issues TO authenticated;
GRANT ALL ON TABLE public.issues TO service_role;


--
-- Name: TABLE job_cards; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.job_cards TO anon;
GRANT ALL ON TABLE public.job_cards TO authenticated;
GRANT ALL ON TABLE public.job_cards TO service_role;


--
-- Name: SEQUENCE job_cards_job_card_number_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.job_cards_job_card_number_seq TO anon;
GRANT ALL ON SEQUENCE public.job_cards_job_card_number_seq TO authenticated;
GRANT ALL ON SEQUENCE public.job_cards_job_card_number_seq TO service_role;


--
-- Name: TABLE tickets; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tickets TO anon;
GRANT ALL ON TABLE public.tickets TO authenticated;
GRANT ALL ON TABLE public.tickets TO service_role;


--
-- Name: TABLE maintenance_dashboard_stats; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.maintenance_dashboard_stats TO anon;
GRANT ALL ON TABLE public.maintenance_dashboard_stats TO authenticated;
GRANT ALL ON TABLE public.maintenance_dashboard_stats TO service_role;


--
-- Name: TABLE outsource_invoice_payments; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.outsource_invoice_payments TO anon;
GRANT ALL ON TABLE public.outsource_invoice_payments TO authenticated;
GRANT ALL ON TABLE public.outsource_invoice_payments TO service_role;


--
-- Name: TABLE outsource_invoices; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.outsource_invoices TO anon;
GRANT ALL ON TABLE public.outsource_invoices TO authenticated;
GRANT ALL ON TABLE public.outsource_invoices TO service_role;


--
-- Name: TABLE part_units; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.part_units TO anon;
GRANT ALL ON TABLE public.part_units TO authenticated;
GRANT ALL ON TABLE public.part_units TO service_role;


--
-- Name: TABLE parts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.parts TO anon;
GRANT ALL ON TABLE public.parts TO authenticated;
GRANT ALL ON TABLE public.parts TO service_role;


--
-- Name: TABLE purchase_invoice_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_invoice_items TO anon;
GRANT ALL ON TABLE public.purchase_invoice_items TO authenticated;
GRANT ALL ON TABLE public.purchase_invoice_items TO service_role;


--
-- Name: TABLE purchase_invoices; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.purchase_invoices TO anon;
GRANT ALL ON TABLE public.purchase_invoices TO authenticated;
GRANT ALL ON TABLE public.purchase_invoices TO service_role;


--
-- Name: TABLE scrap_disposal; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_disposal TO anon;
GRANT ALL ON TABLE public.scrap_disposal TO authenticated;
GRANT ALL ON TABLE public.scrap_disposal TO service_role;


--
-- Name: TABLE scrap_disposal_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_disposal_items TO anon;
GRANT ALL ON TABLE public.scrap_disposal_items TO authenticated;
GRANT ALL ON TABLE public.scrap_disposal_items TO service_role;


--
-- Name: TABLE scrap_excluded_parts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_excluded_parts TO anon;
GRANT ALL ON TABLE public.scrap_excluded_parts TO authenticated;
GRANT ALL ON TABLE public.scrap_excluded_parts TO service_role;


--
-- Name: TABLE scrap_inventory; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_inventory TO anon;
GRANT ALL ON TABLE public.scrap_inventory TO authenticated;
GRANT ALL ON TABLE public.scrap_inventory TO service_role;


--
-- Name: TABLE scrap_writeoff; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_writeoff TO anon;
GRANT ALL ON TABLE public.scrap_writeoff TO authenticated;
GRANT ALL ON TABLE public.scrap_writeoff TO service_role;


--
-- Name: TABLE scrap_writeoff_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scrap_writeoff_items TO anon;
GRANT ALL ON TABLE public.scrap_writeoff_items TO authenticated;
GRANT ALL ON TABLE public.scrap_writeoff_items TO service_role;


--
-- Name: TABLE sites; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sites TO anon;
GRANT ALL ON TABLE public.sites TO authenticated;
GRANT ALL ON TABLE public.sites TO service_role;


--
-- Name: TABLE sla_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sla_events TO anon;
GRANT ALL ON TABLE public.sla_events TO authenticated;
GRANT ALL ON TABLE public.sla_events TO service_role;


--
-- Name: TABLE sla_rules; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sla_rules TO anon;
GRANT ALL ON TABLE public.sla_rules TO authenticated;
GRANT ALL ON TABLE public.sla_rules TO service_role;


--
-- Name: TABLE sla_rules_config; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sla_rules_config TO anon;
GRANT ALL ON TABLE public.sla_rules_config TO authenticated;
GRANT ALL ON TABLE public.sla_rules_config TO service_role;


--
-- Name: TABLE supervisor_dashboard_stats; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.supervisor_dashboard_stats TO anon;
GRANT ALL ON TABLE public.supervisor_dashboard_stats TO authenticated;
GRANT ALL ON TABLE public.supervisor_dashboard_stats TO service_role;


--
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.suppliers TO anon;
GRANT ALL ON TABLE public.suppliers TO authenticated;
GRANT ALL ON TABLE public.suppliers TO service_role;


--
-- Name: TABLE system_settings; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.system_settings TO anon;
GRANT ALL ON TABLE public.system_settings TO authenticated;
GRANT ALL ON TABLE public.system_settings TO service_role;


--
-- Name: SEQUENCE tickets_ticket_number_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.tickets_ticket_number_seq TO anon;
GRANT ALL ON SEQUENCE public.tickets_ticket_number_seq TO authenticated;
GRANT ALL ON SEQUENCE public.tickets_ticket_number_seq TO service_role;


--
-- Name: TABLE user_settings; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_settings TO anon;
GRANT ALL ON TABLE public.user_settings TO authenticated;
GRANT ALL ON TABLE public.user_settings TO service_role;


--
-- Name: TABLE user_sites; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_sites TO anon;
GRANT ALL ON TABLE public.user_sites TO authenticated;
GRANT ALL ON TABLE public.user_sites TO service_role;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.users TO anon;
GRANT ALL ON TABLE public.users TO authenticated;
GRANT ALL ON TABLE public.users TO service_role;


--
-- Name: TABLE vehicle_sites; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.vehicle_sites TO anon;
GRANT ALL ON TABLE public.vehicle_sites TO authenticated;
GRANT ALL ON TABLE public.vehicle_sites TO service_role;


--
-- Name: TABLE vehicles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.vehicles TO anon;
GRANT ALL ON TABLE public.vehicles TO authenticated;
GRANT ALL ON TABLE public.vehicles TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: cron; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT ALL ON SEQUENCES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: cron; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT ALL ON FUNCTIONS TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: cron; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA cron GRANT ALL ON TABLES TO postgres WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- Name: issue_graphql_placeholder; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_graphql_placeholder ON sql_drop
         WHEN TAG IN ('DROP EXTENSION')
   EXECUTE FUNCTION extensions.set_graphql_placeholder();


ALTER EVENT TRIGGER issue_graphql_placeholder OWNER TO supabase_admin;

--
-- Name: issue_pg_cron_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_cron_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_cron_access();


ALTER EVENT TRIGGER issue_pg_cron_access OWNER TO supabase_admin;

--
-- Name: issue_pg_graphql_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_graphql_access ON ddl_command_end
         WHEN TAG IN ('CREATE FUNCTION')
   EXECUTE FUNCTION extensions.grant_pg_graphql_access();


ALTER EVENT TRIGGER issue_pg_graphql_access OWNER TO supabase_admin;

--
-- Name: issue_pg_net_access; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER issue_pg_net_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_net_access();


ALTER EVENT TRIGGER issue_pg_net_access OWNER TO supabase_admin;

--
-- Name: pgrst_ddl_watch; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER pgrst_ddl_watch ON ddl_command_end
   EXECUTE FUNCTION extensions.pgrst_ddl_watch();


ALTER EVENT TRIGGER pgrst_ddl_watch OWNER TO supabase_admin;

--
-- Name: pgrst_drop_watch; Type: EVENT TRIGGER; Schema: -; Owner: supabase_admin
--

CREATE EVENT TRIGGER pgrst_drop_watch ON sql_drop
   EXECUTE FUNCTION extensions.pgrst_drop_watch();


ALTER EVENT TRIGGER pgrst_drop_watch OWNER TO supabase_admin;

--
-- PostgreSQL database dump complete
--


