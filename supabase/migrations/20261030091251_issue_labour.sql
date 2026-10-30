-- MAIN-116: record which mechanics/electricians worked on an in-house work item, for
-- how long, and the day the work item was completed.
--
-- issues.labour_hours stays as it is: it holds the hours logged before this change, with
-- no person attached, and the app shows it as "Unattributed" on a work item that has no
-- issue_labour rows. Nothing writes it any more.

-- ── Activity complete date ──────────────────────────────────────────────────────────

ALTER TABLE public.issues ADD COLUMN completed_on date;

COMMENT ON COLUMN public.issues.completed_on IS
    'Day the work item was completed (IST). Set when status becomes Done, cleared when it leaves Done; the exec may change it. Labour analytics place hours by this date.';

CREATE FUNCTION public.set_issue_completed_on() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
    IF NEW.status::text <> 'Done' THEN
        NEW.completed_on := NULL;
        RETURN NEW;
    END IF;

    -- On reaching Done the row carries the NULL it was cleared to, so this stamps today
    -- unless the caller sent a date of its own.
    IF NEW.completed_on IS NULL THEN
        NEW.completed_on := v_today;
    END IF;

    IF NEW.completed_on > v_today THEN
        RAISE EXCEPTION 'The completion date cannot be in the future.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_set_issue_completed_on
    BEFORE INSERT OR UPDATE OF status, completed_on ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.set_issue_completed_on();

-- Backfill: nothing recorded when a work item was marked Done, so the job card's
-- completion is the closest record. completed_at is `timestamp without time zone`
-- holding UTC. The ticket-status trigger fires on every issue UPDATE and could move
-- stale tickets along, so it is switched off for this one statement.
ALTER TABLE public.issues DISABLE TRIGGER trigger_update_ticket_status;

UPDATE public.issues i
SET    completed_on = (jc.completed_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Kolkata')::date
FROM   public.job_cards jc
WHERE  jc.id = i.job_card_id
AND    i.status = 'Done'
AND    jc.completed_at IS NOT NULL;

ALTER TABLE public.issues ENABLE TRIGGER trigger_update_ticket_status;

-- ── Labour per technician ───────────────────────────────────────────────────────────

CREATE TABLE public.issue_labour (
    id            uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    issue_id      uuid NOT NULL REFERENCES public.issues(id) ON DELETE CASCADE,
    technician_id uuid NOT NULL REFERENCES public.users(id),
    hours         numeric(5,2) NOT NULL,
    created_by    uuid DEFAULT auth.uid() REFERENCES public.users(id),
    created_at    timestamp with time zone DEFAULT now() NOT NULL,
    updated_at    timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT issue_labour_hours_check CHECK (hours > 0 AND hours <= 24),
    CONSTRAINT issue_labour_issue_technician_key UNIQUE (issue_id, technician_id)
);

CREATE INDEX idx_issue_labour_technician ON public.issue_labour (technician_id);

CREATE TRIGGER issue_labour_set_updated_at
    BEFORE UPDATE ON public.issue_labour
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Only an active mechanic or electrician can be recorded, and only on a work item of an
-- in-house job card. The role is checked when the person is set, not afterwards, so a
-- technician who later leaves keeps their history.
CREATE FUNCTION public.guard_issue_labour() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_type text;
BEGIN
    SELECT jc.type::text INTO v_type
    FROM   public.issues i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  i.id = NEW.issue_id;

    IF v_type IS DISTINCT FROM 'InHouse' THEN
        RAISE EXCEPTION 'Labour can only be recorded on a work item of an in-house job card.';
    END IF;

    IF TG_OP = 'INSERT' OR NEW.technician_id IS DISTINCT FROM OLD.technician_id THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.users
            WHERE  id = NEW.technician_id
            AND    role IN ('mechanic', 'electrician')
            AND    is_active
        ) THEN
            RAISE EXCEPTION 'Only an active mechanic or electrician can be recorded against labour.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_issue_labour
    BEFORE INSERT OR UPDATE ON public.issue_labour
    FOR EACH ROW EXECUTE FUNCTION public.guard_issue_labour();

