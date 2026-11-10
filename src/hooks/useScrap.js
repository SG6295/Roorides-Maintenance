import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { auditRef } from './useStockAudits'

export class ScrapRPCError extends Error {
    constructor(payload) {
        super(payload.error_message || 'Scrap RPC error')
        this.name = 'ScrapRPCError'
        this.errorCode = payload.error_code
        this.details = payload.details
    }
}

export function useCloseJobCardWithScrap() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ jobCardId, remarks, scrapDecisions, invoicePending = false }) => {
            const { data, error } = await supabase.rpc('close_job_card_with_scrap', {
                p_job_card_id:     jobCardId,
                p_remarks:         remarks || null,
                p_scrap_decisions: scrapDecisions,
                p_invoice_pending: invoicePending,
            })

            if (error) {
                // RAISE EXCEPTION puts JSON in error.message — try to parse it
                try {
                    const parsed = JSON.parse(error.message)
                    if (parsed.error_code) throw new ScrapRPCError(parsed)
                } catch (parseErr) {
                    if (parseErr instanceof ScrapRPCError) throw parseErr
                }
                throw error
            }

            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['job_card'] })
            queryClient.invalidateQueries({ queryKey: ['job_cards'] })
            // The closure may have set or cleared a part's scrap default (MAIN-56),
            // so the Parts Catalog can no longer be trusted to be current.
            queryClient.invalidateQueries({ queryKey: ['parts'] })
        },
    })
}

// ── Phase 5: existing scrap state for the closure modal ──────────────────────

const PERMANENT_SCRAP_STATUSES = ['sold', 'written_off', 'refurbished', 'sent_for_refurbishment']

export { PERMANENT_SCRAP_STATUSES }

// Returns a map: { [issue_part_id]: { id, status } | null }
// Used by ScrapDecisionModal to determine which parts have permanent scrap.
export function useExistingScrapForJobCard(jobCardId) {
    return useQuery({
        queryKey: ['existing_scrap', jobCardId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('scrap_inventory')
                .select('id, source_issue_part_id, status')
                .eq('source_job_card_id', jobCardId)
            if (error) throw error

            // Build map: one row per part, permanent over anything else, and
            // reversed only when there is nothing better. A partial refurbishment
            // (MAIN-123) leaves one part with a refurbished row and an in-storage
            // row, and close_job_card_with_scrap treats that part as permanent.
            // source_issue_part_id may be NULL when the issue_parts row was
            // deleted after scrap reversal — skip those rows, they can't be
            // keyed to an active part.
            const rank = row =>
                PERMANENT_SCRAP_STATUSES.includes(row.status) ? 2 : row.status === 'reversed' ? 0 : 1
            const map = {}
            for (const row of data || []) {
                if (!row.source_issue_part_id) continue
                const existing = map[row.source_issue_part_id]
                if (!existing || rank(row) > rank(existing)) {
                    map[row.source_issue_part_id] = row
                }
            }
            return map
        },
        enabled: !!jobCardId,
    })
}

// ── Phase 2: scrap outflow hooks ──────────────────────────────────────────────

function throwIfRpcError(error) {
    try {
        const parsed = JSON.parse(error.message)
        if (parsed.error_code) throw new ScrapRPCError(parsed)
    } catch (parseErr) {
        if (parseErr instanceof ScrapRPCError) throw parseErr
    }
    throw error
}

const AUDIT_SOURCE_EMBED = `
    audit_line:stock_audit_item_reasons!source_audit_reason_id(
        audit_item:stock_audit_items!audit_item_id(audit:stock_audits!audit_id(audit_number))
    )
`

/** Where a scrap row came from, as shown in a list: its job card or its stock audit. */
export function scrapSourceLabel(item) {
    const audit = item?.audit_line?.audit_item?.audit
    return item?.job_card?.job_card_number || (audit ? auditRef(audit) : '—')
}

