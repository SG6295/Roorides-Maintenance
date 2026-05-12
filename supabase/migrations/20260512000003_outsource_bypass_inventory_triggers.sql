BEGIN;

-- ── Outsource Invoices — Phase 1 (3/3) ───────────────────────────────────────
-- Modifies the issue_parts inventory triggers to skip stock changes for
-- outsource job cards.
--
-- Background: trigger_deduct_part_inventory fires AFTER INSERT on issue_parts
-- and decrements parts.quantity_in_stock. Parts added to an outsource job card
-- are not drawn from NVS inventory (the vendor supplies them), so deduction
-- must be skipped. Symmetrically, trigger_restore_part_inventory fires AFTER
-- DELETE and must also skip for outsource parts (there was no deduction to undo).
--
-- Implementation: both functions join issue_id → issues → job_cards to read
-- the job card type. NULL job_card_id (issue not yet on a card) falls through
-- to the original behaviour — safe because that situation doesn't occur in the
-- current UI flow.
--
-- Both functions retain SECURITY DEFINER so the lookup bypasses RLS on
-- issues and job_cards when triggered by callers with restricted access.

CREATE OR REPLACE FUNCTION public.deduct_part_from_inventory()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

CREATE OR REPLACE FUNCTION public.restore_part_to_inventory()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- ── Verification ──────────────────────────────────────────────────────────────
-- Confirm both functions now contain the Outsource guard.

SELECT proname,
       prosrc LIKE '%Outsource%' AS has_outsource_guard,
       prosecdef                 AS security_definer
FROM   pg_proc
WHERE  proname IN ('deduct_part_from_inventory', 'restore_part_to_inventory')
ORDER  BY proname;

ROLLBACK; -- change to COMMIT once output looks correct
