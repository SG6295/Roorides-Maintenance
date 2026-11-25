/**
 * MAIN-166 — the invoice form's GST breakdown: required on job card and multi-vehicle
 * invoices only, and an untouched breakdown leaves a job card's optional invoice empty.
 */
import { describe, it, expect } from 'vitest'
import { EMPTY_INVOICE_FORM, isInvoiceFormEmpty, validateInvoiceForm, invoiceFormToRow } from '../invoiceForm'
import { emptyGstRow } from '../../../utils/gstBreakdown'

const filled = {
    dateOfActivity: '2026-11-20', invoiceNo: 'A1', paidBy: 'Accounts', invoiceValue: '4200',
    approvedAmount: '4200', advanceAmount: '0', maintenancePaymentStatus: 'Approved',
    gstRows: [{ rate: '28', amount: '1280', entered: 'incl' }, { rate: '18', amount: '2920', entered: 'incl' }],
}

describe('invoice form GST', () => {
    it('an empty GST row does not start the invoice', () => {
        expect(isInvoiceFormEmpty(EMPTY_INVOICE_FORM)).toBe(true)
        expect(isInvoiceFormEmpty({ ...EMPTY_INVOICE_FORM, gstRows: [emptyGstRow()] })).toBe(true)
        expect(isInvoiceFormEmpty({ ...EMPTY_INVOICE_FORM, gstRows: [{ ...emptyGstRow(), amount: '5' }] })).toBe(false)
    })

    it('is checked only when asked for', () => {
        const noGst = { ...filled, gstRows: [] }
        expect(validateInvoiceForm(noGst, '2026-11-25')).toEqual({})
        expect(validateInvoiceForm(noGst, '2026-11-25', { gst: true })).toEqual({ gstBreakdown: 'Add the GST breakdown.' })
        expect(validateInvoiceForm(filled, '2026-11-25', { gst: true })).toEqual({})
    })

    it('sends the breakdown only for a job card or multi-vehicle invoice', () => {
        expect(invoiceFormToRow(filled)).not.toHaveProperty('gst_breakdown')
        expect(invoiceFormToRow(filled, { gst: true }).gst_breakdown).toEqual([
            { rate: 28, before_gst: 1000, gst: 280, incl_gst: 1280 },
            { rate: 18, before_gst: 2474.58, gst: 445.42, incl_gst: 2920 },
        ])
    })
})
