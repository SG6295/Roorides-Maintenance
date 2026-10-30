/**
 * A multi-vehicle invoice's running number (batch_services.batch_number, MAIN-112), shown
 * as "MVI-12" and used in its link, the way a job card is #3438 at /job-cards/3438.
 */
export const MVI_PREFIX = 'MVI-'

export function formatBatchNumber(n) {
    return `${MVI_PREFIX}${n}`
}

export function batchPath(n) {
    return `/multi-vehicle-invoices/${formatBatchNumber(n)}`
}

/** "MVI-12", "mvi-12" or "12" → 12; anything else → null. */
export function parseBatchNumber(value) {
    const match = /^(?:MVI-)?([0-9]{1,9})$/i.exec(String(value ?? '').trim())
    return match ? Number(match[1]) : null
}
