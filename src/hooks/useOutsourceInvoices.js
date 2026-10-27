import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Fetches the outsource_invoices row for a job card (if any).
 * Returns null when no draft/invoice exists yet.
 * Also fetches payment rows (with status) so the caller can check whether any
 * active payment has been recorded.
 */
export function useOutsourceInvoice(jobCardId) {
    return useQuery({
        queryKey: ['outsource_invoice', jobCardId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('outsource_invoices')
                .select('*, payments:outsource_invoice_payments(id, status)')
                .eq('job_card_id', jobCardId)
                .maybeSingle()
            if (error) throw error
            return data
        },
        enabled: !!jobCardId,
    })
}

/**
 * Upserts an outsource_invoices row.
 * On first save creates the row; on subsequent saves updates it.
 */
export function useUpsertOutsourceInvoice() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ jobCardId, userId, data }) => {
            const { data: result, error } = await supabase
                .from('outsource_invoices')
                .upsert(
                    { job_card_id: jobCardId, created_by: userId, ...data },
                    { onConflict: 'job_card_id' }
                )
                .select()
                .single()
            if (error) throw error
            return result
        },
        onSuccess: (_, { jobCardId }) => {
            queryClient.invalidateQueries({ queryKey: ['outsource_invoice', jobCardId] })
        },
    })
}

const PAGE_SIZE = 50

/**
 * Fetches paginated closed outsource invoices for the list page.
 *
 * filters:
 *   maintenancePaymentStatus — string[]       server-side IN filter on maintenance_payment_status
 *   financePaymentStatus     — string[]       server-side IN filter on finance_payment_status
 *   paidBy                   — string[]       server-side IN filter on paid_by
 *   dateFrom                 — string         ISO date, gte date_of_activity
 *   dateTo                   — string         ISO date, lte date_of_activity
 *   page                     — number | null  0-based page index; null = fetch all (search mode)
 *
 * Returns { invoices: [], totalCount: number | null }.
 * totalCount is null when page=null (search mode — client handles count).
 * Only job cards with status='Completed' are returned (enforced via inner join).
 */
export function useOutsourceInvoices(filters = {}) {
    return useQuery({
        queryKey: ['outsource_invoices', filters],
        queryFn: async () => {
            const isPaginated = filters.page !== null && filters.page !== undefined

            let query = supabase
                .from('outsource_invoices')
                .select(
                    `*,
                    job_card:job_cards!job_card_id!inner(
                        id, job_card_number, vehicle_number, status, completed_at, invoice_url,
                        supplier:suppliers!supplier_id(id, entity_name)
                    ),
                    payments:outsource_invoice_payments(id, amount_paid, tds_amount, round_off, paid_on, ledger, status, created_at)`,
                    isPaginated ? { count: 'exact' } : undefined,
                )
                .eq('job_cards.status', 'Completed')
                .order('payby_date', { ascending: true })

            if (filters.maintenancePaymentStatus?.length)
                query = query.in('maintenance_payment_status', filters.maintenancePaymentStatus)
            if (filters.financePaymentStatus?.length)
                query = query.in('finance_payment_status', filters.financePaymentStatus)
            if (filters.paidBy?.length)
                query = query.in('paid_by', filters.paidBy)
            if (filters.dateFrom)
                query = query.gte('date_of_activity', filters.dateFrom)
            if (filters.dateTo)
                query = query.lte('date_of_activity', filters.dateTo)

            if (isPaginated) {
                const from = filters.page * PAGE_SIZE
                query = query.range(from, from + PAGE_SIZE - 1)
            }

            const { data, count, error } = await query
            if (error) throw error
            return { invoices: data || [], totalCount: isPaginated ? count : null }
        },
    })
}

/**
 * Fetches the three summary aggregates for the Outsource Invoices dashboard tiles
 * via a single RPC call. Applies the same server-side filters as useOutsourceInvoices
 * but ignores pagination — tiles always reflect the full filtered set.
 */
export function useOutsourceInvoiceSummary(filters = {}) {
    return useQuery({
        queryKey: ['outsource_invoice_summary', filters],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_outsource_invoice_summary', {
                p_maintenance_payment_status: filters.maintenancePaymentStatus?.length ? filters.maintenancePaymentStatus : null,
                p_finance_payment_status:     filters.financePaymentStatus?.length     ? filters.financePaymentStatus     : null,
                p_paid_by:                    filters.paidBy?.length                   ? filters.paidBy                   : null,
                p_date_from:                  filters.dateFrom || null,
                p_date_to:                    filters.dateTo   || null,
            })
            if (error) throw error
            const row = data?.[0] ?? {}
            return {
                totalUnpaidPayable:   Number(row.total_unpaid_payable   ?? 0),
                overdueCount:         Number(row.overdue_count           ?? 0),
                pendingApprovalCount: Number(row.pending_approval_count  ?? 0),
            }
        },
    })
}

