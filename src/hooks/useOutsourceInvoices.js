import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Fetches the outsource_invoices row for a job card (if any).
 * Returns null when no draft/invoice exists yet.
 * Also fetches payment rows so the caller can check hasPayments.
 */
export function useOutsourceInvoice(jobCardId) {
    return useQuery({
        queryKey: ['outsource_invoice', jobCardId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('outsource_invoices')
                .select('*, payments:outsource_invoice_payments(id)')
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
 *   paymentStatus  — string[]        server-side IN filter on payment_status
 *   paidBy         — string[]        server-side IN filter on paid_by
 *   dateFrom       — string          ISO date, gte date_of_activity
 *   dateTo         — string          ISO date, lte date_of_activity
 *   page           — number | null   0-based page index; null = fetch all (search mode)
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
                        id, job_card_number, vehicle_number, status, completed_at,
                        supplier:suppliers!supplier_id(id, entity_name)
                    ),
                    payments:outsource_invoice_payments(id, amount_paid)`,
                    isPaginated ? { count: 'exact' } : undefined,
                )
                .eq('job_cards.status', 'Completed')
                .order('payby_date', { ascending: true })

            if (filters.paymentStatus?.length)
                query = query.in('payment_status', filters.paymentStatus)
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
                p_payment_status: filters.paymentStatus?.length ? filters.paymentStatus : null,
                p_paid_by:        filters.paidBy?.length        ? filters.paidBy        : null,
                p_date_from:      filters.dateFrom || null,
                p_date_to:        filters.dateTo   || null,
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
 * Records a payment against an outsource invoice.
 */
export function useRecordInvoicePayment() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ outsourceInvoiceId, paidOn, amountPaid, notes, attachmentUrls, recordedBy }) => {
            const { data, error } = await supabase
                .from('outsource_invoice_payments')
                .insert([{
                    outsource_invoice_id: outsourceInvoiceId,
                    paid_on: paidOn,
                    amount_paid: amountPaid,
                    notes: notes || null,
                    attachment_urls: attachmentUrls || [],
                    recorded_by: recordedBy,
                }])
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: (_, { outsourceInvoiceId }) => {
            queryClient.invalidateQueries({ queryKey: ['outsource_invoices'] })
            queryClient.invalidateQueries({ queryKey: ['outsource_invoice_summary'] })
            queryClient.invalidateQueries({ queryKey: ['outsource_invoice_payments', outsourceInvoiceId] })
        },
    })
}

/**
 * Fetches payments for a specific invoice (used in the payment drawer).
 */
export function useInvoicePayments(outsourceInvoiceId) {
    return useQuery({
        queryKey: ['outsource_invoice_payments', outsourceInvoiceId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('outsource_invoice_payments')
                .select('*, recorder:recorded_by(name)')
                .eq('outsource_invoice_id', outsourceInvoiceId)
                .order('paid_on', { ascending: true })
            if (error) throw error
            return data || []
        },
        enabled: !!outsourceInvoiceId,
    })
}
