import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Hook to fetch Job Cards (General list or by ticket?)
 * Usually we view job cards associated with tickets via the Issue link.
 * But we also need a global list.
 */
export function useJobCards(filters = {}) {
    return useQuery({
        queryKey: ['job_cards', filters],
        queryFn: async () => {
            let query = supabase
                .from('job_cards')
                .select(`
          *,
          mechanic:assigned_mechanic_id(name, email),
          issues(*)
        `)
                .order('created_at', { ascending: false })

            if (filters.status) {
                query = query.eq('status', filters.status)
            }
            if (filters.site) {
                query = query.eq('site', filters.site)
            }
            if (filters.vehicle_number) {
                query = query.eq('vehicle_number', filters.vehicle_number)
            }

            const { data, error } = await query
            if (error) throw error
            return data || []
        },
    })
}

/**
 * Hook to fetch a single Job Card by ID
 */
export function useJobCard(id) {
    return useQuery({
        queryKey: ['job_card', id],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('job_cards')
                .select(`
          *,
          mechanic:assigned_mechanic_id(name, email, contact),
          issues(*)
        `)
                .eq('id', id)
                .single()

            if (error) throw error
            return data
        },
        enabled: !!id,
    })
}

/**
 * Hook to create a Job Card and link issues to it
 */
/**
 * Hook to link multiple issues to an existing Job Card
 */
export function useLinkIssuesToJobCard() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ jobCardId, issueIds }) => {
            if (!issueIds || issueIds.length === 0) return

            const { error } = await supabase
                .from('issues')
                .update({ job_card_id: jobCardId })
                .in('id', issueIds)

            if (error) throw error
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['job_cards'] })
            queryClient.invalidateQueries({ queryKey: ['issues'] })
            queryClient.invalidateQueries({ queryKey: ['tickets'] })
        },
    })
}

/**
 * Hook to create a Job Card and link issues to it
 */
export function useCreateJobCard() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ jobCardData, issueIds }) => {
            // 1. Create Job Card
            const { data: jobCard, error: jcError } = await supabase
                .from('job_cards')
                .insert([jobCardData])
                .select()
                .single()

            if (jcError) throw jcError

            // 2. Link Issues to this Job Card
            if (issueIds && issueIds.length > 0) {
                const { error: linkError } = await supabase
                    .from('issues')
                    .update({ job_card_id: jobCard.id }) // We don't overwrite status here, assume triggers/logic handles it or it stays Open
                    .in('id', issueIds)

                if (linkError) throw linkError
            }

            return jobCard
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['job_cards'] })
            queryClient.invalidateQueries({ queryKey: ['issues'] })
            queryClient.invalidateQueries({ queryKey: ['tickets'] })
        },
    })
}

/**
 * Hook to update Job Card
 */
export function useUpdateJobCard() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ id, updates }) => {
            const { data, error } = await supabase
                .from('job_cards')
                .update(updates)
                .eq('id', id)
                .select()
                .single()

            if (error) throw error
            return data
        },
        onSuccess: (data) => {
            queryClient.invalidateQueries({ queryKey: ['job_card', data.id] })
            queryClient.invalidateQueries({ queryKey: ['job_cards'] })
        },
    })
}
