
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Sites live here and nowhere else.
 *
 * There used to be a second useSites in useTickets.js filtering on is_active while
 * this one did not — both under the cache key ['sites']. TanStack caches by key, so
 * whichever mounted first won and the other silently reused its rows: whether a
 * deactivated site appeared depended on the order the user navigated in. The two
 * queries now have distinct keys and callers pick by purpose (MAIN-50).
 */

/**
 * Active sites only — for *creating* things. A ticket must not be raised against a
 * school that has left.
 */
export function useActiveSites() {
    return useQuery({
        queryKey: ['sites', 'active'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('sites')
                .select('*')
                .eq('is_active', true)
                .order('name')

            if (error) throw error
            return data || []
        }
    })
}

/**
 * Every site, active or not — for *filtering history* and for editing assignments.
 * A departed site's past tickets must stay filterable, and an admin has to be able to
 * see an existing assignment in order to remove it.
 */
export function useAllSites() {
    return useQuery({
        queryKey: ['sites', 'all'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('sites')
                .select('*')
                .order('name')

            if (error) throw error
            return data || []
        }
    })
}
