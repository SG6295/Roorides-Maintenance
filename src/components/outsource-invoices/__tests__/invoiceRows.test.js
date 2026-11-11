import { describe, it, expect } from 'vitest'
import { enrichInvoice } from '../invoiceRows'

const invoice = {
    invoice_value: '4500.00',
    approved_amount: '4200.00',
    advance_amount: '1000.50',
}

describe('enrichInvoice', () => {
    it('works out discount and payable in paise', () => {
        const row = enrichInvoice(invoice)
        expect(row.discount).toBe(30000)
        expect(row.payable).toBe(319950)
    })

    it('marks a cancelled multi-vehicle invoice', () => {
        expect(enrichInvoice({ ...invoice, batch_service: { status: 'Cancelled' } }).cancelled).toBe(true)
        expect(enrichInvoice(invoice).cancelled).toBe(false)
    })

    it('marks a refurbishment by its purchase invoice\'s kind', () => {
        expect(enrichInvoice({ ...invoice, purchase_invoice: { kind: 'refurbishment' } }).refurbishment).toBe(true)
        expect(enrichInvoice({ ...invoice, purchase_invoice: { kind: 'purchase' } }).refurbishment).toBe(false)
        expect(enrichInvoice(invoice).refurbishment).toBe(false)
    })
})
