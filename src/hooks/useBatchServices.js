import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Multi-vehicle outsource invoices (MAIN-99): one invoice, a line per vehicle and work
 * (MAIN-112), no ticket and no job card. The batch, its lines and its invoice are written
 * only through save_batch_service_invoice; the tables have no client write policies.
 */

// The batch functions raise { error_code, error_message } as JSON; show the message.
function readableError(error) {
    let parsed = null
    try { parsed = JSON.parse(error.message) } catch { /* not one of ours */ }
    return parsed?.error_message ? new Error(parsed.error_message) : error
}

// Everything that shows a batch, its lines or its invoice.
const BATCH_QUERY_KEYS = [
    ['batch_service'], ['vehicle_batch_services'], ['outsource_invoices'], ['outsource_invoice_summary'],
    ['outsource_invoice_history'], ['job_card_batch_lines'], ['outsource_job_cards_for_vehicles'],
]

// A line's columns as every reader shows them; linked_job_card is the outsourced job
// card an Other line (or any line) was linked to.
const LINE_COLUMNS = `id, vehicle_number, site, work_type, work_type_other, rate, quantity, amount, job_card_id,
    linked_job_card:job_cards!job_card_id(job_card_number, status)`

/**
 * One batch, by its running number (MVI-12 → 12), with its supplier, vehicle lines and
 * invoice (and that invoice's payments).
 */
export function useBatchService(batchNumber) {
    return useQuery({
        queryKey: ['batch_service', batchNumber],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('batch_services')
                .select(`*,
                    supplier:suppliers!supplier_id(id, entity_name),
                    vehicles:batch_service_vehicles(${LINE_COLUMNS}),
                    invoice:outsource_invoices(*, payments:outsource_invoice_payments(id, status))`)
                .eq('batch_number', batchNumber)
                .order('vehicle_number', { referencedTable: 'batch_service_vehicles' })
                .order('created_at', { referencedTable: 'batch_service_vehicles' })
                .maybeSingle()
            if (error) throw error
            return data
        },
        enabled: !!batchNumber,
    })
}

/** A batch's running number from its id — for links made before MVI numbers existed. */
export function useBatchNumberById(id) {
    return useQuery({
        queryKey: ['batch_number_by_id', id],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('batch_services')
                .select('batch_number')
                .eq('id', id)
                .maybeSingle()
            if (error) throw error
            return data?.batch_number ?? null
        },
        enabled: !!id,
    })
}

/**
 * Creates (batchId null) or edits a batch. The database re-checks everything the form
 * does — lines add up to the approved amount, no vehicle twice with the same standard
 * work, Other lines name their work and an outsourced job card of that vehicle, nothing
 * changes once a payment exists — and its refusal comes back as a readable message.
 *
 * batch:   { supplier_id, invoice_url }
 * invoice: outsource_invoices columns (invoiceFormToRow)
 * lines:   [{ id?, vehicle_number, site, work_type, work_type_other, rate, quantity, job_card_id }]
 *          — a line with an id is that saved line; the amount is worked out server-side.
 *
 * Resolves to the batch's running number, which its page is addressed by.
 */
export function useSaveBatchService() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ batchId, batch, invoice, lines }) => {
            const { data, error } = await supabase.rpc('save_batch_service_invoice', {
                p_batch_id: batchId ?? null,
                p_batch: batch,
                p_invoice: invoice,
                p_lines: lines,
            })
            if (error) throw readableError(error)
            // The function returns the batch's id; its page is addressed by number.
            const { data: row, error: numberError } = await supabase
                .from('batch_services')
                .select('batch_number')
                .eq('id', data)
                .single()
            if (numberError) throw numberError
            return row.batch_number
        },
        onSuccess: () => BATCH_QUERY_KEYS.forEach(queryKey => queryClient.invalidateQueries({ queryKey })),
    })
}

/**
 * Cancels a batch with a reason (MAIN-112). Refused while finance has an active payment
 * on it. Releases its job card links, so a cancelled batch holds no job card back.
 */
export function useCancelBatchService() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ batchId, reason }) => {
            const { error } = await supabase.rpc('cancel_batch_service_invoice', { p_batch_id: batchId, p_reason: reason })
            if (error) throw readableError(error)
        },
        onSuccess: () => BATCH_QUERY_KEYS.forEach(queryKey => queryClient.invalidateQueries({ queryKey })),
    })
}

/**
 * Restores a cancelled batch. Its links were released on cancelling, so `links`
 * ([{ id, job_card_id }]) must give every Other line its outsourced job card again.
 */
export function useRestoreBatchService() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ batchId, links }) => {
            const { error } = await supabase.rpc('restore_batch_service_invoice', { p_batch_id: batchId, p_links: links })
            if (error) throw readableError(error)
        },
        onSuccess: () => BATCH_QUERY_KEYS.forEach(queryKey => queryClient.invalidateQueries({ queryKey })),
    })
}

/** Every batch line for one vehicle, for its history page. */
export function useVehicleBatchServices(vehicleNumber) {
    return useQuery({
        queryKey: ['vehicle_batch_services', vehicleNumber],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('batch_service_vehicles')
                .select(`${LINE_COLUMNS},
                    batch:batch_services!batch_service_id(
                        id, batch_number, status, created_at,
                        supplier:suppliers!supplier_id(entity_name),
                        invoice:outsource_invoices(invoice_no, date_of_activity)
                    )`)
                .eq('vehicle_number', vehicleNumber)
            if (error) throw error
            return data || []
        },
        enabled: !!vehicleNumber,
    })
}

/**
 * The outsourced job cards a line may link to, for every vehicle on the form: open ones,
 * and ones completed in the last 60 days — a vendor's invoice usually arrives after the
 * job card is closed. Each comes with its issue descriptions, so the picker can search
 * them. A saved link older than that is added back by the form from the line itself.
 */
export function useOutsourceJobCardsForVehicles(vehicleNumbers) {
    const vehicles = [...new Set(vehicleNumbers)].sort()
    return useQuery({
        queryKey: ['outsource_job_cards_for_vehicles', vehicles],
        queryFn: async () => {
            const since = new Date(Date.now() - 60 * 24 * 60 * 60 * 1000).toISOString()
            const { data, error } = await supabase
                .from('job_cards')
                .select('id, job_card_number, vehicle_number, status, created_at, completed_at, issues(description, category)')
                .eq('type', 'Outsource')
                .in('vehicle_number', vehicles)
                .or(`status.neq.Completed,completed_at.gte.${since}`)
                .order('created_at', { ascending: false })
            if (error) throw error
            return data || []
        },
        enabled: vehicles.length > 0,
    })
}

/** The multi-vehicle invoice lines linked to one job card, for its page (MAIN-112). */
export function useJobCardBatchLines(jobCardId, { enabled = true } = {}) {
    return useQuery({
        queryKey: ['job_card_batch_lines', jobCardId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('batch_service_vehicles')
                .select(`id, vehicle_number, work_type, work_type_other, rate, quantity, amount,
                    batch:batch_services!batch_service_id(
                        id, batch_number, invoice_url,
                        invoice:outsource_invoices(invoice_no, date_of_activity)
                    )`)
                .eq('job_card_id', jobCardId)
                .order('created_at')
            if (error) throw error
            return data || []
        },
        enabled: !!jobCardId && enabled,
    })
}
