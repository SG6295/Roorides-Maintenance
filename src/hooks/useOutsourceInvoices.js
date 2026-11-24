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
 *   type                     — string[]       server-side IN filter on the invoice's type (MAIN-142)
 *   dateFrom                 — string         ISO date, gte date_of_activity
 *   dateTo                   — string         ISO date, lte date_of_activity
 *   page                     — number | null  0-based page index; null = fetch all (search mode)
 *
 * Returns { invoices: [], totalCount: number | null }.
 * totalCount is null when page=null (search mode — client handles count).
 * Returns invoices of completed job cards, every multi-vehicle invoice (MAIN-99) and
 * every purchase invoice's finance invoice (refurbishments from MAIN-123, all purchases
 * from MAIN-129) — a batch or purchase is complete by construction, its invoice details
 * being mandatory at save.
 *
 * Served by get_outsource_invoice_rows (MAIN-141) for every role, under the same rule
 * as the summary tiles: a supervisor sees only their own sites' invoices, and cannot
 * read the job cards, batches or suppliers a plain PostgREST embed would need. Rows
 * keep the embed shape (job_card / batch_service / purchase_invoice, supplier name only).
 */
export function useOutsourceInvoices(filters = {}) {
    return useQuery({
        queryKey: ['outsource_invoices', filters],
        queryFn: async () => {
            const isPaginated = filters.page !== null && filters.page !== undefined

            const { data, error } = await supabase.rpc('get_outsource_invoice_rows', {
                p_filters: {
                    maintenance_payment_status: filters.maintenancePaymentStatus?.length ? filters.maintenancePaymentStatus : null,
                    finance_payment_status:     filters.financePaymentStatus?.length     ? filters.financePaymentStatus     : null,
                    paid_by:                    filters.paidBy?.length                   ? filters.paidBy                   : null,
                    type:                       filters.type?.length                     ? filters.type                     : null,
                    company:                    filters.company?.length                  ? filters.company                  : null,
                    date_from:                  filters.dateFrom || null,
                    date_to:                    filters.dateTo   || null,
                    page:                       isPaginated ? filters.page : null,
                    page_size:                  PAGE_SIZE,
                },
            })
            if (error) throw error
            return { invoices: data?.rows || [], totalCount: isPaginated ? data?.total ?? 0 : null }
        },
    })
}

/**
 * Fetches the finance-status counts for the Invoices dashboard tiles
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
                p_type:                       filters.type?.length                     ? filters.type                     : null,
                p_company:                    filters.company?.length                  ? filters.company                  : null,
                p_date_from:                  filters.dateFrom || null,
                p_date_to:                    filters.dateTo   || null,
            })
            if (error) throw error
            const row = data?.[0] ?? {}
            return {
                newCount:      Number(row.new_count      ?? 0),
                pendingCount:  Number(row.pending_count  ?? 0),
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
 * Resubmits a rejected invoice from the Resubmit popup (MAIN-120): its file, supplier
 * and invoice fields, with an optional note to finance, in one call. The database
 * refuses it unless something changed, the file is there, maintenance's status is
 * Approved or Hold, and any lines still add up to the Approved Amount.
 */
export function useResubmitOutsourceInvoice() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ id, resubmission }) => {
            const { error } = await supabase.rpc('resubmit_outsource_invoice', {
                p_invoice_id:    id,
                p_resubmission:  resubmission,
            })
            if (error) throw error
        },
        onSuccess: () => {
            for (const queryKey of [
                ['outsource_invoices'], ['outsource_invoice_summary'], ['outsource_invoice'],
                ['outsource_invoice_history'], ['job_card'], ['batch_service'],
                ['purchase_invoices'], ['supplier_ledger'],
            ]) queryClient.invalidateQueries({ queryKey })
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
