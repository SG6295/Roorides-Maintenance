-- Make the five existing stock triggers location-aware.
--
-- Trigger names are unchanged; only the function bodies are rewritten, so nothing
-- else in the schema has to move. Every stock change now goes through
-- apply_part_stock_delta(), which resolves the (part, location) row, locks it, and
-- refuses to drive a location negative.
--
-- Where the location comes from:
--   purchase_invoice_items -> the parent invoice's location_id
--   issue_parts            -> the job card's location_id (InHouse only)

-- ── Purchases ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.add_part_to_inventory()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_location_id uuid;
BEGIN
    SELECT pi.location_id INTO v_location_id
    FROM   public.purchase_invoices pi
    WHERE  pi.id = NEW.invoice_id;

    PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, NEW.quantity);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.adjust_part_inventory_on_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_location_id uuid;
BEGIN
    SELECT pi.location_id INTO v_location_id
    FROM   public.purchase_invoices pi
    WHERE  pi.id = NEW.invoice_id;

    IF NEW.part_id = OLD.part_id THEN
        -- Same part: apply the quantity delta
        PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, NEW.quantity - OLD.quantity);
    ELSE
        -- Part changed: reverse old part stock, add to new part stock
        PERFORM public.apply_part_stock_delta(OLD.part_id, v_location_id, -OLD.quantity);
        PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, NEW.quantity);
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.reverse_part_inventory_on_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_location_id uuid;
BEGIN
    SELECT pi.location_id INTO v_location_id
    FROM   public.purchase_invoices pi
    WHERE  pi.id = OLD.invoice_id;

    -- Defensive: the parent invoice should always still be there, because deleting an
    -- invoice removes its items first (see delete_invoice_items_first below).
    IF v_location_id IS NULL THEN
        RETURN OLD;
    END IF;

    PERFORM public.apply_part_stock_delta(OLD.part_id, v_location_id, -OLD.quantity);
    RETURN OLD;
END;
$$;

-- Deleting an invoice cascades to its items, and the item trigger above needs the
-- parent's location_id to reverse the stock. Remove the items first, while the header
-- is still readable, so a deleted invoice actually gives its stock back instead of
-- leaving it stranded at the workshop.
CREATE OR REPLACE FUNCTION public.delete_invoice_items_first()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    DELETE FROM public.purchase_invoice_items WHERE invoice_id = OLD.id;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trigger_delete_invoice_items_first ON public.purchase_invoices;
CREATE TRIGGER trigger_delete_invoice_items_first
    BEFORE DELETE ON public.purchase_invoices
    FOR EACH ROW EXECUTE FUNCTION public.delete_invoice_items_first();

-- Moving an invoice to another workshop moves everything it inwarded with it.
CREATE OR REPLACE FUNCTION public.move_invoice_stock_on_location_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    r RECORD;
BEGIN
    IF NEW.location_id IS NOT DISTINCT FROM OLD.location_id THEN
        RETURN NEW;
    END IF;

    FOR r IN
        SELECT part_id, quantity
        FROM   public.purchase_invoice_items
        WHERE  invoice_id = NEW.id
    LOOP
        PERFORM public.apply_part_stock_delta(r.part_id, OLD.location_id, -r.quantity);
        PERFORM public.apply_part_stock_delta(r.part_id, NEW.location_id,  r.quantity);
    END LOOP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_move_invoice_stock_on_location_change ON public.purchase_invoices;
CREATE TRIGGER trigger_move_invoice_stock_on_location_change
    AFTER UPDATE OF location_id ON public.purchase_invoices
    FOR EACH ROW EXECUTE FUNCTION public.move_invoice_stock_on_location_change();

-- ── Consumption on job cards ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.deduct_part_from_inventory()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_job_card_type text;
    v_location_id   uuid;
BEGIN
    SELECT jc.type, jc.location_id INTO v_job_card_type, v_location_id
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  i.id = NEW.issue_id;

    -- Outsourced repairs use the vendor's parts; our stock is untouched.
    IF v_job_card_type = 'Outsource' THEN
        RETURN NEW;
    END IF;

    PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, -NEW.quantity_used);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.restore_part_to_inventory()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_job_card_type text;
    v_location_id   uuid;
BEGIN
    SELECT jc.type, jc.location_id INTO v_job_card_type, v_location_id
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  i.id = OLD.issue_id;

    IF v_job_card_type = 'Outsource' THEN
        RETURN OLD;
    END IF;

    -- The issue or its job card may already be gone (cascade delete); nothing to restore to.
    IF v_location_id IS NULL THEN
        RETURN OLD;
    END IF;

    PERFORM public.apply_part_stock_delta(OLD.part_id, v_location_id, OLD.quantity_used);
    RETURN OLD;
END;
$$;

-- A job card's location decides which workshop its parts come out of, so it can no
-- longer be moved once parts have been consumed against it — the deductions already
-- happened at the old workshop.
CREATE OR REPLACE FUNCTION public.guard_job_card_location_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_consumed integer;
BEGIN
    IF NEW.location_id IS NOT DISTINCT FROM OLD.location_id THEN
        RETURN NEW;
    END IF;

    -- Outsource cards never moved stock, so they are free to move.
    IF NEW.type = 'Outsource' THEN
        RETURN NEW;
    END IF;

    SELECT count(*) INTO v_consumed
    FROM   public.issue_parts ip
    JOIN   public.issues      i ON i.id = ip.issue_id
    WHERE  i.job_card_id = NEW.id;

    IF v_consumed > 0 THEN
        RAISE EXCEPTION
            'This job card cannot be moved to another workshop: % part(s) have already been issued from the current one. Remove the parts first, or leave the card where it is.',
            v_consumed;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_guard_job_card_location_change ON public.job_cards;
CREATE TRIGGER trigger_guard_job_card_location_change
    BEFORE UPDATE OF location_id ON public.job_cards
    FOR EACH ROW EXECUTE FUNCTION public.guard_job_card_location_change();
