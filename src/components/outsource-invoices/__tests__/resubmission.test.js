/**
 * MAIN-120 — the Resubmit popup's rules. resubmit_outsource_invoice holds the same ones;
 * these let the popup say so before saving.
 */
import { describe, it, expect } from 'vitest'
import {
    resubmissionStart,
    resubmissionChanges,
    resubmissionProblem,
    resubmissionPayload,
    linesTotalPaise,
    rejectionEntry,
} from '../resubmission'

const row = (extra = {}) => ({
    id: 'oi1',
    invoice_no: 'INV-1',
    date_of_activity: '2026-11-10',
    paid_by: 'Accounts',
    invoice_value: 1000,
    approved_amount: 1000,
    advance_amount: 0,
    maintenance_payment_status: 'Approved',
    payby_date: '2026-11-20',
    finance_payment_status: 'Reject',
    job_card: { id: 'jc1', invoice_url: 'https://drive/old', supplier: { id: 's1', entity_name: 'Ace' } },
    ...extra,
})

const edited = (start, patch = {}, form = {}) => ({ ...start, ...patch, form: { ...start.form, ...form } })
const problemFor = (invoice, start, current) =>
    resubmissionProblem(invoice, start, current, { invalid: false, changes: resubmissionChanges(start, current) })

describe('resubmissionStart', () => {
    it('reads the file and supplier from the job card', () => {
        const s = resubmissionStart(row())
        expect(s.fileUrl).toBe('https://drive/old')
        expect(s.supplierId).toBe('s1')
        expect(s.form.invoiceNo).toBe('INV-1')
    })

    it('reads a purchase invoice\'s file from the purchase', () => {
        const s = resubmissionStart(row({
            job_card: null,
            purchase_invoice: { id: 'p1', invoice_file_url: 'https://drive/p', total_amount: 1000, supplier: null },
        }))
        expect(s.fileUrl).toBe('https://drive/p')
        expect(s.supplierId).toBe('')
    })
})

describe('resubmissionChanges', () => {
    const start = resubmissionStart(row())

    it('lists nothing until something changes, and ignores how an amount is typed', () => {
        expect(resubmissionChanges(start, edited(start, {}, { approvedAmount: '1000.00', invoiceNo: ' INV-1 ' }))).toEqual([])
    })

    it('names the file, the supplier and each changed field', () => {
        const names = { s1: 'Ace', s2: 'Best' }
        const changes = resubmissionChanges(
            start,
            edited(start, { fileUrl: 'https://drive/new', supplierId: 's2' }, { invoiceNo: 'INV-2' }),
            id => names[id],
        )
        expect(changes).toEqual(['Invoice file replaced', 'Supplier: Ace → Best', 'Invoice No: INV-1 → INV-2'])
    })
})

describe('resubmissionProblem', () => {
    const invoice = row()
    const start = resubmissionStart(invoice)

    it('refuses a resubmission that changes nothing', () => {
        expect(problemFor(invoice, start, start).message).toMatch(/at least one detail/)
    })

    it('refuses one without the invoice file', () => {
        expect(problemFor(invoice, start, edited(start, { fileUrl: '' }, { invoiceNo: 'X' })).message).toMatch(/invoice file/)
    })

    it('refuses while maintenance still reports Reject', () => {
        const current = edited(start, {}, { maintenancePaymentStatus: 'Reject', invoiceNo: 'X' })
        expect(problemFor(invoice, start, current).message).toMatch(/Approved or Hold/)
    })

    it('allows a resubmission with a change', () => {
        expect(problemFor(invoice, start, edited(start, { fileUrl: 'https://drive/new' }))).toBeNull()
    })

    it('points a multi-vehicle invoice whose lines no longer match to its own page', () => {
        const batch = row({ job_card: null, batch_service: { batch_number: 3, vehicles: [{ amount: 600 }, { amount: 400 }], supplier: { id: 's1' }, invoice_url: 'u' } })
        const s = resubmissionStart(batch)
        expect(problemFor(batch, s, edited(s, {}, { invoiceNo: 'X' }))).toBeNull()
        expect(problemFor(batch, s, edited(s, {}, { approvedAmount: '900' })).linesMismatch).toBe(true)
    })
})

describe('linesTotalPaise', () => {
    it('is null for a job card, which has no lines', () => {
        expect(linesTotalPaise(row())).toBeNull()
        expect(linesTotalPaise(row({ purchase_invoice: { total_amount: 12.5 } }))).toBe(1250)
    })
})

describe('resubmissionPayload', () => {
    it('sends the fields as columns with the file, supplier and a trimmed note', () => {
        const start = resubmissionStart(row())
        const p = resubmissionPayload(edited(start, { fileUrl: 'https://drive/new' }), '  clearer scan ')
        expect(p).toMatchObject({ invoice_no: 'INV-1', supplier_id: 's1', invoice_file_url: 'https://drive/new', note: 'clearer scan' })
        expect(resubmissionPayload(start, '  ').note).toBeNull()
        // The Pay By Date is no longer asked for or sent, so a stored one is kept (MAIN-121).
        expect(p).not.toHaveProperty('payby_date')
    })
})

describe('rejectionEntry', () => {
    it('finds the latest entry that put the invoice at Reject', () => {
        const history = [
            { performed_by_name: 'Anand', new_data: { finance_payment_status: 'Reject' } },
            { performed_by_name: 'Old', new_data: { finance_payment_status: 'Reject' } },
        ]
        expect(rejectionEntry(history).performed_by_name).toBe('Anand')
        expect(rejectionEntry([])).toBeNull()
    })
})
