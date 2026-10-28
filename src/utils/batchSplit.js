/**
 * Vehicle-line arithmetic for a multi-vehicle invoice (MAIN-99), in whole paise for the
 * same reason as settlement.js: the lines must add up to the approved amount exactly.
 * save_batch_service_invoice makes the binding check in Postgres numeric.
 */
import { toPaise, paiseToInput } from './settlement'

/**
 * The approved amount shared evenly across `count` vehicles, as input strings. The
 * paise that do not divide evenly go on the last line, so the lines always add up.
 * Returns [] when there is nothing valid to split.
 */
export function splitEvenly(approvedAmount, count) {
    const total = toPaise(approvedAmount)
    if (!count || !Number.isFinite(total) || total <= 0) return []
    const share = Math.floor(total / count)
    return Array.from({ length: count }, (_, i) =>
        paiseToInput(i === count - 1 ? total - share * (count - 1) : share),
    )
}

/**
 * Where the lines stand against the approved amount, in paise. `difference` is
 * approved − lines: positive means amount still to allocate, negative over-allocated.
 * `invalid` lists the indexes of lines whose amount is blank, malformed or zero.
 */
export function linesSummary(lines, approvedAmount) {
    const invalid = []
    let total = 0
    lines.forEach((line, i) => {
        const paise = toPaise(line.amount)
        if (line.amount === '' || !Number.isFinite(paise) || paise <= 0) invalid.push(i)
        else total += paise
    })
    const approved = toPaise(approvedAmount)
    return {
        total,
        approved,
        difference: Number.isFinite(approved) ? approved - total : NaN,
        invalid,
    }
}
