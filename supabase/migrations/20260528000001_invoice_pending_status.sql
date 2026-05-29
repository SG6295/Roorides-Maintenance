-- Migration: Add 'Completed - Invoice Pending' status for outsource job cards
--
-- When work is done but the vendor invoice has not yet been received, the exec
-- can now close the job card operationally (stopping the SLA timer) without the
-- invoice. The invoice can be added later, and the card finalized to 'Completed'.

-- ── 1. Enum ──────────────────────────────────────────────────────────────────

ALTER TYPE public.job_card_status ADD VALUE 'Completed - Invoice Pending';

-- ── 2. Replace close_job_card_with_scrap ─────────────────────────────────────
-- Adds p_invoice_pending boolean (default false). When true, skips the
-- invoice_url check and sets status = 'Completed - Invoice Pending' instead
-- of 'Completed'. All other logic is identical.

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

-- ── 3. New RPC: finalize_outsource_invoice ───────────────────────────────────
-- Transitions a 'Completed - Invoice Pending' outsource job card to 'Completed'
-- once the invoice file and all required details have been provided.

CREATE OR REPLACE FUNCTION public.finalize_outsource_invoice(
    p_job_card_id uuid,
    p_remarks     text DEFAULT null
) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
       OR v_invoice.invoice_no       IS NULL
       OR v_invoice.invoice_value    IS NULL
       OR v_invoice.approved_amount  IS NULL
       OR v_invoice.advance_amount   IS NULL
       OR v_invoice.date_of_activity IS NULL
       OR v_invoice.payby_date       IS NULL
       OR v_invoice.payment_status   IS NULL
       OR v_invoice.paid_by          IS NULL
    THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_DETAILS_INCOMPLETE',
            'error_message', 'Invoice details are incomplete. Please fill in all required fields before finalizing.',
            'details',       null
        )::text;
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
$$;
