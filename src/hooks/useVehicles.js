import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useVehicles(filters = {}) {
    return useQuery({
        queryKey: ['vehicles', filters],
        queryFn: async () => {
            let query = supabase
                .from('vehicles')
                .select('id, registration_number, make, model, year, site, notes, is_active, created_at')
                .order('registration_number')

            if (filters.search) {
                query = query.or(
                    `registration_number.ilike.%${filters.search}%,make.ilike.%${filters.search}%,model.ilike.%${filters.search}%`
                )
            }
            if (filters.site) {
                query = query.eq('site', filters.site)
            }
            if (filters.active === 'active') {
                query = query.eq('is_active', true)
            } else if (filters.active === 'inactive') {
                query = query.eq('is_active', false)
            }

            const { data, error } = await query
            if (error) throw error
            return data || []
        },
    })
}

export function useCreateVehicle() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async (vehicle) => {
            const { data, error } = await supabase
                .from('vehicles')
                .insert([vehicle])
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: () => queryClient.invalidateQueries({ queryKey: ['vehicles'] }),
    })
}

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