/**
 * Transitions a 'Completed - Invoice Pending' job card to 'Completed' once the
 * invoice file and all required details have been provided.
 */
export function useFinalizeOutsourceInvoice() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ jobCardId, remarks }) => {
            const { data, error } = await supabase.rpc('finalize_outsource_invoice', {
                p_job_card_id: jobCardId,
                p_remarks:     remarks || null,
            })
            if (error) throw error
            return data
        },
        onSuccess: (_, { jobCardId }) => {
            queryClient.invalidateQueries({ queryKey: ['job_card'] })
            queryClient.invalidateQueries({ queryKey: ['job_cards'] })
            queryClient.invalidateQueries({ queryKey: ['outsource_invoice', jobCardId] })
        },
    })
}

/**
 * Sets finance's own status and/or remark on an outsource invoice. Only finance and
 * super_admin may change these; the DB trigger rejects anyone else.
 *
 * Only the fields passed are written, so editing the remark in its table cell
 * cannot overwrite a status changed a moment earlier in the next cell, or the
 * reverse.
 */
export function useUpdateFinancePaymentStatus() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ id, financePaymentStatus, financeRemark }) => {
            const patch = {}
            if (financePaymentStatus !== undefined) patch.finance_payment_status = financePaymentStatus
            if (financeRemark !== undefined) patch.finance_remark = financeRemark?.trim() || null
            const { data, error } = await supabase
                .from('outsource_invoices')
                .update(patch)
                .eq('id', id)
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['outsource_invoices'] })
            queryClient.invalidateQueries({ queryKey: ['outsource_invoice_summary'] })
            queryClient.invalidateQueries({ queryKey: ['outsource_invoice'] })
            queryClient.invalidateQueries({ queryKey: ['outsource_invoice_history'] })
        },
    })
}

// Recording or cancelling a payment moves the invoice's totals, its finance status
// and its history, and can lift or set the job card's reopen lock.
function invalidateAfterPaymentChange(queryClient, invoiceId) {
    queryClient.invalidateQueries({ queryKey: ['outsource_invoices'] })
    queryClient.invalidateQueries({ queryKey: ['outsource_invoice_summary'] })
    queryClient.invalidateQueries({ queryKey: ['outsource_invoice_payments', invoiceId] })
    queryClient.invalidateQueries({ queryKey: ['outsource_invoice_history', invoiceId] })
    queryClient.invalidateQueries({ queryKey: ['outsource_invoice'] })
}

/**
 * Records a payment against an outsource invoice through
 * record_outsource_invoice_payment, which checks the caller is finance or
 * super_admin, refuses an overpayment and recalculates the finance status, all in
 * one transaction.
 *
 * payment: { amount_paid, tds_amount, round_off, paid_on, ledger, payment_method, bank, utr }
 */
export function useRecordInvoicePayment() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ invoiceId, payment }) => {
            const { data, error } = await supabase.rpc('record_outsource_invoice_payment', {
                p_invoice_id: invoiceId,
                p_payment: payment,
            })
            if (error) throw error
            return data
        },
        onSuccess: (_, { invoiceId }) => invalidateAfterPaymentChange(queryClient, invoiceId),
    })
}

/**
 * Cancels a payment — for a transaction that failed and was refunded. The row is
 * kept, marked Cancelled, and drops out of every total.
 */
export function useCancelInvoicePayment() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ paymentId, reason }) => {
            const { error } = await supabase.rpc('cancel_outsource_invoice_payment', {
                p_payment_id: paymentId,
                p_reason: reason,
            })
            if (error) throw error
        },
        onSuccess: (_, { invoiceId }) => invalidateAfterPaymentChange(queryClient, invoiceId),
    })
}

/**
 * Payments for one invoice, with who recorded and who cancelled each by name.
 * Finance cannot read exec or other finance profiles, so the names come from
 * get_outsource_invoice_payments rather than a join to users.
 */
export function useInvoicePayments(outsourceInvoiceId) {
    return useQuery({
        queryKey: ['outsource_invoice_payments', outsourceInvoiceId],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_outsource_invoice_payments', {
                p_invoice_id: outsourceInvoiceId,
            })
            if (error) throw error
            return data || []
        },
        enabled: !!outsourceInvoiceId,
    })
}

/**
 * The dated "who changed what" history of one invoice (MAIN-96), newest first.
 * Entries come from database triggers, with names attached by
 * get_outsource_invoice_history because finance cannot read exec/finance profiles.
 */
export function useOutsourceInvoiceHistory(outsourceInvoiceId) {
    return useQuery({
        queryKey: ['outsource_invoice_history', outsourceInvoiceId],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_outsource_invoice_history', {
                p_invoice_id: outsourceInvoiceId,
            })
            if (error) throw error
            return data || []
        },
        enabled: !!outsourceInvoiceId,
    })
}
