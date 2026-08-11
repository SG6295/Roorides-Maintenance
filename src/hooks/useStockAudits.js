import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * Physical stock counts (MAIN-30).
 *
 * Every write goes through a SECURITY DEFINER RPC — the tables themselves carry SELECT
 * policies only. That keeps the role rules, the "one audit open per workshop" rule and
 * the stock arithmetic in one place instead of spread across the browser.
 *
 * Kept in its own file rather than added to useInventory.js, which is already long.
 */

export const AUDIT_REASONS = [
    { value: 'missing', label: 'Missing' },
    { value: 'stolen', label: 'Stolen' },
    { value: 'damaged', label: 'Damaged' },
    { value: 'found', label: 'Found / excess' },
    { value: 'other', label: 'Other' },
]

export const AUDIT_REASON_LABELS = Object.fromEntries(
    AUDIT_REASONS.map(r => [r.value, r.label])
)

export const AUDIT_STATUS_LABELS = {
    counting: 'Counting',
    review: 'Under review',
    completed: 'Completed',
    cancelled: 'Cancelled',
}

export const AUDIT_STATUS_BADGE = {
    counting: 'bg-blue-100 text-blue-700',
    review: 'bg-yellow-100 text-yellow-700',
    completed: 'bg-green-100 text-green-700',
    cancelled: 'bg-gray-100 text-gray-500',
}

/** How an audit is referred to anywhere a human reads it. */
export const auditRef = audit =>
    audit?.audit_number ? `AUD-${audit.audit_number}` : 'AUD-?'

const AUDIT_SELECT = `
    id, audit_number, location_id, status, notes,
    started_by_name, started_at,
    counts_uploaded_by_name, counts_uploaded_at,
    completed_by_name, completed_at,
    cancelled_by_name, cancelled_at, cancel_reason,
    total_parts, variance_parts, net_units, net_value, unvalued_parts,
    location:workshop_locations!location_id(id, name)
`

/**
 * Postgres surfaces our RAISE EXCEPTION text as error.message, but a constraint violation
 * arrives as machine noise. Give the user the readable half and keep the rest for the
 * console.
 */
function auditError(error) {
    if (!error) return null
    const raw = error.message || 'Something went wrong.'
    if (/violates|constraint|duplicate key|syntax/i.test(raw)) {
        console.error('[stock audit]', error)
        if (/stock_audits_one_open_per_location/.test(raw)) {
            return 'An audit was just opened at this workshop by someone else. Refresh and try again.'
        }
        return 'The audit could not be saved. Please refresh and try again.'
    }
    return raw
}

async function callAuditRpc(fn, params) {
    const { data, error } = await supabase.rpc(fn, params)
    if (error) throw new Error(auditError(error))
    return data
}

// ─── Queries ──────────────────────────────────────────────────────────────────

/** Every audit, newest first. Used for the history list. */
export function useStockAudits(filters = {}) {
    return useQuery({
        queryKey: ['stock_audits', filters],
        queryFn: async () => {
            let query = supabase
                .from('stock_audits')
                .select(AUDIT_SELECT)
                .order('started_at', { ascending: false })

            if (filters.locationId) query = query.eq('location_id', filters.locationId)
            if (filters.status) query = query.eq('status', filters.status)

            const { data, error } = await query
            if (error) throw error
            return data || []
        },
    })
}

/**
 * The audit currently open at a workshop, if any. Returns null rather than throwing when
 * there is none — "no audit here yet" is the normal state, not an error.
 */
export function useOpenStockAudit(locationId) {
    return useQuery({
        queryKey: ['stock_audits', 'open', locationId],
        enabled: !!locationId,
        queryFn: async () => {
            const { data, error } = await supabase
                .from('stock_audits')
                .select(AUDIT_SELECT)
                .eq('location_id', locationId)
                .in('status', ['counting', 'review'])
                .maybeSingle()
            if (error) throw error
            return data || null
        },
    })
}

