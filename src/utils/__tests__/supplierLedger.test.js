import { describe, it, expect } from 'vitest'
import { describeLine, invoiceOwner, balanceAsOf } from '../supplierLedger'

// MAIN-119 — how statement lines read, from get_supplier_statement rows.
describe('describeLine', () => {
    it('names an advance after the person who paid it', () => {
        const line = { kind: 'advance', invoice_no: 'INV-482', detail: { paid_by: 'Gokilavanan' } }
        expect(describeLine(line).title).toBe('Advance – Gokilavanan')
    })

    it('splits a payment into paid and TDS, with its trail', () => {
        const line = {
            kind: 'payment',
            detail: { ledger: 'Bill accounted', payment_method: 'NEFT', bank: 'Kotak Mahindra', utr: 'KKBK1', amount_paid: '5940.00', tds_amount: '60.00', recorded_by: 'Vijay' },
        }
        const { title, sub } = describeLine(line)
        expect(title).toBe('Bill accounted · NEFT · Kotak Mahindra')
        expect(sub).toContain('₹5,940.00 paid + ₹60.00 TDS')
        expect(sub).toContain('UTR KKBK1')
        expect(sub).toContain('recorded by Vijay')
    })

    it('says a reimbursement does not count toward the supplier', () => {
        const line = { kind: 'reimbursement', detail: { ledger: 'NVS 2954 Gokilavanan', payment_method: 'Cash', amount_paid: '4000.00', tds_amount: '0' } }
        expect(describeLine(line).sub).toContain("Not counted in this supplier's balance")
    })

    it('shows what reconciliation found', () => {
        const line = { kind: 'adjustment', detail: { confirmed_against: 'Vendor statement', system_balance: '2450.00', confirmed_balance: '2400.00', reason: 'Vendor waived 50', created_by: 'Vijay' } }
        const { title, sub } = describeLine(line)
        expect(title).toBe("Reconciled against the vendor's statement")
        expect(sub).toContain('App showed ₹2,450.00 · confirmed ₹2,400.00')
    })

    it('formats an invoice line’s due date', () => {
        expect(describeLine({ kind: 'invoice', invoice_no: 'INV-1', due_date: '2026-08-19' }).sub).toBe('Accepted by finance · due 19 Aug 2026')
    })
})

describe('invoiceOwner', () => {
    it('names the job card or the multi-vehicle invoice', () => {
        expect(invoiceOwner({ job_card_number: 3101 }).label).toBe('Job card #3101')
        expect(invoiceOwner({ batch_number: 4 }).label).toBe('MVI-4')
        expect(invoiceOwner({})).toBeNull()
    })
})

describe('balanceAsOf', () => {
    const lines = [
        { entry_date: '2026-11-10', balance: '10000.00' },
        { entry_date: '2026-11-10', balance: '6000.00' },
        { entry_date: '2026-11-25', balance: '0.00' },
    ]

    it('takes the running balance at the end of the day', () => {
        expect(balanceAsOf(lines, '2026-11-10')).toBe(6000)
        expect(balanceAsOf(lines, '2026-11-24')).toBe(6000)
        expect(balanceAsOf(lines, '2026-12-01')).toBe(0)
    })

    it('is zero before the first line', () => {
        expect(balanceAsOf(lines, '2026-11-01')).toBe(0)
    })
})
