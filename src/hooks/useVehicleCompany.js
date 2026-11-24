import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Vehicle Registration Master (MAIN-155). A vehicle's company is changed only through
 * set_vehicle_company (finance, super_admin); every change is in vehicle_company_changes,
 * which has a SELECT policy only.
 */

export const VEHICLE_COMPANY_CHANGES_KEY = 'vehicle_company_changes'

// set_vehicle_company raises { error_code, error_message } as JSON; show the message.
function readableError(error) {
    let parsed = null
    try { parsed = JSON.parse(error.message) } catch { /* not one of ours */ }
    return parsed?.error_message ? new Error(parsed.error_message) : error
}

/** The change history, newest first, optionally for one vehicle. */
export function useVehicleCompanyChanges({ vehicleId = null, page = 0, pageSize = 20 } = {}) {
    return useQuery({
        queryKey: [VEHICLE_COMPANY_CHANGES_KEY, vehicleId, page, pageSize],
        queryFn: async () => {
            const from = page * pageSize
            let query = supabase
                .from('vehicle_company_changes')
                .select('*', { count: 'exact' })
                .order('created_at', { ascending: false })
                .order('id')
                .range(from, from + pageSize - 1)
            if (vehicleId) query = query.eq('vehicle_id', vehicleId)

            const { data, error, count } = await query
            if (error) throw error
            return { entries: data ?? [], total: count ?? 0 }
        },
        placeholderData: keepPreviousData,
    })
}

/**
 * Assign an Unknown vehicle, or move one between the companies as a sale.
 * change: { company, sale_value?, gst_percent? }
 */
export function useSetVehicleCompany() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ vehicleId, change }) => {
            const { data, error } = await supabase.rpc('set_vehicle_company', {
                p_vehicle_id: vehicleId,
                p_change: change,
            })
            if (error) throw readableError(error)
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['vehicles'] })
            queryClient.invalidateQueries({ queryKey: ['vehicle_company'] })
            queryClient.invalidateQueries({ queryKey: [VEHICLE_COMPANY_CHANGES_KEY] })
        },
    })
}

/**
 * One vehicle's company, by its registration number — for the Unknown banner on ticket and
 * job card pages. Resolves to null when no vehicle has that number.
 */
export function useVehicleCompany(registrationNumber) {
    return useQuery({
        queryKey: ['vehicle_company', registrationNumber],
        enabled: !!registrationNumber,
        queryFn: async () => {
            const { data, error } = await supabase
                .from('vehicles')
                .select('id, registration_number, company')
                .eq('registration_number', registrationNumber)
                .maybeSingle()
            if (error) throw error
            return data
        },
    })
}
