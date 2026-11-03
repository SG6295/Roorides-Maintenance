/**
 * Rupee amounts as whole paise.
 *
 * Floats cannot hold most rupee amounts exactly (0.1 + 0.2 !== 0.3), and forms
 * compare sums to the paisa — a multi-vehicle invoice's lines against its approved
 * amount (batchSplit.js). Every amount is converted to an integer number of paise
 * first, so the comparisons are exact. The database makes the binding checks in
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
