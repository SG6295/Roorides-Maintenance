import { useQuery, keepPreviousData } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { PAGE_SIZE } from '../utils/fetchAllRows'

/**
 * Rows behind Analytics › Labour utilisation (MAIN-117) — see get_labour_report and
 * src/utils/labourReport.js. Site, trade and technician filters are applied on the client,
 * so changing them does not refetch.
 *
 * Batched like fetchAllRows (the API caps a response at 1,000 rows, MAIN-83), but without
 * its de-duplication by `id`: these rows have no id, and that step would keep only the first.
 */
export function useLabourReport({ start, end }) {
    return useQuery({
        queryKey: ['labour_report', start, end],
        queryFn: async () => {
            const rows = []
            for (let from = 0; ; from += PAGE_SIZE) {
                const { data, error } = await supabase
                    .rpc('get_labour_report', { p_from: start, p_to: end })
                    .order('completed_on', { ascending: true, nullsFirst: false })
                    .order('issue_id')
                    .order('technician_id', { nullsFirst: true })
                    .range(from, from + PAGE_SIZE - 1)
                if (error) throw error
                rows.push(...(data || []))
                if (!data || data.length < PAGE_SIZE) return rows
            }
        },
        enabled: !!start && !!end,
        placeholderData: keepPreviousData,
    })
}
