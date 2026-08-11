import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * All parts with stock levels, ordered by name.
 */
export function useParts(filters = {}) {
    return useQuery({
        queryKey: ['parts', filters],
        queryFn: async () => {
            let query = supabase
                .from('parts')
                .select('id, name, part_number, unit, quantity_in_stock')
                .order('name')

            if (filters.search) {
                query = query.or(
                    `name.ilike.%${filters.search}%,part_number.ilike.%${filters.search}%`
                )
            }
            if (filters.stockStatus === 'low') {
                query = query.lte('quantity_in_stock', 5)
            } else if (filters.stockStatus === 'out') {
                query = query.lte('quantity_in_stock', 0)
            }

            const { data, error } = await query
            if (error) throw error
            return data || []
        },
    })
}

/**
 * All purchase invoices with item counts and created_by name.
 */
export function usePurchaseInvoices(filters = {}) {
    return useQuery({
        queryKey: ['purchase_invoices', filters],
        queryFn: async () => {
            let query = supabase
                .from('purchase_invoices')
                .select(`
                    id,
                    invoice_number,
                    supplier_name,
                    invoice_date,
                    total_amount,
                    notes,
                    invoice_file_url,
                    created_at,
                    location_id,
                    location:workshop_locations!location_id(id, name, address),
                    created_by_user:users!created_by(name),
                    purchase_invoice_items(id)
                `)
                .order('invoice_date', { ascending: false })
                .order('created_at', { ascending: false })

            if (filters.search) {
                query = query.or(
                    `invoice_number.ilike.%${filters.search}%,supplier_name.ilike.%${filters.search}%`
                )
            }
            if (filters.dateFrom) {
                query = query.gte('invoice_date', filters.dateFrom)
            }
            if (filters.dateTo) {
                query = query.lte('invoice_date', filters.dateTo)
            }

            const { data, error } = await query
            if (error) throw error
            return (data || []).map(inv => ({
                ...inv,
                item_count: inv.purchase_invoice_items?.length ?? 0,
            }))
        },
    })
}

/**
 * Line items for a single invoice (used in the history detail expand and edit modal).
 */
export function usePurchaseInvoiceItems(invoiceId) {
    return useQuery({
        queryKey: ['purchase_invoice_items', invoiceId],
        enabled: !!invoiceId,
        queryFn: async () => {
            const { data, error } = await supabase
                .from('purchase_invoice_items')
                .select('id, part_id, quantity, unit_price, gst_rate, discount_amount, line_total, part:parts(id, name, part_number, unit)')
                .eq('invoice_id', invoiceId)
            if (error) throw error
            return data || []
        },
    })
}

/**
 * Update a purchase invoice header and its line items, adjusting inventory accordingly.
 * - Existing items that were removed are deleted (trigger reverses stock).
 * - Existing items that were kept are updated (trigger adjusts stock delta).
 * - New items are inserted (trigger adds stock).
 */
export function useUpdatePurchaseInvoice() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ invoiceId, invoiceData, lineItems, originalItems }) => {
            // 1. Update invoice header fields
            const { error: invErr } = await supabase
                .from('purchase_invoices')
                .update({
                    invoice_number: invoiceData.invoice_number,
                    supplier_name: invoiceData.supplier_name,
                    invoice_date: invoiceData.invoice_date,
                    notes: invoiceData.notes || null,
                    invoice_file_url: invoiceData.invoice_file_url || null,
                })
                .eq('id', invoiceId)
            if (invErr) throw invErr

            // Categorise line items
            const originalIds = new Set(originalItems.map(i => i.id))
            const keptIds = new Set(lineItems.filter(l => l.id).map(l => l.id))
            const toDelete = [...originalIds].filter(id => !keptIds.has(id))
            const toUpdate = lineItems.filter(l => l.id)
            const toInsert = lineItems.filter(l => !l.id)

            // 2. Delete removed items — trigger reverses stock
            if (toDelete.length > 0) {
                const { error } = await supabase
                    .from('purchase_invoice_items')
                    .delete()
                    .in('id', toDelete)
                if (error) throw error
            }

            // 3. Update existing items — trigger adjusts stock delta
            for (const item of toUpdate) {
                const { error } = await supabase
                    .from('purchase_invoice_items')
                    .update({
                        quantity: parseFloat(item.quantity),
                        unit_price: parseFloat(item.unit_price),
                        gst_rate: parseFloat(item.gst_rate) || 0,
                        discount_amount: parseFloat(item.discount_amount) || 0,
                    })
                    .eq('id', item.id)
                if (error) throw error
            }

            // 4. Insert new items — trigger adds stock
            if (toInsert.length > 0) {
                const { error } = await supabase
                    .from('purchase_invoice_items')
                    .insert(toInsert.map(item => ({
                        invoice_id: invoiceId,
                        part_id: item.part_id,
                        quantity: parseFloat(item.quantity),
                        unit_price: parseFloat(item.unit_price),
                        gst_rate: parseFloat(item.gst_rate) || 0,
                        discount_amount: parseFloat(item.discount_amount) || 0,
                    })))
                if (error) throw error
            }

            // 5. Recalculate and persist total_amount as the sum of line totals
            //    (GST- and discount-inclusive), matching the DB generated line_total.
            //    Also fixes MAIN-25: the old recompute dropped GST from the total.
            const newTotal = [...toUpdate, ...toInsert].reduce((sum, i) => {
                const qty = parseFloat(i.quantity) || 0
                const price = parseFloat(i.unit_price) || 0
                const gst = parseFloat(i.gst_rate) || 0
                const discount = parseFloat(i.discount_amount) || 0
                const lineTotal = Math.round((qty * price - discount) * (1 + gst / 100) * 100) / 100
                return sum + lineTotal
            }, 0)
            const { error: totalErr } = await supabase
                .from('purchase_invoices')
                .update({ total_amount: newTotal })
                .eq('id', invoiceId)
            if (totalErr) throw totalErr
        },
        onSuccess: (_data, { invoiceId }) => {
            queryClient.invalidateQueries({ queryKey: ['parts'] })
            queryClient.invalidateQueries({ queryKey: ['purchase_invoices'] })
            queryClient.invalidateQueries({ queryKey: ['purchase_invoice_items', invoiceId] })
        },
    })
}

