import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Multi-vehicle outsource invoices (MAIN-99): one invoice, one line per vehicle, no
 * ticket and no job card. The batch, its lines and its invoice are written only through
 * save_batch_service_invoice; the tables have no client write policies.
 */

/** One batch with its supplier, vehicle lines and invoice (and that invoice's payments). */
export function useBatchService(id) {
    return useQuery({
        queryKey: ['batch_service', id],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('batch_services')
                .select(`*,
                    supplier:suppliers!supplier_id(id, entity_name),
                    vehicles:batch_service_vehicles(id, vehicle_number, site, amount),
                    invoice:outsource_invoices(*, payments:outsource_invoice_payments(id, status))`)
                .eq('id', id)
                .order('vehicle_number', { referencedTable: 'batch_service_vehicles' })
                .single()
            if (error) throw error
            return data
        },
        enabled: !!id,
    })
}

/**
 * Creates (batchId null) or edits a batch. The database re-checks everything the form
 * does — lines add up to the approved amount, no repeated vehicle, nothing changes once
 * a payment exists — and its refusal comes back as a readable message.
 *
 * batch:   { description, supplier_id, invoice_url }
 * invoice: outsource_invoices columns (invoiceFormToRow)
 * lines:   [{ vehicle_number, site, amount }]
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
            if (error) {
                let parsed = null
                try { parsed = JSON.parse(error.message) } catch { /* not one of ours */ }
                throw parsed?.error_message ? new Error(parsed.error_message) : error
            }
            return data
        },
        onSuccess: batchId => {
            queryClient.invalidateQueries({ queryKey: ['batch_service', batchId] })
            queryClient.invalidateQueries({ queryKey: ['vehicle_batch_services'] })
            queryClient.invalidateQueries({ queryKey: ['outsource_invoices'] })
            queryClient.invalidateQueries({ queryKey: ['outsource_invoice_summary'] })
            queryClient.invalidateQueries({ queryKey: ['outsource_invoice_history'] })
        },
    })
}

/** Every batch line for one vehicle, for its history page. */
export function useVehicleBatchServices(vehicleNumber) {
    return useQuery({
        queryKey: ['vehicle_batch_services', vehicleNumber],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('batch_service_vehicles')
                .select(`id, site, amount,
                    batch:batch_services!batch_service_id(
                        id, description, created_at,
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
