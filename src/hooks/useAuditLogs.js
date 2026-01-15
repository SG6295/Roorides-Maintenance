import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useAuditLogs(ticketId) {
    return useQuery({
        queryKey: ['audit_logs', ticketId],
        queryFn: async () => {
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
                .eq('table_name', 'tickets')
                .order('performed_at', { ascending: false })

            if (error) throw error
            return data
        },
        enabled: !!ticketId
    })
}
