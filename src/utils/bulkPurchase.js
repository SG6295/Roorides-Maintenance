import * as XLSX from 'xlsx'
import { invoiceTotal } from '../lib/invoiceDiscount'
import { PAID_BY_OPTIONS, MAINTENANCE_PAYMENT_STATUSES } from '../constants/outsourceInvoices'

/**
 * Bulk Upload's invoice-level rules (MAIN-129). Rows are grouped into invoices by
 * number, date and supplier; each invoice names an approved supplier and carries the
 * finance details, which every row of it must repeat identically. The Approved Amount
 * is the lines' total, so it always matches. save_purchase_invoice enforces the same
 * rules; these let the preview say what is wrong before anything is written.
 */

const norm = v => String(v ?? '').trim().toLowerCase()
const isBlank = v => String(v ?? '').trim() === ''

/** A spreadsheet date cell — a Date, an Excel serial number or text — as YYYY-MM-DD. */
export function cellDate(value) {
    if (value instanceof Date) return value.toISOString().slice(0, 10)
    if (typeof value === 'number') {
        const d = XLSX.SSF.parse_date_code(value)
        return `${d.y}-${String(d.m).padStart(2, '0')}-${String(d.d).padStart(2, '0')}`
    }
    return String(value ?? '').trim()
}

const isIsoDate = s => /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s))

/** The approved supplier with this name, ignoring case and outer spaces, or null. */
export function matchSupplier(name, suppliers) {
    const key = norm(name)
    return key ? suppliers.find(s => norm(s.entity_name) === key) ?? null : null
}

const matchOption = (value, options) => options.find(o => norm(o) === norm(value)) ?? null

// The invoice-level cells every row of one invoice must agree on.
const INVOICE_CELLS = ['paid_by', 'maintenance_status', 'pay_by_date', 'advance_amount', 'invoice_value']

/**
 * Groups validated rows into invoices and checks each invoice.
 * @param records rows from the sheet, with _rowIndex, _dateStr, _qty, _price, _gst, _discount
 * @param suppliers approved suppliers ({ id, entity_name })
 * @param today YYYY-MM-DD
 * @returns {{ invoices: object[], rowErrors: Record<number, string[]>, unknownSuppliers: string[] }}
 */
export function checkBulkInvoices(records, suppliers, today) {
    const groups = new Map()
    for (const rec of records) {
        const key = `${String(rec.invoice_number).trim()}||${rec._dateStr}||${norm(rec.supplier_name)}`
        if (!groups.has(key)) groups.set(key, [])
        groups.get(key).push(rec)
    }

    const rowErrors = {}
    const unknown = new Map()
    const invoices = []

    for (const rows of groups.values()) {
        const first = rows[0]
        const errors = []

        const supplier = matchSupplier(first.supplier_name, suppliers)
        if (!supplier && !isBlank(first.supplier_name)) {
            errors.push('Supplier not in the supplier list')
            unknown.set(norm(first.supplier_name), String(first.supplier_name).trim())
        }

        for (const cell of INVOICE_CELLS) {
            const values = new Set(rows.map(r => norm(cell.endsWith('_date') ? cellDate(r[cell]) : r[cell])))
            if (values.size > 1) errors.push(`Rows of this invoice disagree on ${cell}`)
        }

        if (isIsoDate(first._dateStr) && first._dateStr > today) errors.push('invoice_date is in the future')

        const paidBy = matchOption(first.paid_by, PAID_BY_OPTIONS)
        if (!paidBy) errors.push(`paid_by must be one of: ${PAID_BY_OPTIONS.join(', ')}`)

        const status = isBlank(first.maintenance_status)
            ? 'Approved'
            : matchOption(first.maintenance_status, MAINTENANCE_PAYMENT_STATUSES)
        if (!status) errors.push(`maintenance_status must be one of: ${MAINTENANCE_PAYMENT_STATUSES.join(', ')}`)

        const payBy = cellDate(first.pay_by_date)
        if (!isIsoDate(payBy)) errors.push('pay_by_date is missing or not a date')
        else if (isIsoDate(first._dateStr) && payBy < first._dateStr) errors.push('pay_by_date is before invoice_date')

        const approved = invoiceTotal(rows.map(r => ({
            quantity: r._qty, unit_price: r._price, gst_rate: r._gst, discount_amount: r._discount,
        })))

        const advance = isBlank(first.advance_amount) ? 0 : Number(first.advance_amount)
        if (!(advance >= 0)) errors.push('Invalid advance_amount')
        else if (advance > approved) errors.push('advance_amount is more than the invoice total')

        const invoiceValue = isBlank(first.invoice_value) ? approved : Number(first.invoice_value)
        if (!(invoiceValue > 0)) errors.push('Invalid invoice_value')
        else if (invoiceValue < approved) errors.push('invoice_value is less than the lines add up to')

        if (errors.length) {
            for (const r of rows) rowErrors[r._rowIndex] = errors
            continue
        }

        invoices.push({
            invoice_number: String(first.invoice_number).trim(),
            invoice_date: first._dateStr,
            supplier,
            notes: String(first.notes || '').trim(),
            rows,
            finance: {
                paid_by: paidBy,
                maintenance_payment_status: status,
                invoice_value: invoiceValue,
                approved_amount: approved,
                advance_amount: advance,
                payby_date: payBy,
            },
        })
    }

    return { invoices, rowErrors, unknownSuppliers: [...unknown.values()] }
}
