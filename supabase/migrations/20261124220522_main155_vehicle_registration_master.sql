-- MAIN-155 Vehicle Registration Master (epic MAIN-154, two companies).
--
-- Every vehicle belongs to NVS Travels, NVS Travel Solutions Pvt Ltd, or is Unknown.
--   * vehicles.company — the vehicle's company now. Unknown until finance assigns it; the
--     Roorides sync never sends the column, so a new vehicle arrives Unknown and an existing
--     one keeps its company.
--   * vehicle_company_changes — every change, with who, when, old/new and any sale value.
--     It is also what MAIN-156 (sales in the company ledgers) and MAIN-160 (transfers when an
--     Unknown vehicle is first assigned to Pvt Ltd) will read.
--   * set_vehicle_company(p_vehicle_id, p_change jsonb) — the only way to change it, for
--     finance and super_admin. Unknown → a company is an assignment; between the companies
--     is a sale (value incl. GST + GST %), refused while the vehicle has open work.
--   * guard_unassigned_vehicle — no write on an Unknown vehicle's tickets, work items, job
--     cards, spares, labour or multi-vehicle invoice lines, open work included. The database
--     functions that keep SLA deadlines and statuses current still run.
--   * The first load, from the sheet "NVS TRAVELS_FLEET DETAILS" / "NVS TRAVELS PVT LTD".
--
-- p_change is jsonb on purpose: do not add a parameter — CREATE OR REPLACE would leave a
-- second overload behind.

-- ── The company on each vehicle ─────────────────────────────────────────────────────────

ALTER TABLE public.vehicles
    ADD COLUMN company text NOT NULL DEFAULT 'unknown';

ALTER TABLE public.vehicles
    ADD CONSTRAINT vehicles_company_check
    CHECK (company IN ('nvs_travels', 'nvs_travel_solutions', 'unknown'));

COMMENT ON COLUMN public.vehicles.company IS
    'MAIN-155: nvs_travels | nvs_travel_solutions | unknown. Changed only through set_vehicle_company (finance, super_admin); the Roorides sync never writes it.';

-- Execs hold UPDATE on vehicles (year and notes), and RLS gates rows, not columns — so the
-- company is guarded here. set_vehicle_company raises a transaction-local flag; service-role
-- and migration writes (no auth.uid()) pass, as every guard in this schema allows.
CREATE OR REPLACE FUNCTION public.guard_vehicle_company()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
AS $$
BEGIN
    IF auth.uid() IS NULL
       OR current_setting('app.vehicle_company_change', true) = 'on' THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.company <> 'unknown' THEN
            RAISE EXCEPTION 'A new vehicle starts as Unknown; finance assigns its company in the Vehicle Registration Master.';
        END IF;
    ELSIF NEW.company IS DISTINCT FROM OLD.company THEN
        RAISE EXCEPTION 'Only finance can change a vehicle''s company, from the Vehicle Registration Master.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_vehicle_company
    BEFORE INSERT OR UPDATE OF company ON public.vehicles
    FOR EACH ROW EXECUTE FUNCTION public.guard_vehicle_company();

-- ── History ─────────────────────────────────────────────────────────────────────────────
-- performed_by is deliberately not a foreign key, and names are snapshotted, so history
-- survives a user being deleted or renamed (the user_audit_logs convention).

CREATE TABLE public.vehicle_company_changes (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    vehicle_id          uuid NOT NULL REFERENCES public.vehicles(id),
    registration_number text NOT NULL,
    old_company         text NOT NULL,
    new_company         text NOT NULL,
    kind                text NOT NULL,
    sale_value          numeric(14,2),
    gst_percent         numeric(5,2),
    performed_by        uuid,
    performed_by_name   text,
    created_at          timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vehicle_company_changes_company_check
        CHECK (old_company IN ('nvs_travels', 'nvs_travel_solutions', 'unknown')
           AND new_company IN ('nvs_travels', 'nvs_travel_solutions')
           AND old_company <> new_company),
    CONSTRAINT vehicle_company_changes_kind_check
        CHECK (kind IN ('initial_load', 'assignment', 'sale')),
    -- An assignment (or the first load) is from Unknown and has no sale; a sale is between
    -- the two companies and always has its value and GST %.
    CONSTRAINT vehicle_company_changes_sale_check
        CHECK (CASE WHEN kind = 'sale'
                    THEN old_company <> 'unknown'
                     AND sale_value > 0
                     AND gst_percent >= 0 AND gst_percent <= 100
                    ELSE old_company = 'unknown'
                     AND sale_value IS NULL AND gst_percent IS NULL
               END)
);