/**
 * Record a purchase: insert invoice + all line items in sequence.
 * The DB trigger on purchase_invoice_items will restock parts automatically.
 */
export function useRecordPurchase() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ invoice, lineItems }) => {
            // Insert invoice header
            const { data: inv, error: invErr } = await supabase
                .from('purchase_invoices')
                .insert([invoice])
                .select()
                .single()
            if (invErr) throw invErr

            // Insert all line items
            const items = lineItems.map(item => ({
                invoice_id: inv.id,
                part_id: item.part_id,
                quantity: item.quantity,
                unit_price: item.unit_price,
                gst_rate: item.gst_rate ?? 0,
                discount_amount: item.discount_amount ?? 0,
            }))

            const { error: itemsErr } = await supabase
                .from('purchase_invoice_items')
                .insert(items)
            if (itemsErr) throw itemsErr

            return inv
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['parts'] })
            queryClient.invalidateQueries({ queryKey: ['purchase_invoices'] })
        },
    })
}

/**
 * Update an existing part's name, part_number, and unit.
 */
export function useUpdatePart() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ id, name, part_number, unit }) => {
            const { data, error } = await supabase
                .from('parts')
                .update({ name, part_number, unit })
                .eq('id', id)
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['parts'] })
        },
    })
}

/**
 * Part consumption history: issue_parts joined with part, issue, job card, mechanic.
 */
export function usePartConsumption(filters = {}) {
    return useQuery({
        queryKey: ['part_consumption', filters],
        queryFn: async () => {
            let query = supabase
                .from('issue_parts')
                .select(`
                    id,
                    quantity_used,
                    added_at,
                    part:parts(id, name, part_number, unit),
                    issue:issues(
                        id,
                        job_card:job_cards(
                            id,
                            job_card_number,
                            vehicle_number,
                            status,
                            location:workshop_locations!location_id(id, name),
                            mechanic:users!job_cards_assigned_mechanic_id_fkey(id, name)
                        )
                    )
                `)
                .order('added_at', { ascending: false })

            if (filters.dateFrom) {
                query = query.gte('added_at', filters.dateFrom)
            }
            if (filters.dateTo) {
                // Include the full day
                query = query.lte('added_at', filters.dateTo + 'T23:59:59')
            }

            const { data, error } = await query
            if (error) throw error

            let rows = (data || []).map(row => ({
                id: row.id,
                source: 'job_card',
                quantity_used: row.quantity_used,
                added_at: row.added_at,
                part_name: row.part?.name,
                part_number: row.part?.part_number,
                unit: row.part?.unit,
                job_card_id: row.issue?.job_card?.id,
                job_card_number: row.issue?.job_card?.job_card_number,
                vehicle_number: row.issue?.job_card?.vehicle_number,
                job_card_status: row.issue?.job_card?.status,
                location_id: row.issue?.job_card?.location?.id,
                location_name: row.issue?.job_card?.location?.name,
                mechanic_id: row.issue?.job_card?.mechanic?.id,
                mechanic_name: row.issue?.job_card?.mechanic?.name,
            }))

            // Stock audits remove (or return) stock without a job card, so they belong in
            // this history too — otherwise a part's quantity drops with nothing here to
            // explain it. They carry source: 'audit' so per-mechanic and per-vehicle
            // reporting can filter them back out.
            const auditRows = await fetchAuditConsumption(filters)
            rows = [...rows, ...auditRows]

            if (filters.source) {
                rows = rows.filter(r => r.source === filters.source)
            }

            // Client-side filters
            if (filters.search) {
                const term = filters.search.toLowerCase()
                rows = rows.filter(r =>
                    r.part_name?.toLowerCase().includes(term) ||
                    r.part_number?.toLowerCase().includes(term) ||
                    r.vehicle_number?.toLowerCase().includes(term) ||
                    r.mechanic_name?.toLowerCase().includes(term)
                )
            }

            return rows.sort((a, b) => String(b.added_at ?? '').localeCompare(String(a.added_at ?? '')))
        },
    })
}

