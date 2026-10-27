/**
 * MAIN-98 — the cells finance edits straight from the Outsource Invoices table.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

const mutate = vi.fn()
vi.mock('../../../hooks/useOutsourceInvoices', () => ({
    useUpdateFinancePaymentStatus: () => ({ mutate, isPending: false, error: null }),
}))

import RemarkCell from '../RemarkCell'
import FinanceStatusCell from '../FinanceStatusCell'

const invoice = { id: 'inv-1', finance_payment_status: 'Due', finance_remark: 'old note' }

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
    it('offers only the manual statuses, and saves the pick sending only the status', async () => {
        const user = userEvent.setup()
        render(<FinanceStatusCell invoice={invoice} canEdit />)

        await user.click(screen.getByRole('button'))
        const options = screen.getAllByRole('option').map(o => o.textContent)
        expect(options).not.toContain('Paid')
        expect(options).not.toContain('Partly Paid')

        await user.click(screen.getByRole('option', { name: 'Hold - on request' }))
        expect(mutate).toHaveBeenCalledWith(
            { id: 'inv-1', financePaymentStatus: 'Hold - on request' },
            expect.any(Object),
        )
    })

    it('shows a payment-derived status without offering it as a choice to make', async () => {
        const user = userEvent.setup()
        render(<FinanceStatusCell invoice={{ ...invoice, finance_payment_status: 'Partly Paid' }} canEdit />)

        expect(screen.getByRole('button')).toHaveTextContent('Partly Paid')
        await user.click(screen.getByRole('button'))
        expect(screen.getAllByRole('option').map(o => o.textContent)).not.toContain('Paid')

        await user.click(screen.getByRole('option', { name: 'Partly Paid' }))
        expect(mutate).not.toHaveBeenCalled()
    })

    it('is a badge for roles that cannot edit', () => {
        render(<FinanceStatusCell invoice={invoice} canEdit={false} />)
        expect(screen.queryByRole('button')).not.toBeInTheDocument()
        expect(screen.getByText('Due')).toBeInTheDocument()
    })
})
