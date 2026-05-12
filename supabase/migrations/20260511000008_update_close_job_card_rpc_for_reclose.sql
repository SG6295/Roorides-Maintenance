BEGIN;

-- ── Scrap Inventory Module — Phase 5 ─────────────────────────────────────────
-- Migration 3/3: Update close_job_card_with_scrap for the re-close case.
--
-- A job card may be re-closed after a reopen.  On re-close, some issue_parts
-- may already have scrap entries from the previous closure.  This update:
--
--   • Classifies each issue_part into a group:
--       Group A — has a permanent-status scrap entry (sold / written_off /
--                  refurbished / sent_for_refurbishment).  Skip entirely;
--                  do NOT require a decision; leave the permanent entry alone.
--       Group B — has an in_storage scrap entry.  Requires a decision.
--                  Reverse the old in_storage entry first, then apply the
--                  new decision.
--       Group C — has only reversed scrap entries (historical residue).
--                  Requires a decision.  Apply as Phase 1 (ignore reversed).
--       Group D — no scrap entry.  Requires a decision.  Standard Phase 1.
--
--   • Updated validation step (e):
--       – p_scrap_decisions must contain exactly one entry per Group B/C/D part.
--       – p_scrap_decisions must NOT contain entries for Group A parts.
--       – New error code: DECISIONS_EXTRA_PART_PERMANENT_SCRAP.
--       – Existing DECISIONS_MISSING_PART / DECISIONS_EXTRA_PART codes
--         remain for race-condition cases.
--
--   • New return field: "reversed_scrap_ids" — list of in_storage scrap UUIDs
--     that were reversed as part of this closure.  The frontend audit logger
--     writes one UPDATE entry per reversed ID.
--
-- All existing Phase 1 validations (a)–(d) and (f)–(h) are unchanged.