/**
 * Completed stock-audit differences, shaped like consumption rows.
 *
 * quantity_used is the negated variance: a shortfall of -3 reads as 3 units gone, and a
 * surplus of +5 reads as -5 — stock that came back. Matched parts are skipped entirely.
 */
async function fetchAuditConsumption(filters = {}) {
    let query = supabase
        .from('stock_audit_items')
        .select(`
            id, part_id, part_name_snapshot, part_number_snapshot, unit_snapshot,
            variance, reason, reason_notes,
            audit:stock_audits!audit_id(
                id, audit_number, status, completed_at, completed_by_name,
                location:workshop_locations!location_id(id, name)
            )
        `)
        .neq('variance', 0)

    const { data, error } = await query
    if (error) throw error

    const from = filters.dateFrom ? filters.dateFrom : null
    const to = filters.dateTo ? filters.dateTo + 'T23:59:59' : null

    return (data || [])
        .filter(row => row.audit?.status === 'completed' && row.audit?.completed_at)
        .filter(row => {
            const at = row.audit.completed_at
            if (from && at < from) return false
            if (to && at > to) return false
            return true
        })
        .map(row => ({
            id: `audit:${row.id}`,
            source: 'audit',
            quantity_used: -Number(row.variance ?? 0),
            added_at: row.audit.completed_at,
            part_name: row.part_name_snapshot,
            part_number: row.part_number_snapshot,
            unit: row.unit_snapshot,
            job_card_id: null,
            job_card_number: null,
            vehicle_number: null,
            job_card_status: null,
            location_id: row.audit.location?.id,
            location_name: row.audit.location?.name,
            mechanic_id: null,
            mechanic_name: null,
            audit_id: row.audit.id,
            audit_number: row.audit.audit_number,
            audit_reason: row.reason,
            audit_reason_notes: row.reason_notes,
        }))
}

/**
 * Full maintenance history for a specific vehicle number.
 */
export function useVehicleHistory(vehicleNumber) {
    return useQuery({
        queryKey: ['vehicle_history', vehicleNumber],
        enabled: !!vehicleNumber,
        queryFn: async () => {
            const { data, error } = await supabase
                .from('job_cards')
                .select(`
                    id,
                    job_card_number,
                    vehicle_number,
                    status,
                    type,
                    created_at,
                    completed_at,
                    mechanic:assigned_mechanic_id(id, name),
                    issues(id, description, status, labour_hours)
                `)
                .eq('vehicle_number', vehicleNumber)
                .order('created_at', { ascending: false })
            if (error) throw error
            return data || []
        },
    })
}

/**
 * Parts used on a specific job card (lazy-loaded when expanding a row).
 * Queries via issues to stay within existing RLS policies.
 */
export function useJobCardParts(jobCardId) {
    return useQuery({
        queryKey: ['job_card_parts', jobCardId],
        enabled: !!jobCardId,
        queryFn: async () => {
            // First get issue IDs for this job card
            const { data: issues, error: issueErr } = await supabase
                .from('issues')
                .select('id')
                .eq('job_card_id', jobCardId)
            if (issueErr) throw issueErr

            const issueIds = (issues || []).map(i => i.id)
            if (issueIds.length === 0) return []

            const { data, error } = await supabase
                .from('issue_parts')
                .select('id, quantity_used, part:parts(name, unit)')
                .in('issue_id', issueIds)
            if (error) throw error
            return data || []
        },
    })
}

/**
 * Profile + job card activity + labour hours for a specific mechanic.
 */
export function useMechanicProfile(mechanicId) {
    return useQuery({
        queryKey: ['mechanic_profile', mechanicId],
        enabled: !!mechanicId,
        queryFn: async () => {
            const { data, error } = await supabase
                .from('users')
                .select('id, name, role, site, created_at')
                .eq('id', mechanicId)
                .single()
            if (error) throw error
            return data
        },
    })
}

