-- MAIN-118: the invoice history shows when the invoice reached finance.
--
-- submitted_on joins the fields outsource_invoices_audit logs, so the submission
-- (job card completion, finalize, or a multi-vehicle invoice's first save) appears as
-- an entry — together with the starting status and remark when maintenance had set
-- Hold or Reject. Signature unchanged, so replaced in place.

create or replace function public.log_outsource_invoice_change() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_fields  text[] := array[
        'maintenance_payment_status', 'finance_payment_status', 'finance_remark', 'paid_by',
        'invoice_value', 'approved_amount', 'advance_amount', 'payby_date', 'submitted_on'
    ];
    v_new     jsonb := to_jsonb(NEW);
    v_old     jsonb;
    v_changed text[];
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_logs (table_name, record_id, action, new_data, performed_by)
        VALUES ('outsource_invoices', NEW.id, 'INSERT',
                (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_fields) f),
                auth.uid());
        RETURN NEW;
    END IF;

    v_old := to_jsonb(OLD);
    SELECT array_agg(f) INTO v_changed
    FROM   unnest(v_fields) f
    WHERE  v_new->f IS DISTINCT FROM v_old->f;

    IF v_changed IS NULL THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
    VALUES ('outsource_invoices', NEW.id, 'UPDATE',
            (SELECT jsonb_object_agg(f, v_old->f) FROM unnest(v_changed) f),
            (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_changed) f),
            v_changed,
            auth.uid());
    RETURN NEW;
END;
$$;