CREATE OR REPLACE FUNCTION public.close_job_card_with_scrap(
    p_job_card_id     uuid,
    p_remarks         text,
    p_scrap_decisions jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
    -- (a) Caller must be maintenance_exec or super_admin
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can close job cards.',
            'details',       null
        )::text;
    END IF;

    -- (b) Job card must exist and be Open
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

    -- (c) Outsource jobs require an invoice_url before closure
    IF v_job_card.type = 'Outsource' AND v_job_card.invoice_url IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_REQUIRED',
            'error_message', 'Outsource job cards require an invoice before closure.',
            'details',       null
        )::text;
    END IF;

    -- (d) Every issue linked to this job card must be Done
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

    -- (e) Classify parts and validate decisions array.

    -- All issue_part IDs currently on this job card.
    SELECT coalesce(array_agg(ip.id), '{}')
    INTO   v_issue_part_ids
    FROM   public.issue_parts ip
    JOIN   public.issues      i  ON i.id = ip.issue_id
    WHERE  i.job_card_id = p_job_card_id;

    -- Group A: parts that already have a permanent-status scrap entry.
    -- These must be skipped — the existing permanent entry stays untouched.
    SELECT coalesce(array_agg(ip.id), '{}')
    INTO   v_group_a_ids
    FROM   public.issue_parts ip
    JOIN   public.issues      i  ON i.id = ip.issue_id
    WHERE  i.job_card_id = p_job_card_id
      AND  public.get_blocking_scrap_for_issue_part(ip.id) IS NOT NULL;

    -- Groups B/C/D: parts that require a decision (everything not in Group A).
    SELECT coalesce(array_agg(id), '{}')
    INTO   v_required_part_ids
    FROM   unnest(v_issue_part_ids) AS id
    WHERE  id != ALL(v_group_a_ids);

    -- Decision part IDs submitted by the caller.
    SELECT coalesce(array_agg((d->>'issue_part_id')::uuid), '{}')
    INTO   v_decision_part_ids
    FROM   jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb)) AS d;

    -- Guard: caller included a Group A part in the decisions array.
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

    -- Guard: a required part (B/C/D) is missing from decisions — race condition
    -- (part added while the modal was open).
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

    -- Guard: a decision references a part no longer on this job card at all —
    -- race condition (part removed while the modal was open).
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

    -- (f, g, h) Per-decision field validation (unchanged from Phase 1)
    FOR v_decision IN
        SELECT * FROM jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb))
    LOOP
        v_action        := v_decision->>'action';
        v_issue_part_id := (v_decision->>'issue_part_id')::uuid;

        -- (f) Exclude action must have a reason
        IF v_action = 'exclude' AND (v_decision->>'exclusion_reason') IS NULL THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'MISSING_EXCLUSION_REASON',
                'error_message', 'Exclusion reason is required for excluded parts.',
                'details',       json_build_object('issue_part_id', v_issue_part_id)
            )::text;
        END IF;

        -- (g) Scrap on an Outsource job must have an outsource disposition
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

        -- (h) retained_by_vendor_with_credit requires a positive credit amount
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

    -- ── All validation passed.  Execute operations atomically. ────────────────

    -- 1. Close the job card (unchanged)
    UPDATE public.job_cards
    SET    status       = 'Completed',
           completed_at = now(),
           remarks      = p_remarks
    WHERE  id = p_job_card_id;

    -- 2+3. Process each decision.
    --      For Group B parts (in_storage scrap): reverse the old entry first,
    --      then create a fresh record per the new decision.
    --      For Groups C/D: no existing in_storage row — UPDATE touches nothing.
    FOR v_decision IN
        SELECT * FROM jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb))
    LOOP
        v_action        := v_decision->>'action';
        v_issue_part_id := (v_decision->>'issue_part_id')::uuid;

        -- Reverse any existing in_storage scrap for this part line (Group B).
        -- For Groups C/D this UPDATE matches zero rows — no harm done.
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

            -- 2a. Write outsource disposition back to issue_parts (Outsource only)
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

            -- 2b. Create fresh scrap_inventory row
            INSERT INTO public.scrap_inventory (
                source_ticket_id,
                source_job_card_id,
                source_issue_id,
                source_issue_part_id,
                source_vehicle_number,
                part_id_snapshot,
                part_name_snapshot,
                part_number_snapshot,
                quantity_snapshot,
                unit_snapshot,
                status,
                outsource_part_disposition_snapshot,
                outsource_vendor_credit_amount_snapshot,
                created_by
            )
            SELECT
                i.ticket_id,
                jc.id,
                ip.issue_id,
                ip.id,
                jc.vehicle_number,
                p.id,
                p.name,
                p.part_number,
                ip.quantity_used,
                p.unit,
                'in_storage'::scrap_item_status,
                CASE WHEN jc.type = 'Outsource'
                     THEN (v_decision->>'outsource_disposition')::outsource_part_disposition
                     ELSE NULL
                END,
                CASE WHEN jc.type = 'Outsource'
                          AND (v_decision->>'outsource_disposition') = 'retained_by_vendor_with_credit'
                     THEN (v_decision->>'outsource_credit_amount')::numeric
                     ELSE NULL
                END,
                auth.uid()
            FROM  public.issue_parts ip
            JOIN  public.issues      i  ON i.id  = ip.issue_id
            JOIN  public.job_cards   jc ON jc.id = i.job_card_id
            JOIN  public.parts       p  ON p.id  = ip.part_id
            WHERE ip.id = v_issue_part_id
            RETURNING id INTO v_new_id;

            v_scrap_ids := v_scrap_ids || v_new_id;

        ELSIF v_action = 'exclude' THEN

            -- 3. Create scrap_excluded_parts row.
            --    Previous exclusion rows for earlier closures are left untouched
            --    (they are historical audit entries).
            INSERT INTO public.scrap_excluded_parts (
                source_job_card_id,
                source_issue_id,
                source_issue_part_id,
                part_id_snapshot,
                part_name_snapshot,
                quantity_snapshot,
                reason,
                notes,
                excluded_by
            )
            SELECT
                jc.id,
                ip.issue_id,
                ip.id,
                p.id,
                p.name,
                ip.quantity_used,
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

REVOKE ALL    ON FUNCTION public.close_job_card_with_scrap(uuid, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.close_job_card_with_scrap(uuid, text, jsonb) TO authenticated;

-- ── Verification ─────────────────────────────────────────────────────────────

SELECT routine_name, security_type, routine_definition IS NOT NULL AS has_body
FROM   information_schema.routines
WHERE  routine_schema = 'public'
  AND  routine_name   = 'close_job_card_with_scrap';

ROLLBACK; -- change to COMMIT once output looks correct
