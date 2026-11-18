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
