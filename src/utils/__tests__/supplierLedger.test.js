import { describe, it, expect } from 'vitest'
import { describeLine, describeAdvanceLine, invoiceOwner, invoiceSplit, balanceAsOf, isVoided } from '../supplierLedger'

// MAIN-119 — how ledger lines read, from get_supplier_statement / get_advance_statement rows.
describe('invoiceSplit', () => {
    it('shows where the approved value goes when a person paid the advance', () => {
        expect(invoiceSplit({ to_supplier: 500, advance: 500, paid_by: 'NVS 659 Manjunath', advance_by_person: true }))
            .toBe('₹500.00 to the supplier + ₹500.00 advance to repay Manjunath')
    })

    it('says a company-paid advance needs no repaying', () => {
        expect(invoiceSplit({ to_supplier: 700, advance: 300, paid_by: 'Accounts', advance_by_person: false }))
            .toBe('₹700.00 to the supplier + ₹300.00 advance paid from Accounts')
    })

    it('is just the supplier share with no advance', () => {
        expect(invoiceSplit({ to_supplier: 1000, advance: 0 })).toBe('₹1,000.00 to the supplier')
    })
})

describe('describeLine', () => {
    it('gives an invoice its submission day, due date and split', () => {
        const line = {
            kind: 'invoice', invoice_no: 'INV-1', due_date: '2026-11-04',
            detail: { submitted_on: '2026-11-01', to_supplier: 500, advance: 500, paid_by: 'NVS 2954 Gokilavanan', advance_by_person: true },
        }
        expect(describeLine(line).sub).toBe(
            'Reached finance 01 Nov 2026 · due 04 Nov 2026 · ₹500.00 to the supplier + ₹500.00 advance to repay Gokilavanan',
        )
    })

    it('names an advance after the person who paid it', () => {
        const line = { kind: 'advance', invoice_no: 'INV-482', detail: { paid_by: 'PCN', advance_by_person: true } }
        expect(describeLine(line).title).toBe('Advance – Nithin (Petty Cash)')
    })

    it('shows a payment’s date paid, TDS and trail', () => {
        const line = {
            kind: 'payment',
            detail: { paid_on: '2026-11-02', payment_method: 'NEFT', bank: 'Kotak Mahindra', utr: 'KKBK1', amount_paid: '5940.00', tds_amount: '60.00', recorded_by: 'Vijay' },
        }
        const { title, sub } = describeLine(line)
        expect(title).toBe('Bill accounted · NEFT · Kotak Mahindra')
        expect(sub).toBe('Paid 02 Nov 2026 · ₹5,940.00 + ₹60.00 TDS · UTR KKBK1 · recorded by Vijay')
    })

    it('shows what reconciliation found, and who reversed it', () => {
        const detail = {
            as_of: '2026-11-30', confirmed_against: 'Vendor statement', system_balance: '2450.00',
            confirmed_balance: '2400.00', reason: 'Vendor waived 50', created_by: 'Vijay',
            reversed_by: 'Asha', reverse_reason: 'wrong supplier',
        }
        expect(describeLine({ kind: 'adjustment', detail }).sub).toBe('As of 30 Nov 2026 · app showed ₹2,450.00 · confirmed ₹2,400.00 · Vendor waived 50 · by Vijay')
        expect(describeLine({ kind: 'reversed', detail }).sub).toContain('Reversed by Asha: wrong supplier')
    })
})

describe('describeAdvanceLine', () => {
    it('ties an advance to its invoice and supplier', () => {
        const line = { kind: 'advance', invoice_no: 'E2E-1', due_date: '2026-11-01', detail: { supplier: 'Nidhi washing centre', approved: 1000, to_supplier: 500 } }
        expect(describeAdvanceLine(line)).toEqual({
            title: 'Advance on E2E-1 · Nidhi washing centre',
            sub: 'Reached finance 01 Nov 2026 · approved ₹1,000.00, ₹500.00 to the supplier',
        })
    })
})

describe('isVoided', () => {
    it('is true for cancelled payments and reversed adjustments only', () => {
        expect(isVoided({ kind: 'cancelled' })).toBe(true)
        expect(isVoided({ kind: 'reversed' })).toBe(true)
        expect(isVoided({ kind: 'payment' })).toBe(false)
    })
})

describe('invoiceOwner', () => {
    it('names the job card or the multi-vehicle invoice', () => {
        expect(invoiceOwner({ job_card_number: 3101 }).label).toBe('Job card #3101')
        expect(invoiceOwner({ batch_number: 4 }).label).toBe('MVI-4')
        expect(invoiceOwner({})).toBeNull()
    })

    it('names a refurbishment by its purchase invoice', () => {
        expect(invoiceOwner({ detail: { purchase_invoice_id: 'pi1' } })).toEqual({ label: 'Purchase', purchaseInvoiceId: 'pi1' })
    })
})

describe('balanceAsOf', () => {
    // entry_at as timestamps; the suite runs with TZ=UTC in CI, so these read as UTC days.
    const lines = [
        { entry_at: '2026-11-10T09:00:00Z', balance: '10000.00' },
        { entry_at: '2026-11-10T09:00:00Z', balance: '6000.00' },
        { entry_at: '2026-11-25T12:00:00Z', balance: '0.00' },
    ]

    it('takes the running balance after everything entered by the end of the day', () => {
        expect(balanceAsOf(lines, '2026-11-10')).toBe(6000)
        expect(balanceAsOf(lines, '2026-11-24')).toBe(6000)
        expect(balanceAsOf(lines, '2026-12-01')).toBe(0)
    })

    it('is zero before the first entry', () => {
        expect(balanceAsOf(lines, '2026-11-01')).toBe(0)
    })
})
