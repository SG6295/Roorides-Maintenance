import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { logAuditEvent } from '../utils/auditLogger'

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
 * @param {object} options - Optional configuration
 * @param {string} options.userId - User ID for audit logging
 */
export function useCreateIssue() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ issueData, userId }) => {
            const { data, error } = await supabase
                .from('issues')
                .insert([issueData])
                .select()
                .single()

            if (error) throw error

            // Log audit event for issue creation
            if (userId) {
                await logAuditEvent(
                    data.ticket_id, // Use ticket_id as record_id for grouping
                    'issues',
                    'INSERT',
                    userId,
                    {
                        oldData: null,
                        newData: data,
                        changedFields: ['issue_created']
                    }
                )
            }

            return data
        },
        onSuccess: (data) => {
            queryClient.invalidateQueries({ queryKey: ['issues'] })
            queryClient.invalidateQueries({ queryKey: ['ticket', data.ticket_id] })
            queryClient.invalidateQueries({ queryKey: ['audit_logs', data.ticket_id] })
        },
    })
}

/**
 * Hook to update an issue
 * @param {object} options - Optional configuration
 * @param {string} options.userId - User ID for audit logging
 * @param {object} options.oldData - Previous state of the issue for audit diff
 */
export function useUpdateIssue() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ id, updates, userId, oldData }) => {
            console.log('useUpdateIssue: Sending to Supabase', { id, updates })
            const { data, error } = await supabase
                .from('issues')
                .update(updates)
                .eq('id', id)
                .select()
                .single()

            console.log('useUpdateIssue: Supabase response', { data, error })
            if (error) throw error

            // Log audit event for issue update
            if (userId && oldData) {
                // Determine what changed
                const changedFields = Object.keys(updates).filter(key =>
                    JSON.stringify(oldData[key]) !== JSON.stringify(data[key])
                )

                // Detect job card linking/unlinking for special labeling
                let actionType = 'issue_updated'
                if (changedFields.includes('job_card_id')) {
                    if (oldData.job_card_id === null && data.job_card_id !== null) {
                        actionType = 'issue_linked_to_job_card'
                    } else if (oldData.job_card_id !== null && data.job_card_id === null) {
                        actionType = 'issue_unlinked_from_job_card'
                    }
                }

                await logAuditEvent(
                    data.ticket_id,
                    'issues',
                    'UPDATE',
                    userId,
                    {
                        oldData: { ...oldData, _actionType: actionType },
                        newData: data,
                        changedFields: changedFields.length > 0 ? changedFields : ['issue_updated']
                    }
                )
            }

            return data
        },
        onSuccess: (data) => {
            queryClient.invalidateQueries({ queryKey: ['issues'] })
            queryClient.invalidateQueries({ queryKey: ['ticket', data.ticket_id] })
            queryClient.invalidateQueries({ queryKey: ['audit_logs', data.ticket_id] })
            // Also invalidate job card queries if this issue has a job_card_id
            if (data.job_card_id) {
                queryClient.invalidateQueries({ queryKey: ['job_card', data.job_card_id] })
                queryClient.invalidateQueries({ queryKey: ['job_cards'] })
            }
        },
    })
}

/**
 * Hook to delete an issue
 * @param {object} options - Optional configuration
 * @param {string} options.userId - User ID for audit logging
 * @param {object} options.oldData - Issue data before deletion for audit log
 */
export function useDeleteIssue() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ issueId, userId, oldData }) => {
            // First get the ticket_id to invalidate cache
            const { data: issue } = await supabase.from('issues').select('*').eq('id', issueId).single()

            const { error } = await supabase
                .from('issues')
                .delete()
                .eq('id', issueId)

            if (error) throw error

            // Log audit event for issue deletion
            if (userId && issue) {
                await logAuditEvent(
                    issue.ticket_id,
                    'issues',
                    'DELETE',
                    userId,
                    {
                        oldData: oldData || issue,
                        newData: null,
                        changedFields: ['issue_deleted']
                    }
                )
            }

            return issue
        },
        onSuccess: (data) => {
            if (data?.ticket_id) {
                queryClient.invalidateQueries({ queryKey: ['issues'] })
                queryClient.invalidateQueries({ queryKey: ['ticket', data.ticket_id] })
                queryClient.invalidateQueries({ queryKey: ['audit_logs', data.ticket_id] })
            }
        },
    })
}