-- Every change goes to the ticket's timeline. It is written as an 'issues' UPDATE keyed
-- by the ticket, with a single `labour` field, because that is the shape TicketTimeline
-- already renders ("Labour: Empty → Mechanical Manoj 2 h").
CREATE FUNCTION public.log_issue_labour_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_issue public.issues%ROWTYPE;
    v_old   text;
    v_new   text;
BEGIN
    SELECT * INTO v_issue FROM public.issues WHERE id = coalesce(NEW.issue_id, OLD.issue_id);
    -- The issue itself is being deleted (cascade): its own deletion is the record.
    IF NOT FOUND THEN
        RETURN coalesce(NEW, OLD);
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT u.name || ' ' || trim_scale(OLD.hours) || ' h' INTO v_old
        FROM public.users u WHERE u.id = OLD.technician_id;
    END IF;
    IF TG_OP IN ('UPDATE', 'INSERT') THEN
        SELECT u.name || ' ' || trim_scale(NEW.hours) || ' h' INTO v_new
        FROM public.users u WHERE u.id = NEW.technician_id;
    END IF;

    IF v_old IS NOT DISTINCT FROM v_new THEN
        RETURN coalesce(NEW, OLD);
    END IF;

    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
    VALUES ('issues', v_issue.ticket_id, 'UPDATE',
            jsonb_build_object('issue_number', v_issue.issue_number, 'description', v_issue.description, 'labour', v_old),
            jsonb_build_object('issue_number', v_issue.issue_number, 'description', v_issue.description, 'labour', v_new),
            array['labour'],
            auth.uid());

    RETURN coalesce(NEW, OLD);
END;
$$;

CREATE TRIGGER issue_labour_audit
    AFTER INSERT OR UPDATE OR DELETE ON public.issue_labour
    FOR EACH ROW EXECUTE FUNCTION public.log_issue_labour_change();

-- Switching a card to Outsource removes its labour in the same statement; the exec has
-- already confirmed it in the app, and issue_labour_audit records each removed row.
CREATE FUNCTION public.clear_labour_on_outsource() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    IF OLD.type = 'InHouse' AND NEW.type = 'Outsource' THEN
        DELETE FROM public.issue_labour
        WHERE  issue_id IN (SELECT id FROM public.issues WHERE job_card_id = NEW.id);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_clear_labour_on_outsource
    AFTER UPDATE OF type ON public.job_cards
    FOR EACH ROW EXECUTE FUNCTION public.clear_labour_on_outsource();

-- ── Access ──────────────────────────────────────────────────────────────────────────

ALTER TABLE public.issue_labour ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Execs manage issue labour" ON public.issue_labour
    USING (public.is_maintenance_exec()) WITH CHECK (public.is_maintenance_exec());

CREATE POLICY "Finance view issue labour" ON public.issue_labour
    FOR SELECT USING (public.is_finance());

CREATE POLICY "Technicians view own labour" ON public.issue_labour
    FOR SELECT USING (technician_id = auth.uid());

-- A technician sees the job cards they have labour on. SECURITY DEFINER so the policies
-- below don't recurse through issue_labour → issues → job_cards RLS.
CREATE FUNCTION public.has_labour_on_job_card(p_job_card_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM   public.issue_labour il
        JOIN   public.issues i ON i.id = il.issue_id
        WHERE  i.job_card_id = p_job_card_id
        AND    il.technician_id = auth.uid()
    );
$$;

CREATE POLICY "Technicians view cards with their labour" ON public.job_cards
    FOR SELECT USING (public.has_labour_on_job_card(id));

CREATE POLICY "Technicians view issues on cards with their labour" ON public.issues
    FOR SELECT USING (job_card_id IS NOT NULL AND public.has_labour_on_job_card(job_card_id));

CREATE POLICY "Technicians view issue parts on cards with their labour" ON public.issue_parts
    FOR SELECT USING (EXISTS (
        SELECT 1 FROM public.issues i
        WHERE  i.id = issue_parts.issue_id
        AND    public.has_labour_on_job_card(i.job_card_id)
    ));
