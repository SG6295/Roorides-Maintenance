import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { ScrapRPCError } from './useScrap'

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
 * Creates a new part with qty=0, tagged as outsource-created.
 * Used by the inline part-creation form in IssueWorkCard on outsource job cards.
 */
export function useCreatePart() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ name, unit, part_number }) => {
            const { data, error } = await supabase
                .from('parts')
                .insert([{
                    name: name.trim(),
                    unit: unit.trim(),
                    part_number: part_number?.trim() || null,
                    quantity_in_stock: 0,
                    created_via: 'outsource_jobcard',
                }])
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['parts'] })
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

export function useDeleteIssuePart(jobCardId) {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async (issuePartId) => {
            const { data, error } = await supabase.rpc(
                'delete_issue_part_with_scrap_check',
                { p_issue_part_id: issuePartId }
            )
            if (error) {
                try {
                    const parsed = JSON.parse(error.message)
                    if (parsed.error_code) throw new ScrapRPCError(parsed)
                } catch (parseErr) {
                    if (parseErr instanceof ScrapRPCError) throw parseErr
                }
                throw error
            }
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['job_card', jobCardId] })
            queryClient.invalidateQueries({ queryKey: ['parts'] })
            queryClient.invalidateQueries({ queryKey: ['scrap_inventory'] })
        },
    })
}