export function useScrapInventory(filters = {}) {
    return useQuery({
        queryKey: ['scrap_inventory', filters],
        // Keep the current rows visible while a new search term loads — see useSuppliers.
        placeholderData: keepPreviousData,
        queryFn: async () => {
            let query = supabase
                .from('scrap_inventory')
                .select(`
                    id,
                    part_name_snapshot,
                    part_number_snapshot,
                    quantity_snapshot,
                    unit_snapshot,
                    source_vehicle_number,
                    source_job_card_id,
                    status,
                    created_at,
                    location_id,
                    location:workshop_locations!location_id(id, name),
                    job_card:job_cards!source_job_card_id(job_card_number),
                    ${AUDIT_SOURCE_EMBED}
                `)
                .order('created_at', { ascending: false })

            if (filters.status) {
                query = query.eq('status', filters.status)
            }
            if (filters.location_id) {
                query = query.eq('location_id', filters.location_id)
            }
            if (filters.search) {
                query = query.ilike('part_name_snapshot', `%${filters.search}%`)
            }
            if (filters.vehicle) {
                query = query.eq('source_vehicle_number', filters.vehicle)
            }
            if (filters.dateFrom) {
                query = query.gte('created_at', filters.dateFrom)
            }
            if (filters.dateTo) {
                query = query.lte('created_at', filters.dateTo + 'T23:59:59')
            }

            const { data, error } = await query
            if (error) throw error
            return data || []
        },
    })
}

export function useScrapDisposals(filters = {}) {
    return useQuery({
        queryKey: ['scrap_disposals', filters],
        placeholderData: keepPreviousData,
        queryFn: async () => {
            let query = supabase
                .from('scrap_disposal')
                .select(`
                    id,
                    disposal_date,
                    buyer_name,
                    buyer_contact,
                    payment_mode,
                    payment_reference,
                    total_value,
                    receipt_photos,
                    notes,
                    recorded_at,
                    recorded_by_user:users!recorded_by(name),
                    scrap_disposal_items(id)
                `)
                .order('disposal_date', { ascending: false })
                .order('recorded_at', { ascending: false })

            if (filters.search) {
                query = query.or(`buyer_name.ilike.%${filters.search}%,notes.ilike.%${filters.search}%`)
            }
            if (filters.dateFrom) {
                query = query.gte('disposal_date', filters.dateFrom)
            }
            if (filters.dateTo) {
                query = query.lte('disposal_date', filters.dateTo)
            }

            const { data, error } = await query
            if (error) throw error
            return (data || []).map(d => ({
                ...d,
                item_count: d.scrap_disposal_items?.length ?? 0,
            }))
        },
    })
}

export function useScrapDisposalItems(disposalId) {
    return useQuery({
        queryKey: ['scrap_disposal_items', disposalId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('scrap_disposal_items')
                .select('id, scrap_inventory_id, value_allocated, part_name_snapshot, quantity_snapshot, unit_snapshot')
                .eq('disposal_id', disposalId)
                .order('created_at')
            if (error) throw error
            return data || []
        },
        enabled: !!disposalId,
    })
}

export function useScrapWriteoffs(filters = {}) {
    return useQuery({
        queryKey: ['scrap_writeoffs', filters],
        placeholderData: keepPreviousData,
        queryFn: async () => {
            let query = supabase
                .from('scrap_writeoff')
                .select(`
                    id,
                    writeoff_date,
                    reason,
                    description,
                    evidence_photos,
                    notes,
                    recorded_at,
                    recorded_by_user:users!recorded_by(name),
                    scrap_writeoff_items(id)
                `)
                .order('writeoff_date', { ascending: false })
                .order('recorded_at', { ascending: false })

            if (filters.search) {
                query = query.or(`description.ilike.%${filters.search}%,notes.ilike.%${filters.search}%`)
            }
            if (filters.dateFrom) {
                query = query.gte('writeoff_date', filters.dateFrom)
            }
            if (filters.dateTo) {
                query = query.lte('writeoff_date', filters.dateTo)
            }

            const { data, error } = await query
            if (error) throw error
            return (data || []).map(w => ({
                ...w,
                item_count: w.scrap_writeoff_items?.length ?? 0,
            }))
        },
    })
}

