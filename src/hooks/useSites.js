
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useSites() {
    return useQuery({
        queryKey: ['sites'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('sites')
                .select('*')
                .order('name')

            if (error) throw error
            return data
        }
    })
}
