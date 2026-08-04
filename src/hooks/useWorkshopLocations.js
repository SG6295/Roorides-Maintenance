import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Workshop locations — the physical workshops where repairs happen and stock is held.
 * Not to be confused with `sites`, which are the customer sites vehicles run at.
 *
 * Only super admins can write (enforced by RLS); everyone signed in can read.
 */
export function useWorkshopLocations({ includeInactive = false } = {}) {
    return useQuery({
        queryKey: ['workshop_locations', { includeInactive }],
        queryFn: async () => {
            let query = supabase
                .from('workshop_locations')
                .select('id, name, address, is_active')
                .order('name')

            if (!includeInactive) query = query.eq('is_active', true)

            const { data, error } = await query
            if (error) throw error
            return data || []
        },
    })
}

export function useCreateWorkshopLocation() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ name, address }) => {
            const { data, error } = await supabase
                .from('workshop_locations')
                .insert([{ name: name.trim(), address: address?.trim() || null }])
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: () => queryClient.invalidateQueries({ queryKey: ['workshop_locations'] }),
    })
}

export function useUpdateWorkshopLocation() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ id, name, address }) => {
            const { data, error } = await supabase
                .from('workshop_locations')
                .update({ name: name.trim(), address: address?.trim() || null })
                .eq('id', id)
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['workshop_locations'] })
            // Names appear on job cards, inventory and scrap rows.
            queryClient.invalidateQueries({ queryKey: ['job_cards'] })
            queryClient.invalidateQueries({ queryKey: ['part_stock'] })
        },
    })
}

/**
 * Locations are never deleted — historical job cards and invoices must keep resolving
 * to a real row. Deactivating is blocked while the location still holds stock or has
 * open job cards, since that stock would become unreachable.
 */
export function useToggleWorkshopLocation() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ id, is_active }) => {
            if (!is_active) {
                const { data: stock, error: stockErr } = await supabase
                    .from('part_stock')
                    .select('part_id, quantity')
                    .eq('location_id', id)
                    .gt('quantity', 0)
                if (stockErr) throw stockErr
                if (stock?.length) {
                    throw new Error(
                        `This workshop still holds ${stock.length} part${stock.length === 1 ? '' : 's'} in stock. ` +
                        'Move the stock to another workshop before deactivating it.'
                    )
                }

                const { data: openCards, error: cardsErr } = await supabase
                    .from('job_cards')
                    .select('id')
                    .eq('location_id', id)
                    .neq('status', 'Completed')
                if (cardsErr) throw cardsErr
                if (openCards?.length) {
                    throw new Error(
                        `This workshop has ${openCards.length} job card${openCards.length === 1 ? '' : 's'} still open. ` +
                        'Close or move them before deactivating it.'
                    )
                }
            }

            const { data, error } = await supabase
                .from('workshop_locations')
                .update({ is_active })
                .eq('id', id)
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: () => queryClient.invalidateQueries({ queryKey: ['workshop_locations'] }),
    })
}
