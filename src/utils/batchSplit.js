/**
 * Vehicle-line arithmetic for a multi-vehicle invoice (MAIN-99, MAIN-112), in whole
 * paise for the same reason as settlement.js: the lines must add up to the approved
 * amount exactly. A line's amount is rate × quantity; save_batch_service_invoice works
 * it out again in Postgres numeric and makes the binding check.
 */
import { toPaise } from './settlement'

const QUANTITY_PATTERN = /^[0-9]{1,6}$/

/**
 * A line's amount in paise: rate × quantity. NaN when the rate is blank, malformed or
 * zero, or the quantity is not a whole number of at least 1.
 */
export function lineAmount(line) {
    const rate = toPaise(line.rate)
    const quantity = String(line.quantity ?? '').trim()
    if (line.rate === '' || !Number.isFinite(rate) || rate <= 0) return NaN
    if (!QUANTITY_PATTERN.test(quantity) || Number(quantity) < 1) return NaN
    return rate * Number(quantity)
}

/**
 * Where the lines stand against the approved amount, in paise. `difference` is
 * approved − lines: positive means amount still to allocate, negative over-allocated.
 * `invalid` lists the indexes of lines whose rate or quantity is not usable.
 */
export function linesSummary(lines, approvedAmount) {
    const invalid = []
    let total = 0
    lines.forEach((line, i) => {
        const amount = lineAmount(line)
        if (Number.isFinite(amount)) total += amount
        else invalid.push(i)
    })
    const approved = toPaise(approvedAmount)
    return {
        total,
        approved,
        difference: Number.isFinite(approved) ? approved - total : NaN,
        invalid,
    }
}
