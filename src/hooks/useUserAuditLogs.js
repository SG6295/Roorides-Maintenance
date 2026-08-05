import { useQuery, keepPreviousData } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export const USER_AUDIT_LOGS_KEY = 'user_audit_logs'

/**
 * Paginated user-management audit trail, newest first.
 *
 * RLS restricts this table to super_admins, so `enabled` keeps everyone else from
 * firing a query that would only ever come back empty.
 */
export function useUserAuditLogs({ page = 0, pageSize = 20, enabled = true } = {}) {
    return useQuery({
        queryKey: [USER_AUDIT_LOGS_KEY, page, pageSize],
        queryFn: async () => {
            const from = page * pageSize
            const to = from + pageSize - 1

            const { data, error, count } = await supabase
                .from('user_audit_logs')
                .select('*', { count: 'exact' })
                .order('performed_at', { ascending: false })
                .range(from, to)

            if (error) throw error
            return { entries: data ?? [], total: count ?? 0 }
        },
        enabled,
        placeholderData: keepPreviousData,
    })
}