COMMENT ON TABLE public.vehicle_company_changes IS
    'MAIN-155: every change of vehicles.company. Written only by set_vehicle_company (and the MAIN-155 first load); readable by every signed-in user.';

CREATE INDEX vehicle_company_changes_vehicle_idx
    ON public.vehicle_company_changes (vehicle_id, created_at DESC);
CREATE INDEX vehicle_company_changes_created_idx
    ON public.vehicle_company_changes (created_at DESC);

ALTER TABLE public.vehicle_company_changes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Signed-in users view vehicle company changes"
    ON public.vehicle_company_changes FOR SELECT
    USING (auth.uid() IS NOT NULL);

-- ── Open work on a vehicle ──────────────────────────────────────────────────────────────
-- Open = a ticket that is New, Accepted or Work In Progress, or an Open job card (Resolved
-- counts as finished). Returned as "ticket 1234, ticket 1240 and job card 3412" for the
-- refusal message, or NULL when there is none.
CREATE OR REPLACE FUNCTION public.vehicle_open_work(p_registration text)
    RETURNS text
    LANGUAGE sql STABLE
    SET search_path TO 'public'
AS $$
    SELECT CASE
        WHEN cardinality(items) = 0 THEN NULL
        WHEN cardinality(items) = 1 THEN items[1]
        ELSE array_to_string(items[1:cardinality(items) - 1], ', ') || ' and ' || items[cardinality(items)]
    END
    FROM (
    SELECT coalesce(array_agg(label ORDER BY ord, num), ARRAY[]::text[]) AS items
    FROM (
        SELECT 1 AS ord, ticket_number AS num, 'ticket ' || ticket_number AS label
        FROM tickets
        WHERE vehicle_number = p_registration
          AND status IN ('New', 'Accepted', 'Work In Progress')
        UNION ALL
        SELECT 2, job_card_number, 'job card ' || job_card_number
        FROM job_cards
        WHERE vehicle_number = p_registration
          AND status = 'Open'
    ) w
    ) a;
$$;

-- ── Changing a vehicle's company ────────────────────────────────────────────────────────
-- p_change: { company: 'nvs_travels' | 'nvs_travel_solutions',
--             sale_value?: number (incl. GST), gst_percent?: number }   (sale only)
CREATE OR REPLACE FUNCTION public.set_vehicle_company(p_vehicle_id uuid, p_change jsonb)
    RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
AS $$
DECLARE
    v_vehicle   public.vehicles%ROWTYPE;
    v_new       text := p_change->>'company';
    v_kind      text;
    v_sale      numeric;
    v_gst       numeric;
    v_open      text;
    v_name      text;
    v_row       public.vehicle_company_changes%ROWTYPE;
