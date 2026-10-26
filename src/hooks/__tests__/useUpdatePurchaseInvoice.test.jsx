/**
 * Regression tests for MAIN-72 and MAIN-97.
 *
 * MAIN-72: useUpdatePurchaseInvoice built the invoice header update from an
 * explicit column list that omitted `location_id`. The Edit Purchase modal held
 * the field and passed it in, but the hook never wrote it, so the workshop
 * silently never changed and the DB trigger that moves the stock never fired.
 *
 * MAIN-97: the save was five separate PostgREST calls, so a stock check failing
 * on a later line left the earlier changes committed. Both hooks now make one
 * call to save_purchase_invoice, which does everything in a single transaction.
 * The header-before-lines ordering MAIN-72 depended on now lives inside that
 * function, and is covered by the database-level checks run against staging.
 *
 * These tests assert the payload the hooks actually send, which is the half a
 * database-level test cannot reach.
 */
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

// Every supabase call the hooks make.
let rpcCalls = []
let tableCalls = []
let rpcResult = { data: null, error: null }

vi.mock('../../lib/supabase', () => ({
    supabase: {
        rpc: (fn, args) => {
            rpcCalls.push({ fn, args })
            return Promise.resolve(rpcResult)
        },
        from: (table) => {
            tableCalls.push(table)
            throw new Error(`unexpected direct write to ${table}`)
        },
    },
}))

import { useUpdatePurchaseInvoice, useRecordPurchase } from '../useInventory'

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
}

async function runUpdate(args = baseArgs) {
    const { result } = renderHook(() => useUpdatePurchaseInvoice(), { wrapper })
    return result.current.mutateAsync(args)
}

const saveCall = () => rpcCalls.find(c => c.fn === 'save_purchase_invoice')

beforeEach(() => {
    rpcCalls = []
    tableCalls = []
    rpcResult = { data: null, error: null }
})

describe('useUpdatePurchaseInvoice — MAIN-72', () => {
    it('includes location_id in the invoice header', async () => {
        await runUpdate()

        expect(saveCall()).toBeTruthy()
        expect(saveCall().args.p_invoice).toHaveProperty('location_id', LOCATION_ID)
    })

    it('still sends the other header fields alongside it', async () => {
        await runUpdate()

        expect(saveCall().args.p_invoice).toMatchObject({
            invoice_number: 'INV-001',
            supplier_name: 'AutoParts Ltd',
            invoice_date: '2026-09-01',
        })
    })

    it('passes location_id through unchanged when the workshop is not being moved', async () => {
        // The DB trigger no-ops on an unchanged value, so writing it every time is
        // safe — but it must still be written, not dropped.
        await runUpdate()
        expect(saveCall().args.p_invoice.location_id).toBe(LOCATION_ID)
    })
})

describe('useUpdatePurchaseInvoice — MAIN-97', () => {
    it('saves the header and every line in a single call, with no direct table writes', async () => {
        await runUpdate({
            ...baseArgs,
            lineItems: [
                { id: 'line-1', part_id: 'part-1', quantity: '5', unit_price: '10', gst_rate: 0, discount_amount: '' },
                { id: null, part_id: 'part-2', quantity: '1', unit_price: '20', gst_rate: 0, discount_amount: '' },
            ],
        })

        expect(rpcCalls).toHaveLength(1)
        expect(tableCalls).toHaveLength(0)
        expect(saveCall().args.p_invoice_id).toBe(INVOICE_ID)
        expect(saveCall().args.p_items).toHaveLength(2)
    })

    it('keeps the id on existing lines, omits it on new ones, and parses the numbers', async () => {
        await runUpdate({
            ...baseArgs,
            lineItems: [
                { id: 'line-1', part_id: 'part-1', quantity: '5', unit_price: '10.50', gst_rate: '18', discount_amount: '' },
                { id: null, part_id: 'part-2', quantity: '1', unit_price: '20', gst_rate: '', discount_amount: '2' },
            ],
        })

        const [kept, added] = saveCall().args.p_items
        expect(kept).toEqual({ id: 'line-1', part_id: 'part-1', quantity: 5, unit_price: 10.5, gst_rate: 18, discount_amount: 0 })
        expect(added).toEqual({ part_id: 'part-2', quantity: 1, unit_price: 20, gst_rate: 0, discount_amount: 2 })
    })

    it('surfaces the database error so the modal can show it', async () => {
        rpcResult = { data: null, error: new Error('Not enough stock: New Tyre has 2.00 available, needed 5.00.') }

        await expect(runUpdate()).rejects.toThrow('Not enough stock')
    })
})

describe('useRecordPurchase — MAIN-97', () => {
    it('creates the invoice and its lines in a single call, with no invoice id', async () => {
        rpcResult = { data: 'new-inv', error: null }
        const { result } = renderHook(() => useRecordPurchase(), { wrapper })

        const created = await result.current.mutateAsync({
            invoice: { invoice_number: 'INV-002', supplier_name: 'AutoParts Ltd', invoice_date: '2026-09-02', notes: '', location_id: LOCATION_ID },
            lineItems: [{ part_id: 'part-1', quantity: 3, unit_price: 10, gst_rate: 0, discount_amount: 0 }],
        })

        expect(rpcCalls).toHaveLength(1)
        expect(tableCalls).toHaveLength(0)
        expect(saveCall().args.p_invoice_id).toBeNull()
        expect(saveCall().args.p_invoice).toMatchObject({ invoice_number: 'INV-002', location_id: LOCATION_ID })
        expect(saveCall().args.p_items[0]).not.toHaveProperty('id')
        expect(created).toEqual({ id: 'new-inv' })
    })
})
