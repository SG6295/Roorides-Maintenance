/**
 * MAIN-129 — Bulk Upload's invoice-level rules: approved suppliers only, and the finance
 * details agreed by every row of an invoice.
 */
import { describe, it, expect } from 'vitest'
import { checkBulkInvoices, matchSupplier } from '../bulkPurchase'

const suppliers = [{ id: 's1', entity_name: 'Ram Motor Stores' }, { id: 's2', entity_name: 'Kumar Electricals' }]
const today = '2026-11-11'

let n = 2
const row = over => ({
    _rowIndex: n++,
    invoice_number: 'INV-1',
    _dateStr: '2026-11-05',
    supplier_name: 'Ram Motor Stores',
    _qty: 10, _price: 100, _gst: 18, _discount: 0,
    notes: '',
    paid_by: 'Accounts',
    pay_by_date: '2026-11-20',
    maintenance_status: '',
    advance_amount: '',
    invoice_value: '',
    ...over,
})

describe('matchSupplier', () => {
    it('ignores case and outer spaces, and needs the whole name', () => {
        expect(matchSupplier('  ram motor stores ', suppliers)?.id).toBe('s1')
        expect(matchSupplier('Ram Motors', suppliers)).toBeNull()
        expect(matchSupplier('', suppliers)).toBeNull()
    })
})

describe('checkBulkInvoices', () => {
    it('groups rows into one invoice and fills the defaults', () => {
        const { invoices, rowErrors } = checkBulkInvoices(
            [row(), row({ _qty: 2, _price: 50, _gst: 0, supplier_name: 'RAM MOTOR STORES' })], suppliers, today)

        expect(rowErrors).toEqual({})
        expect(invoices).toHaveLength(1)
        expect(invoices[0].supplier.id).toBe('s1')
        expect(invoices[0].rows).toHaveLength(2)
        // 10 × 100 + 18% = 1180, plus 2 × 50 = 100
        expect(invoices[0].finance).toEqual({
            paid_by: 'Accounts',
            maintenance_payment_status: 'Approved',
            invoice_value: 1280,
            approved_amount: 1280,
            advance_amount: 0,
            payby_date: '2026-11-20',
        })
    })

    it('refuses a supplier that is not in the list and names it once', () => {
        const a = row({ supplier_name: 'Ram Motors' })
        const b = row({ supplier_name: 'ram motors' })
        const { invoices, rowErrors, unknownSuppliers } = checkBulkInvoices([a, b], suppliers, today)

        expect(invoices).toHaveLength(0)
        expect(rowErrors[a._rowIndex]).toContain('Supplier not in the supplier list')
        expect(rowErrors[b._rowIndex]).toContain('Supplier not in the supplier list')
        expect(unknownSuppliers).toEqual(['Ram Motors'])
    })

    it('refuses rows of one invoice that disagree on its finance details', () => {
        const a = row()
        const b = row({ paid_by: 'PCN' })
        const { rowErrors } = checkBulkInvoices([a, b], suppliers, today)
        expect(rowErrors[a._rowIndex]).toContain('Rows of this invoice disagree on paid_by')
        expect(rowErrors[b._rowIndex]).toContain('Rows of this invoice disagree on paid_by')
    })

    it('matches paid_by and maintenance_status to their options, ignoring case', () => {
        const { invoices } = checkBulkInvoices([row({ paid_by: 'pcn', maintenance_status: 'hold' })], suppliers, today)
        expect(invoices[0].finance.paid_by).toBe('PCN')
        expect(invoices[0].finance.maintenance_payment_status).toBe('Hold')

        const { rowErrors } = checkBulkInvoices([row({ paid_by: 'Cash box' })], suppliers, today)
        expect(Object.values(rowErrors)[0][0]).toMatch(/^paid_by must be one of/)
    })

    it('checks the dates and amounts', () => {
        const check = over => Object.values(checkBulkInvoices([row(over)], suppliers, today).rowErrors)[0] ?? []
        expect(check({ pay_by_date: '' })).toContain('pay_by_date is missing or not a date')
        expect(check({ pay_by_date: '2026-11-01' })).toContain('pay_by_date is before invoice_date')
        expect(check({ _dateStr: '2026-11-12', pay_by_date: '2026-11-20' })).toContain('invoice_date is in the future')
        expect(check({ advance_amount: 2000 })).toContain('advance_amount is more than the invoice total')
        expect(check({ invoice_value: 1000 })).toContain('invoice_value is less than the lines add up to')
        expect(check({ invoice_value: 1500, advance_amount: 180 })).toEqual([])
    })
})