BEGIN
    IF NOT (public.is_finance() OR public.is_super_admin()) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only finance can change a vehicle''s company.'
        )::text;
    END IF;

    SELECT * INTO v_vehicle FROM public.vehicles WHERE id = p_vehicle_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'VEHICLE_NOT_FOUND',
            'error_message', 'Vehicle not found.'
        )::text;
    END IF;

    IF v_new = 'unknown' THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'CANNOT_UNASSIGN',
            'error_message', 'A vehicle can''t be changed back to Unknown.'
        )::text;
    END IF;

    IF v_new IS NULL OR v_new NOT IN ('nvs_travels', 'nvs_travel_solutions') THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_COMPANY',
            'error_message', 'Choose NVS Travels or NVS Travel Solutions Pvt Ltd.'
        )::text;
    END IF;

    IF v_new = v_vehicle.company THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_CHANGE',
            'error_message', 'The vehicle already belongs to that company.'
        )::text;
    END IF;

    IF v_vehicle.company = 'unknown' THEN
        -- First assignment: the vehicle always belonged to this company. Not a sale, and
        -- open work does not stop it (that work is blocked until it is assigned).
        v_kind := 'assignment';
        IF nullif(p_change->>'sale_value', '') IS NOT NULL
           OR nullif(p_change->>'gst_percent', '') IS NOT NULL THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'SALE_NOT_ALLOWED',
                'error_message', 'Assigning an Unknown vehicle is not a sale, so it takes no sale value.'
            )::text;
        END IF;
    ELSE
        v_kind := 'sale';
        IF coalesce(p_change->>'sale_value', '') !~ '^[0-9]{1,12}(\.[0-9]{1,2})?$'
           OR (p_change->>'sale_value')::numeric <= 0 THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'SALE_VALUE_REQUIRED',
                'error_message', 'Enter the sale value, including GST.'
            )::text;
        END IF;
        IF coalesce(p_change->>'gst_percent', '') !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$'
           OR (p_change->>'gst_percent')::numeric > 100 THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'GST_PERCENT_REQUIRED',
                'error_message', 'Enter the GST % of the sale, between 0 and 100.'
            )::text;
        END IF;
        v_sale := (p_change->>'sale_value')::numeric;
        v_gst  := (p_change->>'gst_percent')::numeric;

        v_open := public.vehicle_open_work(v_vehicle.registration_number);
        IF v_open IS NOT NULL THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'OPEN_WORK',
                'error_message', 'Close ' || v_open || ' first.'
            )::text;
        END IF;
    END IF;

    SELECT name INTO v_name FROM public.users WHERE id = auth.uid();

    PERFORM set_config('app.vehicle_company_change', 'on', true);
    UPDATE public.vehicles SET company = v_new WHERE id = p_vehicle_id;
    PERFORM set_config('app.vehicle_company_change', 'off', true);

    INSERT INTO public.vehicle_company_changes
        (vehicle_id, registration_number, old_company, new_company, kind,
         sale_value, gst_percent, performed_by, performed_by_name)
    VALUES
        (p_vehicle_id, v_vehicle.registration_number, v_vehicle.company, v_new, v_kind,
         v_sale, v_gst, auth.uid(), v_name)
    RETURNING * INTO v_row;

    RETURN to_jsonb(v_row);
END;
$$;

REVOKE ALL ON FUNCTION public.set_vehicle_company(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_vehicle_company(uuid, jsonb) TO authenticated;

-- ── The Unknown block ───────────────────────────────────────────────────────────────────
-- One trigger function for every table that holds work on a vehicle. A vehicle number with
-- no vehicles row is let through (the columns are free text; none exist in prod today).
CREATE OR REPLACE FUNCTION public.assert_vehicle_assigned(p_registration text)
    RETURNS void
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
AS $$
BEGIN
    IF p_registration IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.vehicles
        WHERE registration_number = p_registration AND company = 'unknown'
    ) THEN
        RAISE EXCEPTION 'Kindly contact finance to assign vehicle % in order to proceed.', p_registration
            USING HINT = 'VEHICLE_UNASSIGNED';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_unassigned_vehicle()
    RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
