import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * One company's ledger (MAIN-156), oldest first, with both running columns. Every line is
 * derived from purchases, accepted invoices and vehicle sales, except the reconciliation
 * adjustments finance posts (MAIN-163). `get_company_ledger` checks the caller is exec,
 * super_admin or finance.
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

function useCompanyLedgerMutation(mutationFn) {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn,
        onSuccess: () => queryClient.invalidateQueries({ queryKey: ['company_ledger'] }),
    })
}

/**
 * MAIN-163: records the figure finance confirmed in Tally. `balance` is 'spent' or 'owed';
 * `confirmedBalance` a decimal string (Owed: positive = the other company owes this one).
 * The database works out the app's figure and the difference itself.
 */
export function useReconcileCompanyLedger() {
    return useCompanyLedgerMutation(async ({ company, balance, asOf, confirmedBalance, reason }) => {
        const { data, error } = await supabase.rpc('reconcile_company_ledger', {
            p_company: company,
            p_reconciliation: { balance, as_of: asOf, confirmed_balance: confirmedBalance, reason },
        })
        if (error) throw error
        return data
    })
}

/** Undoes an adjustment posted in error; it stays on the ledger, struck through. */
export function useReverseCompanyLedgerAdjustment() {
    return useCompanyLedgerMutation(async ({ adjustmentId, reason }) => {
        const { error } = await supabase.rpc('reverse_company_ledger_adjustment', {
            p_adjustment_id: adjustmentId,
            p_reason: reason,
        })
        if (error) throw error
    })
}
