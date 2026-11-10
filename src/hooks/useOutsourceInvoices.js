import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Fetches the outsource_invoices row for a job card (if any).
 * Returns null when no draft/invoice exists yet.
 */
export function useOutsourceInvoice(jobCardId) {
    return useQuery({
        queryKey: ['outsource_invoice', jobCardId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('outsource_invoices')
                .select('*')
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
 * Returns invoices of completed job cards, every multi-vehicle invoice (MAIN-99) and
 * every refurbishment's purchase invoice (MAIN-123) — a batch or refurbishment is
 * complete by construction, its invoice being mandatory at save. The job_card embed is
 * filtered to Completed, so it comes back null for an unfinished card, and the or()
 * keeps a row only if it is a batch, a purchase invoice the reader can see, or its job
 * card survived that filter. (PostgREST cannot put job_card.status itself inside an or().)
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
                    job_card:job_cards!job_card_id(
                        id, job_card_number, vehicle_number, status, completed_at, invoice_url,
                        supplier:suppliers!supplier_id(id, entity_name)
                    ),
                    batch_service:batch_services!batch_service_id(
                        id, batch_number, invoice_url, status, cancel_reason, cancelled_at,
                        supplier:suppliers!supplier_id(id, entity_name),
                        vehicles:batch_service_vehicles(
                            id, vehicle_number, site, work_type, work_type_other, rate, quantity, amount,
                            linked_job_card:job_cards!job_card_id(job_card_number)
                        )
                    ),
                    purchase_invoice:purchase_invoices!purchase_invoice_id(
                        id, invoice_number, invoice_file_url,
                        supplier:suppliers!supplier_id(id, entity_name)
                    )`,
                    isPaginated ? { count: 'exact' } : undefined,
                )
                .eq('job_card.status', 'Completed')
                .or('batch_service_id.not.is.null,purchase_invoice.not.is.null,job_card.not.is.null')
                // Newest submitted first: finance's review queue (MAIN-119).
                .order('submitted_on', { ascending: false, nullsFirst: false })
                .order('created_at', { ascending: false })

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
 * Fetches the finance-status counts for the Outsource Invoices dashboard tiles
 * (MAIN-118) via a single RPC call. Applies the same server-side filters as useOutsourceInvoices
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
                newCount:      Number(row.new_count      ?? 0),
                holdCount:     Number(row.hold_count     ?? 0),
                rejectCount:   Number(row.reject_count   ?? 0),
                acceptedCount: Number(row.accepted_count ?? 0),
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
