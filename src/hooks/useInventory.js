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
                .select('id, part_id, quantity, unit_price, gst_rate, line_total, part:parts(id, name, part_number, unit)')
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
                    })))
                if (error) throw error
            }

            // 5. Recalculate and persist total_amount
            const newTotal = [...toUpdate, ...toInsert].reduce(
                (sum, i) => sum + parseFloat(i.quantity) * parseFloat(i.unit_price),
                0
            )
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
                quantity_used: row.quantity_used,
                added_at: row.added_at,
                part_name: row.part?.name,
                part_number: row.part?.part_number,
                unit: row.part?.unit,
                job_card_id: row.issue?.job_card?.id,
                job_card_number: row.issue?.job_card?.job_card_number,
                vehicle_number: row.issue?.job_card?.vehicle_number,
                job_card_status: row.issue?.job_card?.status,
                mechanic_id: row.issue?.job_card?.mechanic?.id,
                mechanic_name: row.issue?.job_card?.mechanic?.name,
            }))

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

            return rows
        },
    })
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
