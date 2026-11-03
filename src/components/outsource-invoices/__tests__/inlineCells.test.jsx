/**
 * MAIN-98, MAIN-118 — the cells finance edits straight from the Outsource Invoices table.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

const mutate = vi.fn()
vi.mock('../../../hooks/useOutsourceInvoices', () => ({
    useUpdateFinancePaymentStatus: () => ({ mutate, reset: vi.fn(), isPending: false, error: null }),
}))

import RemarkCell from '../RemarkCell'
import FinanceStatusCell from '../FinanceStatusCell'

const invoice = { id: 'inv-1', invoice_no: 'INV-7', finance_payment_status: 'New', finance_remark: 'old note' }

beforeEach(() => mutate.mockReset())

describe('RemarkCell', () => {
    it('saves on Enter, sending only the remark', async () => {
        const user = userEvent.setup()
        render(<RemarkCell invoice={invoice} canEdit />)

        await user.click(screen.getByRole('button', { name: 'old note' }))
        const input = screen.getByRole('textbox', { name: 'Finance remark' })
        await user.clear(input)
        await user.type(input, 'need GST no{Enter}')

        expect(mutate).toHaveBeenCalledTimes(1)
        expect(mutate).toHaveBeenCalledWith({ id: 'inv-1', financeRemark: 'need GST no' })
    })

    it('saves when focus leaves the field', async () => {
        const user = userEvent.setup()
        render(<><RemarkCell invoice={invoice} canEdit /><button>elsewhere</button></>)

        await user.click(screen.getByRole('button', { name: 'old note' }))
        await user.type(screen.getByRole('textbox', { name: 'Finance remark' }), ' updated')
        await user.click(screen.getByRole('button', { name: 'elsewhere' }))

        expect(mutate).toHaveBeenCalledWith({ id: 'inv-1', financeRemark: 'old note updated' })
    })

    it('cancels on Esc without saving', async () => {
        const user = userEvent.setup()
        render(<RemarkCell invoice={invoice} canEdit />)

        await user.click(screen.getByRole('button', { name: 'old note' }))
        await user.type(screen.getByRole('textbox', { name: 'Finance remark' }), ' typo{Escape}')

        expect(mutate).not.toHaveBeenCalled()
        expect(screen.getByRole('button', { name: 'old note' })).toBeInTheDocument()
    })

    it('does not save when nothing changed', async () => {
        const user = userEvent.setup()
        render(<RemarkCell invoice={invoice} canEdit />)

        await user.click(screen.getByRole('button', { name: 'old note' }))
        await user.type(screen.getByRole('textbox', { name: 'Finance remark' }), '{Enter}')

        expect(mutate).not.toHaveBeenCalled()
    })

    it('is plain text for roles that cannot edit', () => {
        render(<RemarkCell invoice={invoice} canEdit={false} />)
        expect(screen.queryByRole('button')).not.toBeInTheDocument()
        expect(screen.getByText('old note')).toBeInTheDocument()
    })
})

describe('FinanceStatusCell', () => {
    const options = () => screen.getAllByRole('option').map(o => o.textContent)

    it('offers only the moves allowed from New, and saves the pick sending only the status', async () => {
        const user = userEvent.setup()
        render(<FinanceStatusCell invoice={invoice} canEdit />)

        await user.click(screen.getByRole('button'))
        expect(options()).toEqual(['New', 'Hold', 'Reject', 'Accepted'])

        await user.click(screen.getByRole('option', { name: 'Hold' }))
        expect(mutate).toHaveBeenCalledWith(
            { id: 'inv-1', financePaymentStatus: 'Hold' },
            expect.any(Object),
        )
    })

    it('lets Accepted go back to Hold, on to Reject or to a GST close — never to New', async () => {
        const user = userEvent.setup()
        render(<FinanceStatusCell invoice={{ ...invoice, finance_payment_status: 'Accepted' }} canEdit />)

        await user.click(screen.getByRole('button'))
        expect(options()).toEqual(['Accepted', 'Hold', 'Reject', 'GST reconciled & closed', 'GST not applicable & closed'])
    })

    it('asks for a new reason before rejecting, and saves status and reason together', async () => {
        const user = userEvent.setup()
        render(<FinanceStatusCell invoice={invoice} canEdit />)

        await user.click(screen.getByRole('button'))
        await user.click(screen.getByRole('option', { name: 'Reject' }))
        expect(mutate).not.toHaveBeenCalled()

        const dialog = screen.getByRole('dialog')
        expect(dialog).toHaveTextContent('Reject is final')
        const confirm = screen.getByRole('button', { name: 'Reject invoice' })
        expect(confirm).toBeDisabled()

        // The current remark is not a reason for rejecting.
        await user.type(screen.getByLabelText(/Reason/), 'old note')
        expect(confirm).toBeDisabled()

        await user.clear(screen.getByLabelText(/Reason/))
        await user.type(screen.getByLabelText(/Reason/), '  Duplicate of INV-3 ')
        await user.click(confirm)
        expect(mutate).toHaveBeenCalledWith(
            { id: 'inv-1', financePaymentStatus: 'Reject', financeRemark: 'Duplicate of INV-3' },
            expect.any(Object),
        )
    })

    it('saves nothing when the reject dialog is cancelled', async () => {
        const user = userEvent.setup()
        render(<FinanceStatusCell invoice={invoice} canEdit />)

        await user.click(screen.getByRole('button'))
        await user.click(screen.getByRole('option', { name: 'Reject' }))
        await user.click(screen.getByRole('button', { name: 'Cancel' }))

        expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
        expect(mutate).not.toHaveBeenCalled()
    })

    it.each(['Reject', 'GST reconciled & closed', 'GST not applicable & closed'])(
        'shows the final status %s as a badge, even to finance',
        status => {
            render(<FinanceStatusCell invoice={{ ...invoice, finance_payment_status: status }} canEdit />)
            expect(screen.queryByRole('button')).not.toBeInTheDocument()
            expect(screen.getByText(status)).toBeInTheDocument()
        },
    )

    it('is a badge for roles that cannot edit', () => {
        render(<FinanceStatusCell invoice={invoice} canEdit={false} />)
        expect(screen.queryByRole('button')).not.toBeInTheDocument()
        expect(screen.getByText('New')).toBeInTheDocument()
    })
})
