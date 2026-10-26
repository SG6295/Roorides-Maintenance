/**
 * Outsource invoice settlement arithmetic, in whole paise.
 *
 * Floats cannot hold most rupee amounts exactly (0.1 + 0.2 !== 0.3), and the
 * payment form compares sums against a balance to the paisa. Every amount is
 * converted to an integer number of paise first, so the comparisons are exact.
 *
 * This only drives the form — the pre-filled Paid value, the overpay warning and
 * the round-off offer. record_outsource_invoice_payment makes the binding check in
 * Postgres numeric.
 */

const AMOUNT_PATTERN = /^\d+(\.\d{1,2})?$/

/**
 * Rupees (a number, or a string as typed or as returned for a numeric column) to
 * paise. Blank is 0. Anything that is not a non-negative amount with at most two
 * decimals is NaN, so the form can reject it rather than silently round it.
 */
export function toPaise(value) {
    if (value === '' || value == null) return 0
    const s = String(value).trim()
    if (!AMOUNT_PATTERN.test(s)) return NaN
    const [rupees, paise = ''] = s.split('.')
    return Number(rupees) * 100 + Number(paise.padEnd(2, '0'))
}

/** Paise to a plain two-decimal string, as the form inputs hold it. */
export function paiseToInput(paise) {
    const sign = paise < 0 ? '-' : ''
    const abs = Math.abs(paise)
    return `${sign}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, '0')}`
}

/**
 * Where an invoice stands, in paise. Cancelled payments count for nothing.
 * A negative balance means the invoice is overpaid (possible only if the approved
 * amount was lowered after payment).
 */
export function invoiceSettlement(invoice, payments = []) {
    const active = payments.filter(p => p.status !== 'Cancelled')
    const sum = key => active.reduce((total, p) => total + toPaise(p[key] ?? 0), 0)

    const payable = toPaise(invoice.approved_amount ?? 0) - toPaise(invoice.advance_amount ?? 0)
    const paid = sum('amount_paid')
    const tds = sum('tds_amount')
    const roundOff = sum('round_off')
    const settled = paid + tds + roundOff

    return { payable, paid, tds, roundOff, settled, balance: payable - settled }
}

/**
 * When a payment would leave less than ₹1 outstanding, the remainder it can write
 * off as round-off; otherwise 0. The database accepts round-off only if it settles
 * the invoice exactly and is under ₹1.
 */
export function roundOffOffer(balancePaise, amountPaise, tdsPaise) {
    const remaining = balancePaise - amountPaise - tdsPaise
    return remaining > 0 && remaining < 100 ? remaining : 0
}
