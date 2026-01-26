import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { logAuditEvent } from '../utils/auditLogger'

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
          issues(*, ticket:ticket_id(ticket_number))
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
 * Hook to link multiple issues to an existing Job Card
 * @param {object} options
 * @param {string} options.userId - User ID for audit logging
 * @param {array} options.issues - Full issue objects for audit logging
 */
export function useLinkIssuesToJobCard() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ jobCardId, issueIds, userId, issues }) => {
            if (!issueIds || issueIds.length === 0) return { jobCardId, ticketIds: [] }

            // Get job card info for audit log
            const { data: jobCard } = await supabase
                .from('job_cards')
                .select('job_card_number')
                .eq('id', jobCardId)
                .single()

            const { error } = await supabase
                .from('issues')
                .update({ job_card_id: jobCardId })
                .in('id', issueIds)

            if (error) throw error

            // Log audit events for each issue being linked
            const ticketIds = new Set()
            if (userId && issues) {
                for (const issue of issues) {
                    if (issueIds.includes(issue.id)) {
                        ticketIds.add(issue.ticket_id)
                        await logAuditEvent(
                            issue.ticket_id,
                            'issues',
                            'UPDATE',
                            userId,
                            {
                                oldData: {
                                    ...issue,
                                    _actionType: 'issue_linked_to_job_card',
                                    _jobCardNumber: jobCard?.job_card_number
                                },
                                newData: { ...issue, job_card_id: jobCardId },
                                changedFields: ['job_card_id']
                            }
                        )
                    }
                }
            }

            return { jobCardId, ticketIds: Array.from(ticketIds) }
        },
        onSuccess: (data) => {
            queryClient.invalidateQueries({ queryKey: ['job_cards'] })
            queryClient.invalidateQueries({ queryKey: ['issues'] })
            queryClient.invalidateQueries({ queryKey: ['tickets'] })
            // Invalidate audit logs for affected tickets
            if (data?.ticketIds) {
                data.ticketIds.forEach(ticketId => {
                    queryClient.invalidateQueries({ queryKey: ['audit_logs', ticketId] })
                })
            }
        },
    })
}

/**
 * Hook to create a Job Card and link issues to it
 * @param {object} options
 * @param {string} options.userId - User ID for audit logging
 * @param {array} options.issues - Full issue objects for audit logging
 */
export function useCreateJobCard() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ jobCardData, issueIds, userId, issues }) => {
            // 1. Create Job Card
            const { data: jobCard, error: jcError } = await supabase
                .from('job_cards')
                .insert([jobCardData])
                .select()
                .single()

            if (jcError) throw jcError

            // 2. Link Issues to this Job Card
            const ticketIds = new Set()
            if (issueIds && issueIds.length > 0) {
                const { error: linkError } = await supabase
                    .from('issues')
                    .update({ job_card_id: jobCard.id })
                    .in('id', issueIds)

                if (linkError) throw linkError

                // Log audit events for each issue being linked
                if (userId && issues) {
                    for (const issue of issues) {
                        if (issueIds.includes(issue.id)) {
                            ticketIds.add(issue.ticket_id)
                            await logAuditEvent(
                                issue.ticket_id,
                                'issues',
                                'UPDATE',
                                userId,
                                {
                                    oldData: {
                                        ...issue,
                                        _actionType: 'issue_linked_to_job_card',
                                        _jobCardNumber: jobCard.job_card_number
                                    },
                                    newData: { ...issue, job_card_id: jobCard.id },
                                    changedFields: ['job_card_id']
                                }
                            )
                        }
                    }
                }
            }

            return { ...jobCard, ticketIds: Array.from(ticketIds) }
        },
        onSuccess: (data) => {
            queryClient.invalidateQueries({ queryKey: ['job_cards'] })
            queryClient.invalidateQueries({ queryKey: ['issues'] })
            queryClient.invalidateQueries({ queryKey: ['tickets'] })
            // Invalidate audit logs for affected tickets
            if (data?.ticketIds) {
                data.ticketIds.forEach(ticketId => {
                    queryClient.invalidateQueries({ queryKey: ['audit_logs', ticketId] })
                })
            }
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
