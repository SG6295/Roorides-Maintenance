import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * The supplier ledger (MAIN-119). Every figure comes from database functions, which
 * check the caller is exec, super_admin or finance; every write goes through a function
 * that allows finance and super_admin only.
 */

const toNumber = v => (v == null ? 0 : Number(v))

function normaliseBalance(row) {
    return {
        ...row,
        outstanding:        toNumber(row.outstanding),
        overdue:            toNumber(row.overdue),
        due_this_wednesday: toNumber(row.due_this_wednesday),
        due_next_wednesday: toNumber(row.due_next_wednesday),
        later:              toNumber(row.later),
        awaiting_acceptance: toNumber(row.awaiting_acceptance),
    }
}

/** One row per supplier: outstanding and the Wednesday buckets. */
export function useSupplierBalances() {
    return useQuery({
        queryKey: ['supplier_ledger', 'balances'],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_supplier_balances')
            if (error) throw error
            return (data ?? []).map(normaliseBalance)
        },
    })
}

export function useSupplierBalance(supplierId) {
    return useQuery({
        queryKey: ['supplier_ledger', 'balance', supplierId],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_supplier_balances', { p_supplier_id: supplierId })
            if (error) throw error
            return data?.[0] ? normaliseBalance(data[0]) : null
        },
        enabled: !!supplierId,
    })
}

/** Every line, oldest first, with the running balance. */
export function useSupplierStatement(supplierId) {
    return useQuery({
        queryKey: ['supplier_ledger', 'statement', supplierId],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_supplier_statement', { p_supplier_id: supplierId })
            if (error) throw error
            return data ?? []
        },
        enabled: !!supplierId,
    })
}

/** What is still open, oldest payments clearing the oldest invoices first. */
export function useSupplierOpenItems(supplierId) {
    return useQuery({
        queryKey: ['supplier_ledger', 'open', supplierId],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_supplier_open_items', { p_supplier_id: supplierId })
            if (error) throw error
            return data ?? []
        },
        enabled: !!supplierId,
    })
}

function useLedgerMutation(mutationFn, alsoInvalidate = []) {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn,
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['supplier_ledger'] })
            for (const key of alsoInvalidate) queryClient.invalidateQueries({ queryKey: key })
        },
    })
}

/** payment: { amount_paid, tds_amount, paid_on, payment_method, bank, utr } — always Bill accounted. */
export function useRecordSupplierPayment() {
    return useLedgerMutation(async ({ supplierId, payment }) => {
        const { data, error } = await supabase.rpc('record_supplier_payment', {
            p_supplier_id: supplierId,
            p_payment: payment,
        })
        if (error) throw error
        return data
    })
}

export function useCancelSupplierPayment() {
    return useLedgerMutation(async ({ paymentId, reason }) => {
        const { error } = await supabase.rpc('cancel_supplier_payment', {
            p_payment_id: paymentId,
            p_reason: reason,
        })
        if (error) throw error
    })
}

export function useReconcileSupplierBalance() {
    return useLedgerMutation(async ({ supplierId, asOf, confirmedAgainst, confirmedBalance, reason }) => {
        const { data, error } = await supabase.rpc('reconcile_supplier_balance', {
            p_supplier_id:       supplierId,
            p_as_of:             asOf,
            p_confirmed_against: confirmedAgainst,
            p_confirmed_balance: confirmedBalance,
            p_reason:            reason,
        })
        if (error) throw error
        return data
    })
}

/** days: a whole number 0–365, or null to clear (counts as 0). */
export function useSetSupplierCreditDays() {
    return useLedgerMutation(async ({ supplierId, days }) => {
        const { error } = await supabase.rpc('set_supplier_credit_days', {
            p_supplier_id: supplierId,
            p_days: days,
        })
        if (error) throw error
    }, [['suppliers'], ['supplier']])
}

/** Undoes a reconciliation adjustment posted in error; it stays on the statement, struck through. */
export function useReverseAdjustment() {
    return useLedgerMutation(async ({ adjustmentId, reason }) => {
        const { error } = await supabase.rpc('reverse_ledger_adjustment', {
            p_adjustment_id: adjustmentId,
            p_reason: reason,
        })
        if (error) throw error
    })
}

// ── Advances to repay ───────────────────────────────────────────────────────────

/** One row per person who pays suppliers upfront: owed, and the Wednesday buckets. */
export function useAdvanceBalances() {
    return useQuery({
        queryKey: ['supplier_ledger', 'advances'],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_advance_balances')
            if (error) throw error
            return (data ?? []).map(row => ({
                ...row,
                owed:               toNumber(row.owed),
                overdue:            toNumber(row.overdue),
                due_this_wednesday: toNumber(row.due_this_wednesday),
                due_next_wednesday: toNumber(row.due_next_wednesday),
                later:              toNumber(row.later),
            }))
        },
    })
}

export function useAdvanceStatement(person) {
    return useQuery({
        queryKey: ['supplier_ledger', 'advance_statement', person],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_advance_statement', { p_person: person })
            if (error) throw error
            return data ?? []
        },
        enabled: !!person,
    })
}

export function useAdvanceOpenItems(person) {
    return useQuery({
        queryKey: ['supplier_ledger', 'advance_open', person],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_advance_open_items', { p_person: person })
            if (error) throw error
            return data ?? []
        },
        enabled: !!person,
    })
}

/** payment: { amount, paid_on, payment_method, bank, utr } */
export function useRecordAdvanceRepayment() {
    return useLedgerMutation(async ({ person, payment }) => {
        const { data, error } = await supabase.rpc('record_advance_repayment', {
            p_person: person,
            p_payment: payment,
        })
        if (error) throw error
        return data
    })
}

export function useCancelAdvanceRepayment() {
    return useLedgerMutation(async ({ repaymentId, reason }) => {
        const { error } = await supabase.rpc('cancel_advance_repayment', {
            p_repayment_id: repaymentId,
            p_reason: reason,
        })
        if (error) throw error
    })
}
