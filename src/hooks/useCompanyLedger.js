import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * One company's ledger (MAIN-156), oldest first, with both running columns. Read-only:
 * every line is derived from purchases, accepted invoices and vehicle sales, so there is
 * nothing to write. `get_company_ledger` checks the caller is exec, super_admin or finance.
 */
export function useCompanyLedger(company) {
    return useQuery({
        queryKey: ['company_ledger', company],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_company_ledger', { p_company: company })
            if (error) throw error
            return data ?? []
        },
        enabled: !!company,
    })
}
