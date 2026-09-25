/**
 * Regression tests for MAIN-72.
 *
 * The bug: useUpdatePurchaseInvoice built the invoice header update from an
 * explicit column list that omitted `location_id`. The Edit Purchase modal held
 * the field and passed it in, but the hook never wrote it, so the workshop
 * silently never changed and the DB trigger that moves the stock never fired.
 *
 * These tests assert the payload the hook actually sends, which is the half a
 * database-level test cannot reach.
 */
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

// Every supabase call the hook makes, in order.
let calls = []

vi.mock('../../lib/supabase', () => {
    const makeQuery = (table) => {
        const q = {
            update: (payload) => { calls.push({ table, op: 'update', payload }); return q },
            insert: (payload) => { calls.push({ table, op: 'insert', payload }); return q },
            delete: () => { calls.push({ table, op: 'delete' }); return q },
            eq: () => q,
            in: () => q,
            select: () => q,
            single: () => q,
            // Thenable so `await supabase.from(…).update(…).eq(…)` resolves.
            then: (resolve) => resolve({ data: null, error: null }),
        }
        return q
    }
    return { supabase: { from: (table) => makeQuery(table) } }
})

import { useUpdatePurchaseInvoice } from '../useInventory'

function wrapper({ children }) {
    const client = new QueryClient({ defaultOptions: { mutations: { retry: false } } })
    return <QueryClientProvider client={client}>{children}</QueryClientProvider>
}

const INVOICE_ID = 'inv-1'
const LOCATION_ID = 'a1e1d4c0-0000-4000-8000-000000000002'

const baseArgs = {
    invoiceId: INVOICE_ID,
    invoiceData: {
        invoice_number: 'INV-001',
        supplier_name: 'AutoParts Ltd',
        invoice_date: '2026-09-01',
        notes: '',
        location_id: LOCATION_ID,
    },
    lineItems: [{ id: 'line-1', part_id: 'part-1', quantity: '2', unit_price: '10', gst_rate: 0, discount_amount: '' }],
    originalItems: [{ id: 'line-1' }],
}

async function runMutation(args = baseArgs) {
    const { result } = renderHook(() => useUpdatePurchaseInvoice(), { wrapper })
    await result.current.mutateAsync(args)
    await waitFor(() => expect(calls.length).toBeGreaterThan(0))
}

// The header update is the first purchase_invoices write; a later one only
// persists the recalculated total_amount.
const headerUpdate = () =>
    calls.find(c => c.table === 'purchase_invoices' && c.op === 'update')

describe('useUpdatePurchaseInvoice — MAIN-72', () => {
    beforeEach(() => { calls = [] })

    it('includes location_id in the invoice header update', async () => {
        await runMutation()

        expect(headerUpdate()).toBeTruthy()
        expect(headerUpdate().payload).toHaveProperty('location_id', LOCATION_ID)
    })

    it('still sends the other header fields alongside it', async () => {
        await runMutation()

        expect(headerUpdate().payload).toMatchObject({
            invoice_number: 'INV-001',
            supplier_name: 'AutoParts Ltd',
            invoice_date: '2026-09-01',
        })
    })

    it('writes the header before touching any line item', async () => {
        // Ordering matters: the move-stock trigger must fire — and be allowed to
        // refuse — before a line-item change has been written, so a refused move
        // leaves nothing half-saved.
        await runMutation({
            ...baseArgs,
            lineItems: [
                { id: 'line-1', part_id: 'part-1', quantity: '5', unit_price: '10', gst_rate: 0, discount_amount: '' },
                { id: null, part_id: 'part-2', quantity: '1', unit_price: '20', gst_rate: 0, discount_amount: '' },
            ],
            originalItems: [{ id: 'line-1' }, { id: 'line-removed' }],
        })

        const headerIndex = calls.findIndex(c => c.table === 'purchase_invoices' && c.op === 'update')
        const firstLineItemIndex = calls.findIndex(c => c.table === 'purchase_invoice_items')

        expect(headerIndex).toBeGreaterThanOrEqual(0)
        expect(firstLineItemIndex).toBeGreaterThanOrEqual(0)
        expect(headerIndex).toBeLessThan(firstLineItemIndex)
    })

    it('passes location_id through unchanged when the workshop is not being moved', async () => {
        // The DB trigger no-ops on an unchanged value, so writing it every time is
        // safe — but it must still be written, not dropped.
        await runMutation()
        expect(headerUpdate().payload.location_id).toBe(LOCATION_ID)
    })
})
