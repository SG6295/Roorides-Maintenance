-- Outsourced job cards no longer need an invoice of their own to close.
--
-- Closing with no invoice lands the card in 'Completed - Invoice Pending', as the
-- separate "Close — Invoice Pending" button used to. A card linked to a multi-vehicle
-- invoice line is billed there, so it closes fully as 'Completed' with no invoice of its
-- own and is never put in Invoice Pending; an Invoice Pending card that gets linked later
-- can be finalized without one.
--
-- outsource_completion_requires_invoice is dropped: a CHECK sees only its own row, so it
-- cannot tell a card is covered by a multi-vehicle invoice. close_job_card_with_scrap and
-- finalize_outsource_invoice — the only paths to 'Completed' — hold the rule instead.
--
-- If a card was completed on the strength of that link and the link goes away (the line
-- is unlinked or removed, or the invoice is cancelled, which releases every link), the
-- card drops back to Invoice Pending. That is a deferred constraint trigger, so it judges
-- the state at commit: a save that moves a link from one line to another must not demote
-- the card in between. Restoring the invoice does not promote the card back; the exec
-- finalizes it.

alter table public.job_cards drop constraint outsource_completion_requires_invoice;

CREATE OR REPLACE FUNCTION public.close_job_card_with_scrap(p_job_card_id uuid, p_remarks text, p_scrap_decisions jsonb, p_invoice_pending boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    v_batch_linked          boolean;
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

    -- A multi-vehicle invoice line linked to this card bills its work, so the card can
    -- close fully without an invoice of its own, and Invoice Pending makes no sense.
    v_batch_linked := EXISTS (
        SELECT 1 FROM public.batch_service_vehicles WHERE job_card_id = p_job_card_id
    );

    IF p_invoice_pending AND v_batch_linked THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'BATCH_LINKED',
            'error_message', 'This job card is billed on a multi-vehicle invoice, so it cannot be closed as Invoice Pending.',
            'details',       null
        )::text;
    END IF;

    IF NOT p_invoice_pending AND NOT v_batch_linked
       AND v_job_card.type = 'Outsource' AND v_job_card.invoice_url IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_REQUIRED',
            'error_message', 'Outsource job cards need an invoice, or a multi-vehicle invoice line, to close fully. Close it as Invoice Pending instead.',
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
$function$;

CREATE OR REPLACE FUNCTION public.finalize_outsource_invoice(p_job_card_id uuid, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_job_card job_cards%ROWTYPE;
    v_invoice  outsource_invoices%ROWTYPE;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can finalize outsource invoices.',
            'details',       null
        )::text;
    END IF;

    SELECT * INTO v_job_card
    FROM   public.job_cards
    WHERE  id     = p_job_card_id
      AND  status = 'Completed - Invoice Pending'
      AND  type   = 'Outsource';

    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'JOB_CARD_NOT_ELIGIBLE',
            'error_message', 'Job card not found or is not an Outsource card with status "Completed - Invoice Pending".',
            'details',       null
        )::text;
    END IF;

    -- A linked multi-vehicle invoice line bills the work, so the card's own invoice is
    -- not needed to finalize.
    IF NOT EXISTS (
        SELECT 1 FROM public.batch_service_vehicles WHERE job_card_id = p_job_card_id
    ) THEN
        IF v_job_card.invoice_url IS NULL THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVOICE_FILE_REQUIRED',
                'error_message', 'An invoice file must be uploaded before finalizing.',
                'details',       null
            )::text;
        END IF;

        SELECT * INTO v_invoice
        FROM   public.outsource_invoices
        WHERE  job_card_id = p_job_card_id;

        IF NOT FOUND
           OR v_invoice.invoice_no                 IS NULL
           OR v_invoice.invoice_value              IS NULL
           OR v_invoice.approved_amount            IS NULL
           OR v_invoice.advance_amount             IS NULL
           OR v_invoice.date_of_activity           IS NULL
           OR v_invoice.payby_date                 IS NULL
           OR v_invoice.maintenance_payment_status IS NULL
           OR v_invoice.paid_by                    IS NULL
        THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVOICE_DETAILS_INCOMPLETE',
                'error_message', 'Invoice details are incomplete. Please fill in all required fields before finalizing.',
                'details',       null
            )::text;
        END IF;
    END IF;

    UPDATE public.job_cards
    SET    status  = 'Completed',
           remarks = coalesce(p_remarks, remarks)
    WHERE  id = p_job_card_id;

    RETURN json_build_object(
        'success',     true,
        'job_card_id', p_job_card_id
    );
END;
$function$;

create or replace function public.demote_job_card_on_batch_unlink()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
BEGIN
    IF OLD.job_card_id IS NULL
       OR (TG_OP = 'UPDATE' AND NEW.job_card_id IS NOT DISTINCT FROM OLD.job_card_id) THEN
        RETURN NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM public.batch_service_vehicles WHERE job_card_id = OLD.job_card_id) THEN
        RETURN NULL;
    END IF;

    -- A card with its own complete invoice stays Completed.
    UPDATE public.job_cards jc
    SET    status = 'Completed - Invoice Pending'
    WHERE  jc.id     = OLD.job_card_id
      AND  jc.type   = 'Outsource'
      AND  jc.status = 'Completed'
      AND  (jc.invoice_url IS NULL
            OR NOT EXISTS (SELECT 1 FROM public.outsource_invoices oi WHERE oi.job_card_id = jc.id));

    IF FOUND THEN
        INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
        VALUES ('job_cards', OLD.job_card_id, 'UPDATE',
                jsonb_build_object('status', 'Completed'),
                jsonb_build_object('status', 'Completed - Invoice Pending',
                                   'reason', 'Multi-vehicle invoice link removed'),
                array['status'], auth.uid());
    END IF;

    RETURN NULL;
END;
$function$;

create constraint trigger batch_service_vehicles_demote_job_card
    after update of job_card_id or delete on public.batch_service_vehicles
    deferrable initially deferred
    for each row execute function public.demote_job_card_on_batch_unlink();
