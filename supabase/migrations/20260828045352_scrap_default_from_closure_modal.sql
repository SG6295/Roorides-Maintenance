-- MAIN-56: Scrap-exclusion defaults can be set from the job card closure modal
--
-- MAIN-55 put the "always exclude this part" decision in the part master, but the
-- only place to set it is the Parts Catalog. Parts are added continuously, so a
-- workflow that needs a separate trip to the catalog will not be kept up — the
-- defaults go stale and the per-card data-entry burden comes back. The moment an
-- exec knows a part is always a consumable is while they are excluding it on a
-- card, so the control belongs there.
--
-- Each decision entry may now carry `set_as_default` or `clear_default`, and the
-- part master is updated inside this function's transaction. That is deliberate:
-- a client-side write after the RPC returned could half-apply, leaving a standing
-- default behind from a closure that failed.
--
-- No DROP FUNCTION here, and none is needed. Adding a *parameter* to this
-- function under CREATE OR REPLACE creates a second overload rather than
-- replacing the first — that is how the orphan MAIN-57 had to drop came about.
-- The new fields live inside the p_scrap_decisions jsonb payload, so the
-- parameter list is untouched and this is a true replace of the single
-- 4-argument signature.

CREATE OR REPLACE FUNCTION public.close_job_card_with_scrap(
    p_job_card_id     uuid,
    p_remarks         text,
    p_scrap_decisions jsonb,
    p_invoice_pending boolean DEFAULT false
) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card              job_cards%ROWTYPE;
    v_decision              jsonb;
    v_issue_part_id         uuid;
    v_action                text;
    v_set_default           boolean;
    v_clear_default         boolean;
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
    v_conflicting_part_ids  uuid[];
    v_part_default          record;
    v_part_name             text;
    v_old_flag              boolean;
    v_old_reason            public.scrap_exclusion_reason;
    v_default_changes       jsonb := '[]'::jsonb;
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

    IF NOT p_invoice_pending AND v_job_card.type = 'Outsource' AND v_job_card.invoice_url IS NULL THEN
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
        v_set_default   := coalesce((v_decision->>'set_as_default')::boolean, false);
        v_clear_default := coalesce((v_decision->>'clear_default')::boolean, false);

        IF v_action = 'exclude' AND (v_decision->>'exclusion_reason') IS NULL THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'MISSING_EXCLUSION_REASON',
                'error_message', 'Exclusion reason is required for excluded parts.',
                'details',       json_build_object('issue_part_id', v_issue_part_id)
            )::text;
        END IF;

        IF v_action = 'exclude'
           AND (v_decision->>'exclusion_reason') = 'other'
           AND btrim(coalesce(v_decision->>'exclusion_notes', '')) = ''
        THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'MISSING_EXCLUSION_NOTES',
                'error_message', 'A note is required when the exclusion reason is "Other".',
                'details',       json_build_object('issue_part_id', v_issue_part_id)
            )::text;
        END IF;

        -- Setting and clearing the same part's default in one decision has no
        -- sensible resolution, so it is rejected rather than silently ordered.
        IF v_set_default AND v_clear_default THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'CONFLICTING_DEFAULT_DIRECTIVE',
                'error_message', 'A decision cannot both set and clear the part default.',
                'details',       json_build_object('issue_part_id', v_issue_part_id)
            )::text;
        END IF;

        -- Mirrors parts_default_exclusion_reason_check. Without this the payload
        -- would reach the UPDATE and fail on the raw constraint, which surfaces
        -- to the exec as an untranslatable Postgres error instead of a message.
        -- `clear_default` is deliberately not tied to an action: it only ever
        -- clears, so it cannot violate the constraint, and coupling it to
        -- action = 'scrap' would be a server rule whose only justification is
        -- the shape of today's modal.
        IF v_set_default THEN
            IF v_action <> 'exclude'
               OR (v_decision->>'exclusion_reason') IS NULL
               OR (v_decision->>'exclusion_reason') NOT IN ('consumable', 'destroyed_on_removal')
            THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'INVALID_DEFAULT_REASON',
                    'error_message', 'A part default can only be set on an excluded part, with reason "Consumable" or "Destroyed on removal".',
                    'details',       json_build_object(
                        'issue_part_id',    v_issue_part_id,
                        'action',           v_action,
                        'exclusion_reason', v_decision->>'exclusion_reason'
                    )
                )::text;
            END IF;
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

    -- A part can appear on a job card more than once, so two decisions can carry
    -- directives for the same part. The modal keys its checkbox by part and
    -- cannot produce a disagreement, but this function is reachable directly
    -- over PostgREST. Letting the last one win would record a coincidence of
    -- payload ordering as a standing decision about the part.
    WITH directives AS (
        SELECT ip.part_id,
               CASE WHEN coalesce((d->>'set_as_default')::boolean, false)
                    THEN 'set:' || (d->>'exclusion_reason')
                    ELSE 'clear'
               END AS directive
        FROM   jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb)) AS d
        JOIN   public.issue_parts ip ON ip.id = (d->>'issue_part_id')::uuid
        WHERE  coalesce((d->>'set_as_default')::boolean, false)
            OR coalesce((d->>'clear_default')::boolean, false)
    )
    SELECT array_agg(part_id)
    INTO   v_conflicting_part_ids
    FROM   (
        SELECT part_id
        FROM   directives
        GROUP  BY part_id
        HAVING count(DISTINCT directive) > 1
    ) c;

    IF v_conflicting_part_ids IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'CONFLICTING_PART_DEFAULTS',
            'error_message', 'The same part was given two different default instructions in one closure.',
            'details',       json_build_object('part_ids', v_conflicting_part_ids)
        )::text;
    END IF;

    UPDATE public.job_cards
    SET    status       = CASE WHEN p_invoice_pending
                               THEN 'Completed - Invoice Pending'::public.job_card_status
                               ELSE 'Completed'::public.job_card_status
                          END,
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
                reason, notes, from_part_default, excluded_by
            )
            SELECT
                jc.id, ip.issue_id, ip.id, p.id, p.name, ip.quantity_used,
                (v_decision->>'exclusion_reason')::scrap_exclusion_reason,
                v_decision->>'exclusion_notes',
                coalesce((v_decision->>'from_default')::boolean, false),
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

    -- Part master updates, last and still inside this transaction. Both columns
    -- are always written together: parts_default_exclusion_reason_check requires
    -- a reason exactly when the flag is set, so clearing must null the reason and
    -- setting must supply one.
    FOR v_part_default IN
        WITH directives AS (
            SELECT DISTINCT
                   ip.part_id,
                   coalesce((d->>'set_as_default')::boolean, false) AS set_default,
                   CASE WHEN coalesce((d->>'set_as_default')::boolean, false)
                        THEN (d->>'exclusion_reason')::public.scrap_exclusion_reason
                        ELSE NULL::public.scrap_exclusion_reason
                   END AS reason
            FROM   jsonb_array_elements(coalesce(p_scrap_decisions, '[]'::jsonb)) AS d
            JOIN   public.issue_parts ip ON ip.id = (d->>'issue_part_id')::uuid
            WHERE  coalesce((d->>'set_as_default')::boolean, false)
                OR coalesce((d->>'clear_default')::boolean, false)
        )
        SELECT part_id, set_default, reason FROM directives
    LOOP
        SELECT p.name, p.default_exclude_from_scrap, p.default_exclusion_reason
        INTO   v_part_name, v_old_flag, v_old_reason
        FROM   public.parts p
        WHERE  p.id = v_part_default.part_id;

        -- A directive that asks for the state the part is already in is not a
        -- change, and reporting it would put an audit row on the record saying
        -- nothing happened.
        CONTINUE WHEN v_old_flag   IS NOT DISTINCT FROM v_part_default.set_default
                  AND v_old_reason IS NOT DISTINCT FROM v_part_default.reason;

        UPDATE public.parts
        SET    default_exclude_from_scrap = v_part_default.set_default,
               default_exclusion_reason   = v_part_default.reason
        WHERE  id = v_part_default.part_id;

        v_default_changes := v_default_changes || jsonb_build_object(
            'part_id',     v_part_default.part_id,
            'part_name',   v_part_name,
            'old_exclude', v_old_flag,
            'old_reason',  v_old_reason,
            'new_exclude', v_part_default.set_default,
            'new_reason',  v_part_default.reason
        );
    END LOOP;

    RETURN json_build_object(
        'success',               true,
        'job_card_id',           p_job_card_id,
        'scrap_entry_ids',       v_scrap_ids,
        'exclusion_ids',         v_exclusion_ids,
        'reversed_scrap_ids',    v_reversed_scrap_ids,
        'part_default_changes',  v_default_changes
    );
END;
$$;
