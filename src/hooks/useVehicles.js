import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { fetchAllRows } from '../utils/fetchAllRows'


export function useVehicles(filters = {}) {
    return useQuery({
        queryKey: ['vehicles', filters],
        // Keep the current rows visible while a new search term loads — see useSuppliers.
        placeholderData: keepPreviousData,
        // Batched: vehicles are never deleted, so this list will outgrow the API's
        // 1,000-row cap (MAIN-83). registration_number is unique, so the order is stable.
        queryFn: () => fetchAllRows(() => {
            const joinType = filters.site ? '!inner' : ''
            let query = supabase
                .from('vehicles')
                .select(`id, registration_number, make, model, year, notes, is_active, created_at, vehicle_sites${joinType}(site_name)`)
                .order('registration_number')

            if (filters.search) {
                query = query.or(
                    `registration_number.ilike.%${filters.search}%,make.ilike.%${filters.search}%,model.ilike.%${filters.search}%`
                )
            }
            if (filters.site) {
                query = query.eq('vehicle_sites.site_name', filters.site)
            }
            if (filters.active === 'active') {
                query = query.eq('is_active', true)
            } else if (filters.active === 'inactive') {
                query = query.eq('is_active', false)
            }

            return query
        }),
    })
}

/**
 * Vehicles are created only by the sync-roorides-vehicles feed (MAIN-68) — there is
 * deliberately no create hook, and the RLS policy on public.vehicles is UPDATE-only so
 * the database refuses a browser insert even if one were attempted.
 *
 * Only `year` and `notes` may be updated. Every other column (registration_number, make,
 * model, type, is_active, raw_data) is rewritten by the sync on each run, so a local edit
 * to one is silently reverted within 24 hours.
 */
export function useUpdateVehicle() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ id, ...fields }) => {
            const { data, error } = await supabase
                .from('vehicles')
                .update(fields)
                .eq('id', id)
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: () => queryClient.invalidateQueries({ queryKey: ['vehicles'] }),
    })
}
