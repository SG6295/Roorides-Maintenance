-- Close a read gap in stock_audit_movements().
--
-- The function is SECURITY DEFINER, which bypasses RLS, and Postgres grants EXECUTE to
-- PUBLIC by default — so any authenticated user (mechanic, supervisor, electrician), and
-- anyone holding the anon key, could read a workshop's consumption detail: job card
-- numbers, vehicle numbers and quantities. The stock_audits tables themselves are
-- restricted to finance / super_admin / maintenance_exec; the function was not.
--
-- The other five audit functions each check the caller's role in their body. This one is
-- LANGUAGE sql, so the check goes into the driving CTE instead: a caller without the role
-- selects no audit, every UNION branch joins against nothing, and the result is empty.
-- Same outcome as the SELECT policy, without needing to raise.

CREATE OR REPLACE FUNCTION public.stock_audit_movements(p_audit_id uuid)
RETURNS TABLE (
    part_id        uuid,
    source         text,
    quantity       numeric,
    reference      text,
    vehicle_number text,
    occurred_at    timestamp without time zone
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
    WITH a AS (
        SELECT sa.id, sa.location_id, sa.started_at
        FROM   public.stock_audits sa
        WHERE  sa.id = p_audit_id
          -- Mirrors the SELECT policy on stock_audits.
          AND  EXISTS (
                   SELECT 1 FROM public.users u
                   WHERE u.id = auth.uid()
                     AND u.role IN ('finance', 'super_admin', 'maintenance_exec')
               )
    )
    -- Consumed on a job card. Outsource job cards never touch stock, so they are excluded
    -- here exactly as deduct_part_from_inventory() excludes them.
    SELECT ip.part_id,
           'consumption'::text,
           -ip.quantity_used,
           'JC-' || jc.job_card_number::text,
           jc.vehicle_number,
           ip.added_at
    FROM   a
    JOIN   public.job_cards   jc ON jc.location_id = a.location_id AND jc.type <> 'Outsource'
    JOIN   public.issues      i  ON i.job_card_id = jc.id
    JOIN   public.issue_parts ip ON ip.issue_id = i.id
    WHERE  ip.added_at > a.started_at

    UNION ALL

    -- Inwarded on a purchase invoice.
    SELECT pii.part_id,
           'purchase'::text,
           pii.quantity,
           pi.invoice_number,
           NULL::text,
           pi.created_at
    FROM   a
    JOIN   public.purchase_invoices      pi  ON pi.location_id = a.location_id
    JOIN   public.purchase_invoice_items pii ON pii.invoice_id = pi.id
    WHERE  pi.created_at > a.started_at

    UNION ALL

    -- Moved to or from another workshop.
    SELECT sti.part_id,
           CASE WHEN st.to_location_id = a.location_id
                THEN 'transfer_in' ELSE 'transfer_out' END,
           CASE WHEN st.to_location_id = a.location_id
                THEN sti.quantity ELSE -sti.quantity END,
           wl.name,
           NULL::text,
           st.transferred_at
    FROM   a
    JOIN   public.stock_transfers st
           ON (st.from_location_id = a.location_id OR st.to_location_id = a.location_id)
    JOIN   public.stock_transfer_items sti ON sti.transfer_id = st.id
    JOIN   public.workshop_locations wl
           ON wl.id = CASE WHEN st.to_location_id = a.location_id
                           THEN st.from_location_id ELSE st.to_location_id END
    WHERE  st.transferred_at > a.started_at

    ORDER BY 6 DESC;
$fn$;

-- Nothing unauthenticated has any business calling this.
REVOKE EXECUTE ON FUNCTION public.stock_audit_movements(uuid) FROM anon;

COMMENT ON FUNCTION public.stock_audit_movements(uuid) IS
    'Stock that legitimately moved at a workshop while an audit was open. SECURITY DEFINER, so it carries its own role check: returns nothing unless the caller is finance, super_admin or maintenance_exec.';
