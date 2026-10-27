import { describe, it, expect } from 'vitest'
import { enrichInvoice, isInteractiveClick } from '../invoiceRows'

const invoice = {
    invoice_value: '4500.00',
    approved_amount: '4200.00',
    advance_amount: '0.00',
    payments: [
        { amount_paid: 1000, tds_amount: 0, round_off: 0, paid_on: '2026-10-20', ledger: 'PCN', status: 'Active', created_at: '2026-10-20T05:00:00Z' },
        { amount_paid: 2000, tds_amount: 20, round_off: 0, paid_on: '2026-10-25', ledger: 'NVS 659 Manjunath', status: 'Active', created_at: '2026-10-25T05:00:00Z' },
        { amount_paid: 900, tds_amount: 0, round_off: 0, paid_on: '2026-10-26', ledger: 'Bill accounted', status: 'Cancelled', created_at: '2026-10-26T05:00:00Z' },
    ],
}

describe('enrichInvoice', () => {
    it('works out discount, paid, TDS and balance, ignoring the cancelled payment', () => {
        const row = enrichInvoice(invoice)
        expect(row.discount).toBe(30000)
        expect(row.settlement).toMatchObject({ payable: 420000, paid: 300000, tds: 2000, balance: 118000 })
    })

    it('takes Last Paid On and Last Ledger from the latest active payment', () => {
        const row = enrichInvoice(invoice)
        expect(row.lastPaidOn).toBe('2026-10-25')
        expect(row.lastLedger).toBe('NVS 659 Manjunath')
    })

    it('breaks a same-day tie by when the payment was recorded', () => {
        const row = enrichInvoice({
            ...invoice,
            payments: [
                { amount_paid: 1, paid_on: '2026-10-25', ledger: 'PCN', status: 'Active', created_at: '2026-10-25T09:00:00Z' },
                { amount_paid: 1, paid_on: '2026-10-25', ledger: 'Bill accounted', status: 'Active', created_at: '2026-10-25T05:00:00Z' },
            ],
        })
        expect(row.lastLedger).toBe('PCN')
    })

    it('leaves the payment columns empty when nothing has been paid', () => {
        const row = enrichInvoice({ ...invoice, payments: [] })
        expect(row.lastPaidOn).toBeNull()
        expect(row.lastLedger).toBeNull()
        expect(row.settlement.balance).toBe(420000)
    })
})

describe('isInteractiveClick', () => {
    const el = html => {
        const root = document.createElement('div')
        root.innerHTML = html
        return root
    }

    it('lets a click on plain row text expand the row', () => {
        const root = el('<span>KA-01-AB-1234</span>')
        expect(isInteractiveClick(root.querySelector('span'))).toBe(false)
    })

    it('leaves buttons, links, inputs and their contents to do their own job', () => {
        const root = el('<button><svg><path/></svg></button><a href="#">#2820</a><input />')
        expect(isInteractiveClick(root.querySelector('path'))).toBe(true)
        expect(isInteractiveClick(root.querySelector('a'))).toBe(true)
        expect(isInteractiveClick(root.querySelector('input'))).toBe(true)
    })

    it('treats a dropdown option as interactive', () => {
        const root = el('<div role="listbox"><div role="option"><span>Hold - on request</span></div></div>')
        expect(isInteractiveClick(root.querySelector('span'))).toBe(true)
    })
})