export function useStockAudit(auditId) {
    return useQuery({
        queryKey: ['stock_audits', auditId],
        enabled: !!auditId,
        queryFn: async () => {
            const { data, error } = await supabase
                .from('stock_audits')
                .select(AUDIT_SELECT)
                .eq('id', auditId)
                .single()
            if (error) throw error
            return data
        },
    })
}

export function useStockAuditItems(auditId) {
    return useQuery({
        queryKey: ['stock_audit_items', auditId],
        enabled: !!auditId,
        queryFn: async () => {
            const { data, error } = await supabase
                .from('stock_audit_items')
                .select('*')
                .eq('audit_id', auditId)
                .order('part_name_snapshot')
            if (error) throw error
            return (data || []).map(row => ({
                ...row,
                system_qty: Number(row.system_qty ?? 0),
                counted_qty: row.counted_qty === null ? null : Number(row.counted_qty),
                variance: row.variance === null ? null : Number(row.variance),
            }))
        },
    })
}

/**
 * What legitimately moved at this workshop since the count sheet was generated, grouped
 * by part. Without this a final figure that differs from the counted figure reads as a
 * bug rather than as a job card doing its job.
 */
export function useStockAuditMovements(auditId) {
    return useQuery({
        queryKey: ['stock_audit_movements', auditId],
        enabled: !!auditId,
        queryFn: async () => {
            const { data, error } = await supabase.rpc('stock_audit_movements', {
                p_audit_id: auditId,
            })
            if (error) throw error

            return (data || []).reduce((acc, row) => {
                const list = acc[row.part_id] || (acc[row.part_id] = [])
                list.push({ ...row, quantity: Number(row.quantity ?? 0) })
                return acc
            }, {})
        },
    })
}

// ─── Mutations ────────────────────────────────────────────────────────────────

/**
 * Invalidate everything an audit can touch. Completion moves real stock, so the parts
 * catalog, the per-location tables and consumption history all go stale at once.
 */
function invalidateAudit(queryClient) {
    queryClient.invalidateQueries({ queryKey: ['stock_audits'] })
    queryClient.invalidateQueries({ queryKey: ['stock_audit_items'] })
    queryClient.invalidateQueries({ queryKey: ['stock_audit_movements'] })
    queryClient.invalidateQueries({ queryKey: ['part_stock'] })
    queryClient.invalidateQueries({ queryKey: ['parts'] })
    queryClient.invalidateQueries({ queryKey: ['part_consumption'] })
}

export function useStartStockAudit() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: ({ locationId, notes }) =>
            callAuditRpc('start_stock_audit', {
                p_location_id: locationId,
                p_notes: notes || null,
            }),
        onSuccess: () => invalidateAudit(queryClient),
    })
}

/** @param {Array<{part_id: string, counted_qty: number}>} counts */
export function useSubmitStockAuditCounts() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: ({ auditId, counts }) =>
            callAuditRpc('submit_stock_audit_counts', {
                p_audit_id: auditId,
                p_counts: counts.map(c => ({
                    part_id: c.part_id,
                    counted_qty: Number(c.counted_qty),
                })),
            }),
        onSuccess: () => invalidateAudit(queryClient),
    })
}

/** @param {Array<{part_id: string, reason: string|null, notes: string|null}>} items */
export function useSetStockAuditReasons() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: ({ auditId, items }) =>
            callAuditRpc('set_stock_audit_reasons', {
                p_audit_id: auditId,
                p_items: items.map(i => ({
                    part_id: i.part_id,
                    reason: i.reason || null,
                    notes: i.notes || null,
                })),
            }),
        onSuccess: () => invalidateAudit(queryClient),
    })
}

export function useCompleteStockAudit() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: ({ auditId }) =>
            callAuditRpc('complete_stock_audit', { p_audit_id: auditId }),
        onSuccess: () => invalidateAudit(queryClient),
    })
}

export function useCancelStockAudit() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: ({ auditId, reason }) =>
            callAuditRpc('cancel_stock_audit', {
                p_audit_id: auditId,
                p_reason: reason || null,
            }),
        onSuccess: () => invalidateAudit(queryClient),
    })
}
