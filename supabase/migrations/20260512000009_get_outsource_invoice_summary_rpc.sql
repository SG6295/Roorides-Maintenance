BEGIN;

-- ── Outsource Invoices — Performance: Summary RPC ─────────────────────────────
-- get_outsource_invoice_summary returns three dashboard aggregates in one round
-- trip, applying the same server-side filters as the list query but ignoring
-- pagination so the tiles always reflect the full filtered population.
--
-- total_unpaid_payable   — sum of remaining balance (payable − paid) for every
--                          invoice where total paid < payable amount.
-- overdue_count          — invoices past payby_date that are not fully paid.
-- pending_approval_count — invoices with payment_status = 'Hold'.
--
-- SECURITY DEFINER: needed so the function can JOIN job_cards regardless of the
-- calling user's RLS policy (e.g. supervisors).

CREATE OR REPLACE FUNCTION public.get_outsource_invoice_summary(
    p_payment_status text[]  DEFAULT NULL,
    p_paid_by        text[]  DEFAULT NULL,
    p_date_from      date    DEFAULT NULL,
    p_date_to        date    DEFAULT NULL
)
RETURNS TABLE (
    total_unpaid_payable   numeric,
    overdue_count          bigint,
    pending_approval_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH paid_sums AS (
        SELECT outsource_invoice_id,
               SUM(amount_paid) AS total_paid
        FROM   outsource_invoice_payments
        GROUP  BY outsource_invoice_id
    )
    SELECT
        -- Remaining balance across all non-Paid invoices
        COALESCE(SUM(
            GREATEST(0,
                (oi.approved_amount - oi.advance_amount) - COALESCE(ps.total_paid, 0)
            )
        ) FILTER (WHERE
            COALESCE(ps.total_paid, 0) < (oi.approved_amount - oi.advance_amount)
        ), 0)                                                    AS total_unpaid_payable,

        -- Past due and not fully paid
        COUNT(*) FILTER (WHERE
            oi.payby_date < CURRENT_DATE
            AND COALESCE(ps.total_paid, 0) < (oi.approved_amount - oi.advance_amount)
        )                                                        AS overdue_count,

        -- Awaiting payment approval
        COUNT(*) FILTER (WHERE oi.payment_status = 'Hold')      AS pending_approval_count

    FROM  outsource_invoices     oi
    JOIN  job_cards              jc ON jc.id = oi.job_card_id
    LEFT JOIN paid_sums          ps ON ps.outsource_invoice_id = oi.id
    WHERE jc.status = 'Completed'
      AND (p_payment_status IS NULL OR oi.payment_status   = ANY(p_payment_status))
      AND (p_paid_by        IS NULL OR oi.paid_by          = ANY(p_paid_by))
      AND (p_date_from      IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to        IS NULL OR oi.date_of_activity <= p_date_to)
$$;

GRANT EXECUTE ON FUNCTION public.get_outsource_invoice_summary TO authenticated;

-- ── Verification ──────────────────────────────────────────────────────────────
SELECT proname, provolatile, prosecdef AS security_definer
FROM   pg_proc
WHERE  proname = 'get_outsource_invoice_summary';

COMMIT;
