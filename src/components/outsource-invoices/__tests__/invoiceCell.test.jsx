/**
 * MAIN-141 — a supervisor sees their own sites' invoices but has no job card or
 * multi-vehicle invoice page, so the number is plain text for them.
 */
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'

vi.mock('../../../hooks/useOutsourceInvoices', () => ({
    useUpdateFinancePaymentStatus: () => ({ mutate: vi.fn(), reset: vi.fn(), isPending: false, error: null }),
}))

import InvoiceCell from '../InvoiceCell'
import { COLUMNS, DEFAULT_COLUMN_KEYS } from '../columns'

const jobCardInvoice = { id: 'inv-1', job_card: { job_card_number: 8863, vehicle_number: 'KA01AB1' } }
const batchInvoice = {
    id: 'inv-2',
    batch_service: { batch_number: 12, status: 'Active', vehicles: [{ vehicle_number: 'KA01AB1', work_type: 'Greasing' }] },
}

const renderCell = (invoice, canOpen) =>
    render(<MemoryRouter><InvoiceCell columnKey="job_card" invoice={invoice} canOpen={canOpen} /></MemoryRouter>)

describe('InvoiceCell job card column', () => {
    it('links to the job card by default', () => {
        renderCell(jobCardInvoice)
        expect(screen.getByRole('link', { name: '#8863' })).toHaveAttribute('href', '/job-cards/8863')
    })

    it('shows the job card number as text when the reader cannot open it', () => {
        renderCell(jobCardInvoice, false)
        expect(screen.getByText('#8863')).toBeInTheDocument()
        expect(screen.queryByRole('link')).not.toBeInTheDocument()
    })

    it('shows the multi-vehicle invoice number as text when the reader cannot open it', () => {
        renderCell(batchInvoice, false)
        expect(screen.getByText('MVI-12')).toBeInTheDocument()
        expect(screen.queryByRole('link')).not.toBeInTheDocument()
    })
})

describe('InvoiceCell type column (MAIN-142)', () => {
    it.each([
        ['job_card', 'Job card'],
        ['multi_vehicle', 'Multi-vehicle'],
        ['purchase', 'Purchase'],
        ['refurbishment', 'Refurbishment'],
    ])('labels %s as %s', (type, label) => {
        render(<MemoryRouter><InvoiceCell columnKey="type" invoice={{ id: 'inv', invoice_type: type }} /></MemoryRouter>)
        expect(screen.getByText(label)).toBeInTheDocument()
    })
})

describe('Invoices columns (MAIN-142)', () => {
    it('shows Type by default, and calls the job card column Reference', () => {
        expect(DEFAULT_COLUMN_KEYS).toContain('type')
        expect(COLUMNS.find(c => c.key === 'job_card').label).toBe('Reference')
        expect(COLUMNS.some(c => c.key === 'pay_by')).toBe(false)
    })
})

// MAIN-161 — every invoice shows whose it is.
describe('InvoiceCell company column', () => {
    const renderCompany = company =>
        render(<MemoryRouter><InvoiceCell columnKey="company" invoice={{ ...jobCardInvoice, company }} /></MemoryRouter>)

    it('is shown by default', () => {
        expect(DEFAULT_COLUMN_KEYS).toContain('company')
    })

    it('shows the short company name', () => {
        renderCompany('nvs_travel_solutions')
        expect(screen.getByText('Pvt Ltd')).toBeInTheDocument()
    })

    it('shows NVS Travels', () => {
        renderCompany('nvs_travels')
        expect(screen.getByText('NVS Travels')).toBeInTheDocument()
    })
})