export function useMechanicActivity(mechanicId) {
    return useQuery({
        queryKey: ['mechanic_activity', mechanicId],
        enabled: !!mechanicId,
        queryFn: async () => {
            const { data, error } = await supabase
                .from('job_cards')
                .select(`
                    id,
                    job_card_number,
                    vehicle_number,
                    status,
                    type,
                    created_at,
                    completed_at,
                    issues(id, description, status, labour_hours)
                `)
                .eq('assigned_mechanic_id', mechanicId)
                .order('created_at', { ascending: false })
            if (error) throw error
            return data || []
        },
    })
}

/**
 * Create a new part (used during bulk upload when a part isn't in the catalog).
 */
export function useCreatePart() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async (partData) => {
            const { data, error } = await supabase
                .from('parts')
                .insert([partData])
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['parts'] })
        },
    })
}

// ─── Part Units ───────────────────────────────────────────────────────────────

export function usePartUnits() {
    return useQuery({
        queryKey: ['part_units'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('part_units')
                .select('id, name')
                .order('sort_order')
            if (error) throw error
            return data || []
        },
    })
}

export function useAddPartUnit() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async (name) => {
            const { data, error } = await supabase
                .from('part_units')
                .insert([{ name: name.trim() }])
                .select()
                .single()
            if (error) throw error
            return data
        },
        onSuccess: () => queryClient.invalidateQueries({ queryKey: ['part_units'] }),
    })
}

export function useDeletePartUnit() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async (id) => {
            const { error } = await supabase
                .from('part_units')
                .delete()
                .eq('id', id)
            if (error) throw error
        },
        onSuccess: () => queryClient.invalidateQueries({ queryKey: ['part_units'] }),
    })
}

// ─── Per-location stock ───────────────────────────────────────────────────────

/**
 * Parts with their stock at one workshop location.
 *
 * Deliberately a left join: every part is returned, with 0 where it has no stock at
 * this location. If we filtered to parts that have a part_stock row, a newly created
 * part would silently vanish from the list until its first purchase, which reads as
 * a bug rather than as "none here yet".
 */
export function usePartStock(locationId, filters = {}) {
    return useQuery({
        queryKey: ['part_stock', locationId, filters],
        enabled: !!locationId,
        queryFn: async () => {
            let query = supabase
                .from('parts')
                .select('id, name, part_number, unit, quantity_in_stock, part_stock(location_id, quantity)')
                .eq('part_stock.location_id', locationId)
                .order('name')

            if (filters.search) {
                query = query.or(
                    `name.ilike.%${filters.search}%,part_number.ilike.%${filters.search}%`
                )
            }

            const { data, error } = await query
            if (error) throw error

            const rows = (data || []).map(part => ({
                ...part,
                quantity_here: Number(part.part_stock?.[0]?.quantity ?? 0),
                quantity_total: Number(part.quantity_in_stock ?? 0),
            }))

            // Stock level filters apply to this location, not the company-wide total.
            if (filters.stockStatus === 'low') return rows.filter(r => r.quantity_here <= 5)
            if (filters.stockStatus === 'out') return rows.filter(r => r.quantity_here <= 0)
            return rows
        },
    })
}

/**
 * Headline numbers per location for the inventory landing cards.
 */
export function useLocationStockSummary() {
    return useQuery({
        queryKey: ['part_stock', 'summary'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('part_stock')
                .select('location_id, quantity')
            if (error) throw error

            return (data || []).reduce((acc, row) => {
                const qty = Number(row.quantity ?? 0)
                const bucket = acc[row.location_id] || { stocked: 0, low: 0, units: 0 }
                if (qty > 0) {
                    bucket.stocked += 1
                    bucket.units += qty
                    if (qty <= 5) bucket.low += 1
                }
                acc[row.location_id] = bucket
                return acc
            }, {})
        },
    })
}

/**
 * Move parts between workshops. All lines move together — if the source is short of
 * any one part the whole transfer is rejected and nothing moves.
 *
 * @param {object} args
 * @param {string} args.fromLocationId
 * @param {string} args.toLocationId
 * @param {Array<{part_id: string, quantity: number}>} args.items
 * @param {string} [args.notes]
 */
export function useTransferStock() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ fromLocationId, toLocationId, items, notes }) => {
            const { data, error } = await supabase.rpc('transfer_stock', {
                p_from: fromLocationId,
                p_to: toLocationId,
                p_items: items.map(i => ({ part_id: i.part_id, quantity: Number(i.quantity) })),
                p_notes: notes || null,
            })
            if (error) throw error
            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['part_stock'] })
            queryClient.invalidateQueries({ queryKey: ['parts'] })
            queryClient.invalidateQueries({ queryKey: ['stock_transfers'] })
        },
    })
}
