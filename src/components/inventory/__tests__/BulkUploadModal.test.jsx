/**
 * Regression tests for MAIN-73.
 *
 * The bug: BulkUploadModal had no workshop field and left `location_id` off its
 * invoice header insert, so every bulk-uploaded invoice silently took the column
 * default (Bannerghatta) and credited its stock there.
 *
 * These cover the UI half — that the selector exists, that it gates the upload,
 * and that the chosen workshop actually reaches the insert payload.
 */
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

const BANNERGHATTA = { id: 'loc-blr', name: 'Bannerghatta', address: null, is_active: true }
const MAHADEVPURA = { id: 'loc-mhd', name: 'Mahadevpura', address: null, is_active: true }

// Swapped per test — the single-workshop auto-select branch needs a different list.
let mockLocations = [BANNERGHATTA, MAHADEVPURA]
let calls = []

vi.mock('../../../hooks/useWorkshopLocations', () => ({
    useWorkshopLocations: () => ({ data: mockLocations }),
}))

vi.mock('../../../hooks/useAuth', () => ({
    useAuth: () => ({ userProfile: { id: 'user-1' } }),
}))

vi.mock('../../../hooks/useInventory', () => ({
    useParts: () => ({ data: [{ id: 'part-1', name: 'Engine Oil 5W40', part_number: 'OIL-5W40', unit: 'L' }] }),
    useRecordPurchase: () => ({}),
}))

vi.mock('@tanstack/react-query', () => ({
    useQueryClient: () => ({ invalidateQueries: vi.fn() }),
}))

vi.mock('../../../lib/supabase', () => {
    const makeQuery = (table) => {
        const q = {
            insert: (payload) => { calls.push({ table, op: 'insert', payload }); return q },
            select: () => q,
            single: () => q,
            then: (resolve) => resolve({ data: { id: `${table}-row-1` }, error: null }),
        }
        return q
    }
    return { supabase: { from: (table) => makeQuery(table) } }
})

// One invoice, one line, matching the part above so no part creation is needed.
const HEADER = ['invoice_number', 'invoice_date', 'supplier_name', 'part_number',
    'part_name', 'unit', 'quantity', 'unit_price', 'gst_rate', 'discount_amount', 'notes']
const ROW = ['INV-001', '2026-01-15', 'AutoParts Ltd', 'OIL-5W40', 'Engine Oil 5W40', 'L', 20, 85, 18, 0, '']

vi.mock('xlsx', () => ({
    read: () => ({ SheetNames: ['Sheet1'], Sheets: { Sheet1: {} } }),
    utils: {
        sheet_to_json: () => [HEADER, ROW],
        book_new: () => ({}),
        aoa_to_sheet: () => ({}),
        book_append_sheet: () => {},
    },
    writeFile: () => {},
    SSF: { parse_date_code: () => ({ y: 2026, m: 1, d: 15 }) },
}))

import BulkUploadModal from '../BulkUploadModal'

const fileInput = (container) => container.querySelector('input[type="file"]')
const makeFile = () => new File(['x'], 'upload.xlsx', {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
})

async function chooseWorkshop(user, name) {
    await user.click(screen.getAllByText('Select workshop')[0])
    await user.click(await screen.findByText(name))
}

describe('BulkUploadModal — MAIN-73', () => {
    beforeEach(() => {
        calls = []
        mockLocations = [BANNERGHATTA, MAHADEVPURA]
    })

    it('asks which workshop the batch is inwarded to', () => {
        render(<BulkUploadModal onClose={() => {}} />)
        expect(screen.getByText(/Inward to Workshop/i)).toBeInTheDocument()
    })

    it('gates the drop zone until a workshop is chosen', async () => {
        const user = userEvent.setup()
        render(<BulkUploadModal onClose={() => {}} />)

        expect(screen.getByText('Choose a workshop above to start')).toBeInTheDocument()

        await chooseWorkshop(user, 'Mahadevpura')

        expect(screen.getByText('Drop your file here or click to browse')).toBeInTheDocument()
    })

    it('refuses to parse a file while no workshop is chosen', async () => {
        const user = userEvent.setup()
        const { container } = render(<BulkUploadModal onClose={() => {}} />)

        await user.upload(fileInput(container), makeFile())

        expect(await screen.findByText(/Choose which workshop this batch is being inwarded to first/i))
            .toBeInTheDocument()
    })

    it('auto-selects when there is exactly one workshop', () => {
        // Staging has two workshops, so this branch cannot be exercised there.
        mockLocations = [BANNERGHATTA]
        render(<BulkUploadModal onClose={() => {}} />)

        expect(screen.getByText('Bannerghatta')).toBeInTheDocument()
        expect(screen.getByText('Drop your file here or click to browse')).toBeInTheDocument()
    })

    it('sends the chosen workshop as location_id on the invoice insert', async () => {
        const user = userEvent.setup()
        const { container } = render(<BulkUploadModal onClose={() => {}} />)

        await chooseWorkshop(user, 'Mahadevpura')
        await user.upload(fileInput(container), makeFile())

        // Preview step, then import.
        await user.click(await screen.findByRole('button', { name: /Import 1 rows/i }))

        await waitFor(() => {
            const inv = calls.find(c => c.table === 'purchase_invoices' && c.op === 'insert')
            expect(inv).toBeTruthy()
            expect(inv.payload[0]).toHaveProperty('location_id', MAHADEVPURA.id)
        })
    })

    it('keeps the workshop visible and changeable on the preview step', async () => {
        const user = userEvent.setup()
        const { container } = render(<BulkUploadModal onClose={() => {}} />)

        await chooseWorkshop(user, 'Mahadevpura')
        await user.upload(fileInput(container), makeFile())

        expect(await screen.findByText(/Every invoice below is received into this workshop/i))
            .toBeInTheDocument()
    })
})