export function useScrapWriteoffItems(writeoffId) {
    return useQuery({
        queryKey: ['scrap_writeoff_items', writeoffId],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('scrap_writeoff_items')
                .select('id, scrap_inventory_id, part_name_snapshot, quantity_snapshot, unit_snapshot')
                .eq('writeoff_id', writeoffId)
                .order('created_at')
            if (error) throw error
            return data || []
        },
        enabled: !!writeoffId,
    })
}

export function useRecordScrapDisposal() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ header, items }) => {
            const { data, error } = await supabase.rpc('record_scrap_disposal', {
                p_header: header,
                p_items:  items,
            })
            if (error) throwIfRpcError(error)
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['scrap_inventory'] })
            queryClient.invalidateQueries({ queryKey: ['scrap_disposals'] })
        },
    })
}

export function useRecordScrapWriteoff() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ header, items }) => {
            const { data, error } = await supabase.rpc('record_scrap_writeoff', {
                p_header: header,
                p_items:  items,
            })
            if (error) throwIfRpcError(error)
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['scrap_inventory'] })
            queryClient.invalidateQueries({ queryKey: ['scrap_writeoffs'] })
        },
    })
}

// ── MAIN-123: refurbishment ───────────────────────────────────────────────────

export function useRefurbishments(filters = {}) {
    return useQuery({
        queryKey: ['scrap_refurbishments', filters],
        placeholderData: keepPreviousData,
        queryFn: async () => {
            let query = supabase
                .from('scrap_refurbishments')
                .select(`
                    id,
                    quantity,
                    comment,
                    created_at,
                    scrap_inventory_id,
                    original:parts!original_part_id(name, part_number, unit),
                    refurbished:parts!refurbished_part_id(name),
                    created_by_user:users!created_by(name),
                    line:purchase_invoice_items!purchase_invoice_item_id(
                        line_total,
                        invoice:purchase_invoices!invoice_id(
                            invoice_number, supplier_name, invoice_date, invoice_file_url,
                            location:workshop_locations!location_id(name)
                        )
                    ),
                    scrap:scrap_inventory!scrap_inventory_id(
                        job_card:job_cards!source_job_card_id(job_card_number),
                        ${AUDIT_SOURCE_EMBED}
                    )
                `)
                .order('created_at', { ascending: false })

            if (filters.dateFrom) {
                query = query.gte('created_at', filters.dateFrom)
            }
            if (filters.dateTo) {
                query = query.lte('created_at', filters.dateTo + 'T23:59:59')
            }

            const { data, error } = await query
            if (error) throw error
            return data || []
        },
    })
}

export function useRecordRefurbishment() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ invoice, lines }) => {
            const { data, error } = await supabase.rpc('record_refurbishment', {
                p_invoice: invoice,
                p_lines:   lines,
            })
            if (error) throwIfRpcError(error)
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['scrap_inventory'] })
            queryClient.invalidateQueries({ queryKey: ['scrap_refurbishments'] })
            queryClient.invalidateQueries({ queryKey: ['existing_scrap'] })
            queryClient.invalidateQueries({ queryKey: ['parts'] })
            queryClient.invalidateQueries({ queryKey: ['part_stock'] })
            queryClient.invalidateQueries({ queryKey: ['purchase_invoices'] })
            // The invoice goes straight to finance.
            queryClient.invalidateQueries({ queryKey: ['outsource_invoices'] })
            queryClient.invalidateQueries({ queryKey: ['outsource_invoice_summary'] })
            queryClient.invalidateQueries({ queryKey: ['supplier_ledger'] })
        },
    })
}
