import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useSLAEvents(ticketId) {
    return useQuery({
        queryKey: ['sla_events', ticketId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('sla_events')
                .select(`
          *,
          created_by_user:created_by (
            name,
            role
          )
        `)
                .eq('ticket_id', ticketId)
                .order('created_at', { ascending: false })

            if (error) throw error
            return data
        },
        enabled: !!ticketId
    })
}
