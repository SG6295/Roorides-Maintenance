/**
 * The work a multi-vehicle invoice line records (MAIN-112). Mirrors
 * batch_service_vehicles_work_type_check — keep in step.
 *
 * "Other" carries its own description and must link the outsourced job card it belongs
 * to; the standard types may appear once per vehicle on an invoice, Other any number.
 */
export const OTHER_WORK_TYPE = 'Other'

export const BATCH_WORK_TYPES = ['Greasing', 'Puncture', 'Air filling', 'Washing', OTHER_WORK_TYPE]

/** What a line's work is called: the standard type, or the text typed for Other. */
export function workTypeLabel(line) {
    if (line.work_type === OTHER_WORK_TYPE) return line.work_type_other || OTHER_WORK_TYPE
    return line.work_type || '—'
}

/**
 * The invoice's work in one line — "Greasing ×12 · Puncture ×3" — counting vehicle
 * lines per work, in the order the standard list gives, then Other work by its text.
 */
export function workTypeSummary(lines) {
    const counts = new Map()
    for (const line of lines ?? []) {
        const label = workTypeLabel(line)
        counts.set(label, (counts.get(label) ?? 0) + 1)
    }
    const order = label => {
        const i = BATCH_WORK_TYPES.indexOf(label)
        return i === -1 ? BATCH_WORK_TYPES.length : i
    }
    return [...counts]
        .sort(([a], [b]) => order(a) - order(b) || a.localeCompare(b))
        .map(([label, n]) => `${label} ×${n}`)
        .join(' · ')
}

/** How many vehicles an invoice covers — a vehicle with two kinds of work has two lines. */
export function vehicleCount(lines) {
    return new Set((lines ?? []).map(l => l.vehicle_number)).size
}

/** "1 vehicle" / "3 vehicles", counted as vehicleCount does. */
export function vehicleCountLabel(lines) {
    const n = vehicleCount(lines)
    return `${n} vehicle${n === 1 ? '' : 's'}`
}