AS $$
DECLARE
    -- Columns only the SLA functions write (refresh_ticket_sla, the hourly refresh, a
    -- holiday change). Those keep running for an Unknown vehicle's tickets.
    c_ticket_sla constant text[] := ARRAY['final_sla_end_date', 'overall_sla_status',
                                          'acceptance_sla_status', 'acceptance_sla_end_date'];
    c_issue_sla  constant text[] := ARRAY['sla_end_date', 'sla_status', 'sla_days'];
    v_regs text[] := ARRAY[]::text[];
    v_reg  text;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN coalesce(NEW, OLD);
    END IF;

    IF TG_OP = 'UPDATE' THEN
        IF TG_TABLE_NAME = 'tickets'
           AND (to_jsonb(NEW) - c_ticket_sla) = (to_jsonb(OLD) - c_ticket_sla) THEN
            RETURN NEW;
        END IF;
        IF TG_TABLE_NAME = 'issues'
           AND (to_jsonb(NEW) - c_issue_sla) = (to_jsonb(OLD) - c_issue_sla) THEN
            RETURN NEW;
        END IF;
    END IF;

    IF TG_TABLE_NAME IN ('tickets', 'job_cards', 'batch_service_vehicles') THEN
        IF TG_OP <> 'DELETE' THEN v_regs := v_regs || NEW.vehicle_number; END IF;
        IF TG_OP <> 'INSERT' THEN v_regs := v_regs || OLD.vehicle_number; END IF;
    ELSIF TG_TABLE_NAME = 'issues' THEN
        IF TG_OP <> 'DELETE' THEN
            v_regs := v_regs || (SELECT vehicle_number FROM public.tickets WHERE id = NEW.ticket_id);
        END IF;
        IF TG_OP <> 'INSERT' THEN
            v_regs := v_regs || (SELECT vehicle_number FROM public.tickets WHERE id = OLD.ticket_id);
        END IF;
    ELSE  -- issue_parts, issue_labour: through the work item's ticket
        IF TG_OP <> 'DELETE' THEN
            v_regs := v_regs || (SELECT t.vehicle_number FROM public.issues i
                                 JOIN public.tickets t ON t.id = i.ticket_id
                                 WHERE i.id = NEW.issue_id);
        END IF;
        IF TG_OP <> 'INSERT' THEN
            v_regs := v_regs || (SELECT t.vehicle_number FROM public.issues i
                                 JOIN public.tickets t ON t.id = i.ticket_id
                                 WHERE i.id = OLD.issue_id);
        END IF;
    END IF;

    FOREACH v_reg IN ARRAY v_regs LOOP
        PERFORM public.assert_vehicle_assigned(v_reg);
    END LOOP;

    RETURN coalesce(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_guard_unassigned_vehicle
    BEFORE INSERT OR UPDATE OR DELETE ON public.tickets
    FOR EACH ROW EXECUTE FUNCTION public.guard_unassigned_vehicle();
CREATE TRIGGER trg_guard_unassigned_vehicle
    BEFORE INSERT OR UPDATE OR DELETE ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.guard_unassigned_vehicle();
CREATE TRIGGER trg_guard_unassigned_vehicle
    BEFORE INSERT OR UPDATE OR DELETE ON public.job_cards
    FOR EACH ROW EXECUTE FUNCTION public.guard_unassigned_vehicle();
CREATE TRIGGER trg_guard_unassigned_vehicle
    BEFORE INSERT OR UPDATE OR DELETE ON public.issue_parts
    FOR EACH ROW EXECUTE FUNCTION public.guard_unassigned_vehicle();
CREATE TRIGGER trg_guard_unassigned_vehicle
    BEFORE INSERT OR UPDATE OR DELETE ON public.issue_labour
    FOR EACH ROW EXECUTE FUNCTION public.guard_unassigned_vehicle();
CREATE TRIGGER trg_guard_unassigned_vehicle
    BEFORE INSERT OR UPDATE OR DELETE ON public.batch_service_vehicles
    FOR EACH ROW EXECUTE FUNCTION public.guard_unassigned_vehicle();

-- ── First load from the Google Sheet ────────────────────────────────────────────────────
-- Sheet 1vyubL3PZ0XlODXRiLIEcCxBnejomeRa-60_SGCYwqvo, column "vehicle Number", read
-- 2026-11-25. The sheet writes "KA 51 B 5997", the app "KA51B5997": matched ignoring spaces
-- and hyphens. A plate in both tabs is left Unknown for finance to decide.
WITH sheet(company, plates) AS (
    VALUES
    ('nvs_travels', ARRAY[
        'KA 51 B 5997','KA 51 B 4090','KA 51 B 4091','KA 51 C 6546','KA 51 D 3691','KA 51 B 4092','KA 51 D 3692','KA 51 D 3697',
        'KA 51 D 3709','KA 51 D 3693','KA 51 D 3685','KA 51 D 3705','KA 51 D 3701','KA 51 D 3702','KA 51 D 3700','KA 03 AD 5737',
        'KA 01 MP 7827','KA 51 D 5105','KA 51 D 3707','KA 51 D 3687','KA 51 D 3710','KA 51 D 5106','KA 51 D 5107','KA 51 D 5104',
        'KA 51 D 3694','KA 51 D 3800','KA 51 D 3706','KA 51 D 3689','KA 51 D 3708','KA 51 AB 4369','KA 51 AB 4368','KA 51 AB 4330',
        'KA 51 AB 4328','KA 51 AB 4359','KA 51 AB 4358','KA 51 AB 4373','KA 51 AB 4372','KA 51 AB 4350','KA 51 AB 4349','KA 51 AB 4361',
        'KA 51 AB 4367','KA 51 AB 4344','KA 51 AB 4366','KA 51 AB 4346','KA 51 AB 4371','KA 51 AB 4347','KA 51 AB 4374','KA 51 AB 4364',
        'KA 51 AB 4365','KA 51 AB 5066','KA 51 AK 9783','KA 51 AK 9789','KA 51 AK 9785','KA 51 AB 3542','KA 51 AB 4354','KA 51 AB 4353',
        'KA 51 AB 4352','KA 51 AB 4355','KA 51 AB 3537','KA 51 AB 3539','TN 70 AZ 6023','KA 51 AK 9784','KA 51 AK 9782','KA 51 AK 9788',
        'KA 51 AB 1454','KA 51 AB 3541','KA 51 AD 8657','KA 51 AD 8663','KA 51 AD 8662','KA 51 AD 8666','KA 51 AD 8655','KA 51 AD 8659',
        'KA 51 AD 8661','KA 51 AD 8656','KA 51 AD 8665','KA 51 AB 3538','KA 51 AB 4363','KA 51 AB 4362','KA 51 AD 8653','KA 51 AD 8664',
        'KA 51 AD 8654','KA 51 AD 8660','KA 51 AB 4327','KA 51 AB 4360','KA 51 AK 8216','KA 51 AK 8215','KA 51 AM 1214','KA 51 AK 8214',
        'KA 51 AB 3540','KA 51 AE 8746','KA 51 AF 5534','KA 51 AF 5530','KA 51 AF 5527','KA 51 AF 5532','KA 51 AF 5524','KA 51 AF 5521',
        'KA 51 AF 5531','KA 51 AF 5529','KA 51 AF 5525','KA 51 AF 3659','KA 51 AF 3658','KA 51 AE 8399','KA 51 AE 8747','KA 51 AF 3657',
        'KA 51 AE 8411','KA 51 AE 8412','KA 51 AF 5523','KA 51 AF 5528','KA 51 AB 4370','KA 51 AB 4351','KA 51 AE 8404','KA 51 AE 8430',
        'KA 51 AE 8402','KA 51 AF 1583','KA 51 AE 8405','KA 51 AF 5520','KA 51 AF 5519','KA 51 AF 5518','KA 51 AF 6805','KA 51 AF 6510',
        'KA 51 AF 6808','KA 51 AF 6811','KA 51 AF 6812','KA 51 AF 6809','KA 51 AF 6807','KA 51 AF 6780','KA 51 AF 6769','KA 51 AF 6788',
        'KA 51 AF 6776','KA 51 AF 6782','KA 51 AF 6775','KA 51 AF 6787','KA 51 AF 6783','KA 51 AF 6791','KA 51 AF 6790','KA 51 AF 6803',
        'KA 51 AF 6801','KA 51 AF 6802','KA 51 AF 6800','KA 51 AF 6794','KA 51 AF 6864','KA 51 AF 6781','KA 51 AF 6814','KA 51 AF 6770',
        'KA 51 AF 6508','KA 51 AF 6509','KA 51 AF 6810','KA 51 AF 6784','KA 51 AF 6785','KA 51 AH 4607','KA 51 AH 4608','KA 51 AH 4609',
        'KA 51 AH 4610','KA 51 AH 4611','KA 51 AH 5651','KA 51 AH 5655','KA 51 AH 5656','KA 51 AH 5772','KA 51 AH 6042','KA 51 AH 6043',
        'KA 51 AH 5654','KA 51 AH 5652','KA 51 AH 7267','KA 51 AH 7271','KA 51 AH 7268','KA 51 AH 7270','KA 51 AH 0936','KA 51 AH 0934',
        'KA 51 AH 1882','KA 51 AH 1880','KA 51 AH 1878','KA 51 AH 1879','KA 51 AH 0935','KA 51 AH 1047','KA 51 AH 1037','KA 51 AH 1046',
        'KA 51 AH 1048','KA 51 AH 1038','KA 51 AH 1049','KA 51 AH 1045','KA 51 AH 1036','KA 51 AH 1043','KA 51 AH 1040','KA 51 AH 1042',
        'KA 51 AH 1041','KA 51 AH 1044','KA 51 AH 1039','KA 51 AH 1583','KA 51 AH 1585','TN 99 W 5130','TN 99 W 5148','KA 51 AJ 1077',
        'KA 51 AJ 2147','KA 51 AJ 2148','KA 51 AJ 2145','KA 51 AJ 2146','KA 51 AJ 2174','KA 51 AJ 2173','KA 51 AJ 4309','KA 51 AJ 4305',
        'KA 51 AJ 6765','KA 51 AJ 4299','KA 51 AJ 4308','KA 51 AJ 4297','KA 51 AJ 4295','KA 51 AJ 4304','KA 51 AJ 4301','KA 51 AJ 4300',
        'KA 51 AJ 4296','KA 51 AJ 4298','KA 51 AJ 4302','KA 51 AJ 4306','KA 51 AJ 4303','KA 51 AJ 4307','KA 51 AB 1873','KA 51 AB 1869',
        'KA 51 AB 1871','KA 51 AB 1870','KA 03 AK 9602','KA 03 AK 9601','KA 51 AJ 3686','KA 51 AJ 3685','KA 51 AJ 3684','KA 51 AJ 3687',
        'KA 51 AJ 3639','KA 51 AJ 3638','KA 51 AJ 3636','KA 51 AJ 3637','KA 51 AJ 3635','KA 51 AJ 1075','KA 51 AJ 1073','KA 51 AJ 1068',
        'KA 51 AJ 1082','KA 51 AJ 1076','KA 51 AJ 1081','KA 51 AJ 1084','KA 51 AJ 1074','KA 51 AJ 1072','KA 51 AJ 1080','KA 51 AJ 1423',
        'KA 51 AJ 5579','KA 51 AJ 5623','KA 51 AJ 5624','KA 51 AJ 5625','KA 51 AJ 5621','KA 51 AJ 5622','KA 51 AJ 1465','KA 51 AJ 1433',
        'KA 51 AJ 1431','KA 51 AJ 1430','KA 51 AJ 1438','KA 51 AJ 1435','KA 51 AJ 1436','KA 51 AJ 1424','KA 51 AJ 1437','KA 51 AJ 1462',
        'KA 51 AJ 1468','KA 51 AJ 1464','KA 51 AJ 1463','KA 51 AJ 1432','KA 51 AJ 1425','KA 51 AJ 1426','KA 51 AJ 1434','KA 51 AJ 1429',
        'KA 51 AH 9717','KA 51 AJ 0408','KA 51 AJ 0407','KA 51 AJ 0404','KA 51 AJ 0403','KA 51 AJ 0401','KA 51 AJ 0406','KA 51 AJ 0398',
        'KA 51 AJ 0400','KA 51 AJ 0391','KA 51 AJ 0394','KA 51 AJ 0397','KA 51 AJ 0395','KA 51 AJ 0396','KA 51 AJ 0392','KA 51 AJ 0399',
        'KA 51 AJ 0390','KA 51 AJ 0389','KA 51 AJ 1880','KA 51 AJ 1881','KA 51 AJ 2969','KA 51 MV 5179','KA 51 AJ 7157','KA 51 AJ 7153',
        'KA 51 AJ 7150','KA 51 AJ 7158','KA 51 AJ 7159','KA 51 AJ 7149','KA 51 AJ 7160','KA 51 AJ 7156','KA 51 AJ 7154','KA 51 AJ 7148',
        'KA 51 AJ 7152','KA 51 AJ 7145','KA 51 AJ 7147','KA 51 AJ 7312','KA 51 AJ 7313','KA 51 AJ 7358','KA 51 AJ 7359','KA 51 AJ 7151',
        'KA 51 AJ 1428','KA 51 AJ 1427','KA 51 AK 9267','KA 51 AK 1487','KA 51 AK 2060','KA 51 AK 2062','KA 51 AK 2061','KA 51 AK 2268',
        'KA 51 AK 2266','KA 51 AK 2267','KA 51 AK 2847','KA 51 AK 3420','KA 51 AK 3419','KA 51 AK 3421','KA 51 AK 3422','KA 51 AK 2000',
        'KA 51 AK 2001','KA 51 AK 2002','KA 51 AK 2271','KA 51 AK 2270','KA 51 AK 2269','KA 51 AK 2272','KA 51 AK 2546','KA 51 AK 2544',
        'KA 51 AK 3423','KA 51 AK 2848','KA 51 AK 2545','KA 51 AK 2846','KA 51 AK 2849','KA 51 AK 2547','TN 99 AB 9541','TN 99 AB 9594',
        'TN 99 AB 9542','TN 99 AB 9567','KA 51 AK 3167','KA 51 AK 4010','KA 51 AK 4011','KA 51 AK 4665','KA 51 AK 4646','KA 51 AK 4645',
        'KA 51 AK 4644','KA 51 AB 4348','KA 51 AE 9129','KA 51 AF 1585','KA 51 AH 8915','KA 51 AH 8917','KA 51 AH 8916','KA 51 AH 8913',
        'KA 51 AL 2880','KA 51 AL 2879','KA 51 AL 2878','KA 51 AL 2877','KA 51 AL 2876','KA 51 AL 3605','KA 51 AL 3607','KA 51 AL 3441',
        'KA 51 AL 3453','KA 51 AL 3442','KA 51 AL 3443','KA 51 AL 3451','KA 51 AL 3454','KA 51 AL 3444','KA 51 AL 3440','KA 51 AL 3455',
        'KA 51 AL 3741','KA 51 AL 3608','KA 51 AL 3606','TN 99 AE 0741','KA 51 AL 3742','KA 51 AL 3743','TN 14 AQ 4749','TN 14 AQ 4768',
        'TN 14 AQ 4775','TN 14 AQ 4728','KA 51 AL 4169','KA 51 AL 4282','KA 51 AL 5390','KA 51 AL 5391','KA 51 AL 6280','KA 51 AL 6279',
        'KA 51 AL 6278','TN 99 AE 8794','KA 51 AL 7817','KA 51 AL 7820','KA 51 AL 7825','KA 51 AL 7829','KA 51 AL 7824','KA 51 AL 7830',
        'KA 51 AL 7823','KA 51 AL 7826','KA 51 AL 7828','KA 51 AL 7827','KA 51 AL 7813','KA 51 AL 7814','KA 51 AL 7815','KA 51 AL 7818',
        'KA 51 AL 7816','KA 51 AL 7819','KA 51 AL 8570','KA 51 AL 8564','KA 51 AL 8565','KA 51 AL 8566','KA 51 AL 8567','KA 51 AL 8568',
        'KA 51 AL 8563','KA 51 AL 8562','KA 51 AL 8572','KA 51 AL 8573','KA 51 AL 8571','KA 51 AM 4370','KA 51 AM 4368','KA 51 AM 4375',
        'KA 51 AM 4369','KA 51 AM 4372','KA 51 AM 4373','TN 70 AY 4413','TN 70 AY 5056','TN 70 AY 4435','TN 70 AY 5010','TN 70 AY 4416',
        'TN 70 AY 4485','TN 70 AY 4466','TN 70 AY 4457','TN 70 AY 4486','TN 70 AY 4417','TN 70 AY 4476','KA 51 AM 7087','KA 51 AM 7088',
        'TN 70 AY 8863','TN 70 AY 8845','TN 14 AU 6960','TN 14 AU 6944','TN 14 AU 6878','TN 14 AU 6846','KA 51 AM 6953','KA 51 AM 6954',
        'KA 51 AM 6951','KA 51 AM 6952','KA 51 AM 6928','KA 51 AM 6929','KA 51 AM 6917','KA 51 AM 6918','TN 99 AJ 3110','KA 51 AM 7493',
        'KA 51 AM 7495','KA 51 AM 7494','KA 51 AM 7496','KA 51 AM 7455','KA 51 AM 7456','TG 08 X 1486','TG 08 X 1485','TG 08 X 1487',
        'TG 08 X 1484','TG 08 X 1382','TG 08 X 1383','TG 08 X 1384','TG 08 X 1385','TG 08 X 1381','TG 08 X 1386','KA 51 AM 7492',
        'KA 51 AM 7609','KA 51 AM 7563','KA 51 AM 7473','KA 51 AM 7497','KA 51 AM 7491','KA 51 AM 7459','KA 51 AM 7465','KA 51 AM 7469',
        'KA 51 AM 7463','KA 51 AM 7464','KA 51 AM 7462','KA 51 AM 7458','KA 51 AM 7475','KA 51 AM 7498','KA 51 AM 7778','KA 51 AM 7483',
        'KA 51 AM 7485','KA 51 AM 7481','KA 51 AM 7467','KA 51 AM 7468','KA 51 AM 7482','KA 51 AM 7451','KA 51 AM 7514','KA 51 AM 7513',
        'KA 51 AM 7893','KA 51 AM 7608','KA 51 AM 7507','KA 51 AM 7484','KA 51 AM 7486','KA 51 AM 7499','KA 51 AM 7501','KA 51 AM 7488',
        'KA 51 AM 7490','KA 51 AM 7500','KA 51 AM 7502','KA 51 AM 7504','KA 51 AM 7503','KA 51 AM 7489','KA 51 AM 7904','KA 51 AM 7905',
        'KA 51 AM 7480','KA 51 AM 7466','KA 51 AM 7505','KA 51 AM 7506','KA 51 AM 7476','KA 51 AM 7442','TN 64 AH 6909','KA 51 AM 7450',
        'KA 51 AM 7457','KA 01 AU 2250','KA 51 AM 8895','KA 51 AM 8922','KA 51 AM 8616','TN 64 AH 6990','KA 51 AM 7487','KA 51 AM 7564',
        'KA 51 D 3703','KA 05 HU 8428'
    ]),
    ('nvs_travel_solutions', ARRAY[
        'KA 51 AL 5631','KA 51 AL 5638','KA 51 AL 5632','KA 51 AL 5680','KA 51 AL 5630','KA 51 AL 5629','KA 51 AL 5623','KA 51 AL 5637',
        'KA 51 AL 5636','KA 51 AL 5627','KA 51 AL 5633','KA 51 AL 5624','KA 51 AL 5240','KA 51 AL 5242','KA 51 AL 5241','KA 51 AL 5247',
        'KA 51 AL 5248','KA 51 AL 5249','KA 51 AL 5244','KA 51 AL 5250','KA 51 AL 5245','KA 51 AL 5246','KA 51 AL 5487','KA 51 AL 5490',
        'KA 51 AL 5489','KA 51 AL 5492','KA 51 AL 5491','KA 51 AL 5488','KA 51 AL 5493','KA 51 AL 5565','KA 51 AL 5751','KA 51 AL 5494',
        'KA 51 AL 5628','KA 51 AL 5635','KA 51 AL 5634','KA 51 AL 5750','KA 51 AL 5749','KA 51 AL 5748','KA 51 AL 9487','KA 51 AL 9488',
        'KA 51 AL 9458','KA 51 AL 9847','KA 51 AM 1165','KA 51 AM 3287'
    ])
),
plates AS (
    SELECT DISTINCT s.company, upper(regexp_replace(p, '[\s-]', '', 'g')) AS plate_key
    FROM sheet s, unnest(s.plates) p
),
-- A plate listed under both companies is not decided here.
decided AS (
    SELECT plate_key, min(company) AS company
    FROM plates
    GROUP BY plate_key
    HAVING count(DISTINCT company) = 1
),
assigned AS (
    UPDATE public.vehicles v
    SET company = d.company
    FROM decided d
    WHERE upper(regexp_replace(v.registration_number, '[\s-]', '', 'g')) = d.plate_key
      AND v.company = 'unknown'
    RETURNING v.id, v.registration_number, v.company
)
INSERT INTO public.vehicle_company_changes
    (vehicle_id, registration_number, old_company, new_company, kind, performed_by, performed_by_name)
SELECT id, registration_number, 'unknown', company, 'initial_load', NULL, 'System (MAIN-155)'
FROM assigned;
