import { toPaise, paiseToInput } from './settlement'
import { DEFAULT_GST_RATE, GST_RATES } from '../constants/gstRates'

/**
 * The GST breakdown of a job card or multi-vehicle invoice (MAIN-166): one row per rate,
 * whose Amount incl. GST add up to the Invoice Value. The database holds the same rules in
 * gst_breakdown_problem(); these let the form say so before saving.
 *
 * A form row is { rate: '18', amount: '1180', entered: 'incl' | 'before' } — the amount
 * the exec typed and which one it was; the other two are worked out from the rate, in
 * whole paise:
 *   incl entered   → before = incl ÷ (1 + rate), rounded; GST = incl − before
 *   before entered → GST = before × rate, rounded;      incl = before + GST
 * The saved shape is [{ rate, before_gst, gst, incl_gst }] in rupees.
 */

export function emptyGstRow(rate = DEFAULT_GST_RATE) {
    return { rate: String(rate), amount: '', entered: 'incl' }
}

const hasAmount = row => String(row.amount ?? '').trim() !== ''

/** True when no row has an amount typed — the breakdown has not been started. */
export function isGstBreakdownEmpty(rows) {
    return !(rows ?? []).some(hasAmount)
}

/** A row's three amounts in paise, or null when its amount is blank or not an amount. */
export function gstRowPaise(row) {
    if (!hasAmount(row)) return null
    const amount = toPaise(row.amount)
    const rate = Number(row.rate)
    if (Number.isNaN(amount) || Number.isNaN(rate)) return null
    if (row.entered === 'before') {
        const gst = Math.round(amount * rate / 100)
        return { before: amount, gst, incl: amount + gst }
    }
    const before = Math.round(amount * 100 / (100 + rate))
    return { before, gst: amount - before, incl: amount }
}

/** The rows' Amount incl. GST added up, in paise (rows without an amount count 0). */
export function gstRowsInclPaise(rows) {
    return (rows ?? []).reduce((sum, r) => sum + (gstRowPaise(r)?.incl ?? 0), 0)
}

/** Why the breakdown can't be saved against this Invoice Value, or null. */
export function gstBreakdownProblem(rows, invoiceValue) {
    const list = rows ?? []
    if (isGstBreakdownEmpty(list)) return 'Add the GST breakdown.'
    const seen = new Set()
    for (const row of list) {
        if (!GST_RATES.includes(Number(row.rate))) return 'Choose a GST rate on every row.'
        if (seen.has(Number(row.rate))) return 'Use one row per GST rate.'
        seen.add(Number(row.rate))
        const p = gstRowPaise(row)
        if (!p || p.incl <= 0) return 'Every GST row needs an amount.'
    }
    const total = gstRowsInclPaise(list)
    const value = toPaise(invoiceValue)
    if (Number.isNaN(value) || value <= 0) return 'Enter the Invoice Value first.'
    if (total !== value) {
        return `The GST rows add up to ₹${paiseToInput(total)} but the Invoice Value is ₹${paiseToInput(value)}.`
    }
    return null
}

/** Form rows as gst_breakdown. Call only once gstBreakdownProblem is null. */
export function gstRowsToBreakdown(rows) {
    return rows.filter(hasAmount).map(r => {
        const p = gstRowPaise(r)
        return {
            rate:       Number(r.rate),
            before_gst: p.before / 100,
            gst:        p.gst / 100,
            incl_gst:   p.incl / 100,
        }
    })
}

/**
 * A saved gst_breakdown as form rows. Each comes back as its Amount incl. GST, which
 * always reproduces the saved split: a split made from the amount before GST rounds back
 * to the same amount before GST.
 */
export function breakdownToGstRows(breakdown) {
    if (!Array.isArray(breakdown)) return []
    return breakdown.map(b => ({
        rate: String(Number(b.rate)),
        amount: paiseToInput(toPaise(Number(b.incl_gst).toFixed(2))),
        entered: 'incl',
    }))
}

/** The bill's total GST in rupees, or null when there is no breakdown. */
export function breakdownGstTotal(breakdown) {
    if (!Array.isArray(breakdown)) return null
    return breakdown.reduce((sum, b) => sum + toPaise(Number(b.gst).toFixed(2)), 0) / 100
}

const rupees = paise => `₹${(paise / 100).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

/** One line per rate, e.g. "18%: ₹1,000.00 + ₹180.00 GST = ₹1,180.00". */
export function breakdownLines(breakdown) {
    if (!Array.isArray(breakdown)) return []
    return breakdown.map(b => {
        const [before, gst, incl] = [b.before_gst, b.gst, b.incl_gst].map(v => toPaise(Number(v).toFixed(2)))
        return `${Number(b.rate)}%: ${rupees(before)} + ${rupees(gst)} GST = ${rupees(incl)}`
    })
}

/** True when two saved breakdowns are the same rows in the same order. */
export function sameBreakdown(a, b) {
    const norm = x => JSON.stringify((Array.isArray(x) ? x : []).map(r =>
        [Number(r.rate), toPaise(Number(r.before_gst).toFixed(2)), toPaise(Number(r.gst).toFixed(2)), toPaise(Number(r.incl_gst).toFixed(2))]))
    return norm(a) === norm(b)
}
