import { invoiceFormFromRow, invoiceFormToRow } from './invoiceForm'
import { fmtMoney, fmtDate, fmtPaise } from './format'
import { toPaise } from '../../utils/settlement'
import { breakdownLines, gstRowsToBreakdown, sameBreakdown } from '../../utils/gstBreakdown'

/**
 * The Resubmit popup's rules (MAIN-120), for a row of the Invoices list. The
 * database checks the same things in resubmit_outsource_invoice; these let the popup say
 * so before saving.
 */

/** The rejected invoice as the popup starts: its supplier, its file and its details. */
export function resubmissionStart(invoice) {
    const purchase = invoice.purchase_invoice
    const owner = invoice.batch_service ?? purchase ?? invoice.job_card
    return {
        supplierId: owner?.supplier?.id ?? '',
        fileUrl: (purchase ? purchase.invoice_file_url : owner?.invoice_url) ?? '',
        form: invoiceFormFromRow(invoice),
    }
}

const FIELDS = [
    ['invoiceNo',                'Invoice No'],
    ['dateOfActivity',           'Date'],
    ['paidBy',                   'Paid By'],
    ['invoiceValue',             'Invoice value'],
    ['approvedAmount',           'Approved amount'],
    ['advanceAmount',            'Advance'],
    ['maintenancePaymentStatus', 'Maintenance status'],
]
const MONEY = ['invoiceValue', 'approvedAmount', 'advanceAmount']
const DATES = ['dateOfActivity']

// "1000" and "1000.00" are the same amount; " A1 " and "A1" the same number.
const same = (field, a, b) => MONEY.includes(field)
    ? toPaise(a) === toPaise(b)
    : String(a ?? '').trim() === String(b ?? '').trim()

const show = (field, v) => {
    if (v == null || String(v).trim() === '') return '—'
    if (MONEY.includes(field)) return fmtMoney(v)
    if (DATES.includes(field)) return fmtDate(v)
    return String(v).trim()
}

/**
 * What has changed so far, one line each, for the popup's list. `supplierName` names a
 * supplier id.
 */
export function resubmissionChanges(start, current, supplierName = id => id) {
    const out = []
    if (current.fileUrl !== start.fileUrl) out.push('Invoice file replaced')
    if (current.supplierId !== start.supplierId) {
        out.push(`Supplier: ${supplierName(start.supplierId) || '—'} → ${supplierName(current.supplierId) || '—'}`)
    }
    for (const [field, label] of FIELDS) {
        if (!same(field, start.form[field], current.form[field])) {
            out.push(`${label}: ${show(field, start.form[field])} → ${show(field, current.form[field])}`)
        }
    }
    // The GST breakdown (MAIN-166), compared as saved; a half-typed row is not a change.
    const gstOf = form => {
        try { return gstRowsToBreakdown(form.gstRows ?? []) } catch { return null }
    }
    const [before, after] = [gstOf(start.form), gstOf(current.form)]
    if (after && !sameBreakdown(before, after)) {
        const describe = b => (b && b.length ? breakdownLines(b).join('; ') : '—')
        out.push(`GST breakdown: ${describe(before)} → ${describe(after)}`)
    }
    return out
}

/** The invoice's lines total in paise, or null for a job card, which has no lines. */
export function linesTotalPaise(invoice) {
    if (invoice.batch_service) {
        return (invoice.batch_service.vehicles ?? []).reduce((sum, v) => sum + toPaise(v.amount ?? 0), 0)
    }
    if (invoice.purchase_invoice) return toPaise(invoice.purchase_invoice.total_amount ?? 0)
    return null
}

/**
 * Why the popup cannot resubmit yet, or null. `linesMismatch` is set when the Approved
 * Amount no longer matches the lines, which only the invoice's own page can fix.
 */
export function resubmissionProblem(invoice, start, current, { invalid, changes }) {
    if (!current.fileUrl) return { message: 'Upload the invoice file to resubmit.' }
    // A purchase recorded before suppliers came from the list (MAIN-128) may have none.
    if (start.supplierId && !current.supplierId) return { message: 'Choose the supplier.' }
    if (invalid) return { message: 'Check the invoice details.' }
    if (current.form.maintenancePaymentStatus === 'Reject') {
        return { message: 'Set the payment status reported by maintenance to Approved or Hold to resubmit.' }
    }
    const lines = linesTotalPaise(invoice)
    if (lines !== null && toPaise(current.form.approvedAmount) !== lines) {
        return {
            message: `The lines add up to ${fmtPaise(lines)} but the approved amount is ${fmtMoney(current.form.approvedAmount)}.`,
            linesMismatch: true,
        }
    }
    if (changes.length === 0) return { message: 'Replace the file or correct at least one detail to resubmit.' }
    return null
}

/**
 * What resubmit_outsource_invoice takes. Call only once resubmissionProblem is null.
 * `gst` sends the GST breakdown — a job card or multi-vehicle invoice's (MAIN-166).
 */
export function resubmissionPayload(current, note, { gst = false } = {}) {
    return {
        ...invoiceFormToRow(current.form, { gst }),
        supplier_id: current.supplierId || null,
        invoice_file_url: current.fileUrl,
        note: note.trim() || null,
    }
}

/**
 * The entry that put the invoice at Reject — finance's, or the submission of an invoice
 * maintenance rejected at closure — from its history, newest first.
 */
export function rejectionEntry(history) {
    return history.find(e => e.new_data?.finance_payment_status === 'Reject') ?? null
}
