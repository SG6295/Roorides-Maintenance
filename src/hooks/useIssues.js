import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Hook to fetch issues (optionally filtered)
 */
export function useIssues(filters = {}) {
    // Handle legacy string argument (ticketId) if any, though we should migrate calls
    const actualFilters = typeof filters === 'string' ? { ticket_id: filters } : filters

    return useQuery({
        queryKey: ['issues', actualFilters],
        queryFn: async () => {
            let query = supabase
                .from('issues')
                .select(`
          *,
          job_card:job_cards(*),
          ticket:ticket_id(ticket_number, vehicle_number, site)
        `)
                .order('created_at', { ascending: true })

            if (actualFilters.ticket_id) {
                query = query.eq('ticket_id', actualFilters.ticket_id)
            }
            if (actualFilters.status) {
                query = query.eq('status', actualFilters.status)
            }
            if (actualFilters.category) {
                query = query.eq('category', actualFilters.category)
            }

            const { data, error } = await query

            if (error) throw error
            return data || []
        },
        enabled: true, // Always enabled, filters are optional
    })
}

/**
 * Hook to create a new issue
 */
export function useCreateIssue() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async (issueData) => {
            const { data, error } = await supabase
                .from('issues')
                .insert([issueData])
                .select()
                .single()

            if (error) throw error
            return data
        },
        onSuccess: (data) => {
            queryClient.invalidateQueries({ queryKey: ['issues'] })
            queryClient.invalidateQueries({ queryKey: ['ticket', data.ticket_id] }) // Ticket status might change
        },
    })
}

/**
 * Hook to update an issue
 */
export function useUpdateIssue() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ id, updates }) => {
            const { data, error } = await supabase
                .from('issues')
                .update(updates)
                .eq('id', id)
                .select()
                .single()

            if (error) throw error
            return data
        },
        onSuccess: (data) => {
            queryClient.invalidateQueries({ queryKey: ['issues'] })
            queryClient.invalidateQueries({ queryKey: ['ticket', data.ticket_id] })
        },
    })
}

/**
 * Hook to delete an issue
 */
export function useDeleteIssue() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async (issueId) => {
            // First get the ticket_id to invalidate cache
            const { data: issue } = await supabase.from('issues').select('ticket_id').eq('id', issueId).single()

            const { error } = await supabase
                .from('issues')
                .delete()
                .eq('id', issueId)

            if (error) throw error
            return issue
        },
        onSuccess: (data) => {
            if (data?.ticket_id) {
                queryClient.invalidateQueries({ queryKey: ['issues'] })
                queryClient.invalidateQueries({ queryKey: ['ticket', data.ticket_id] })
            }
        },
    })
}
