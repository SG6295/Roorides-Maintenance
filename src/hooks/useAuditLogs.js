import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Fetches audit logs for a ticket, including:
 * - Direct ticket changes (table_name = 'tickets', record_id = ticketId)
 * - Issue changes related to this ticket (table_name = 'issues', record_id = ticketId)
 */
export function useAuditLogs(ticketId) {
    return useQuery({
        queryKey: ['audit_logs', ticketId],
        queryFn: async () => {
            // Fetch audit logs where record_id matches ticketId
            // This covers both direct ticket changes and issue changes
            // (issues use ticket_id as record_id for proper grouping)
            const { data, error } = await supabase
                .from('audit_logs')
                .select(`
          *,
          performed_by_user:performed_by (
            name,
            role
          )
        `)
                .eq('record_id', ticketId)
                .order('performed_at', { ascending: false })

            if (error) throw error
            return data
        },
        enabled: !!ticketId
    })
}
