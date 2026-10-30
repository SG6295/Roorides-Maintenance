import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Active mechanics and electricians — the people labour can be recorded against
 * (MAIN-116). The database enforces the same rule in guard_issue_labour.
 */
export function useTechnicians({ enabled = true } = {}) {
    return useQuery({
        queryKey: ['technicians'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('users')
                .select('id, name, role')
                .in('role', ['mechanic', 'electrician'])
                .eq('is_active', true)
                .order('name')
            if (error) throw error
            return data || []
        },
        enabled,
    })
}

// Labour feeds the job card, the ticket timeline, the vehicle history and the mechanic pages.
function invalidateLabour(queryClient, jobCardId) {
    queryClient.invalidateQueries({ queryKey: ['job_card', jobCardId] })
    queryClient.invalidateQueries({ queryKey: ['audit_logs'] })
    queryClient.invalidateQueries({ queryKey: ['vehicle_history'] })
    queryClient.invalidateQueries({ queryKey: ['mechanic_activity'] })
}

/**
 * Each change is written to the ticket timeline by the issue_labour_audit trigger,
 * so these hooks do not log it themselves.
 * @param {string} jobCardId - the key useJobCard caches under
 */
export function useAddIssueLabour(jobCardId) {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ issue_id, technician_id, hours }) => {
            const { error } = await supabase
                .from('issue_labour')
                .insert([{ issue_id, technician_id, hours }])
            if (error) {
                if (error.code === '23505') throw new Error('This person is already recorded on this work item.')
                throw error
            }
        },
        onSuccess: () => invalidateLabour(queryClient, jobCardId),
    })
}

export function useUpdateIssueLabour(jobCardId) {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ id, hours }) => {
            const { error } = await supabase
                .from('issue_labour')
                .update({ hours })
                .eq('id', id)
            if (error) throw error
        },
        onSuccess: () => invalidateLabour(queryClient, jobCardId),
    })
}

export function useDeleteIssueLabour(jobCardId) {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async (id) => {
            const { error } = await supabase
                .from('issue_labour')
                .delete()
                .eq('id', id)
            if (error) throw error
        },
        onSuccess: () => invalidateLabour(queryClient, jobCardId),
    })
}
