import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Hook to fetch all parts ordered by name
 */
export function useParts() {
    return useQuery({
        queryKey: ['parts'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('parts')
                .select('id, name, part_number, unit, quantity_in_stock')
                .order('name')

            if (error) throw error
            return data || []
        },
    })
}

/**
 * Hook to add a part to an issue
 * @param {string} jobCardId - Job Card ID for cache invalidation
 */
export function useAddIssuePart(jobCardId) {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ issue_id, part_id, quantity_used, added_by }) => {
            const { data, error } = await supabase
                .from('issue_parts')
                .insert([{ issue_id, part_id, quantity_used, added_by }])
                .select()
                .single()

            if (error) throw error
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['job_card', jobCardId] })
            queryClient.invalidateQueries({ queryKey: ['parts'] })
        },
    })
}

/**
 * Hook to delete a part from an issue (restores inventory via DB trigger)
 * @param {string} jobCardId - Job Card ID for cache invalidation
 */
export function useDeleteIssuePart(jobCardId) {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async (issuePartId) => {
            const { error } = await supabase
                .from('issue_parts')
                .delete()
                .eq('id', issuePartId)

            if (error) throw error
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['job_card', jobCardId] })
            queryClient.invalidateQueries({ queryKey: ['parts'] })
        },
    })
}
