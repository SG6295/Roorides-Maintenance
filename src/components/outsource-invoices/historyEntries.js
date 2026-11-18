/** True for the single entry a resubmission writes (MAIN-120). */
export const isResubmission = e => e.source === 'invoice' && e.new_data?.resubmitted === true

/**
 * A multi-vehicle invoice (MAIN-99) logs one entry per vehicle line, so creating one for
 * fifteen buses would read as fifteen events. Lines changed in the same save share a
 * timestamp and a performer; fold them into one 'batch_lines' entry whose `lines` are
 * the individual changes. A resubmission is one entry too (MAIN-120): it becomes a
 * 'resubmission' entry, and the line changes saved with it go into its `lines`.
 * Everything else passes through, newest first as before.
 */
export function groupBatchLines(entries) {
    const keyOf = e => `${e.performed_at}|${e.performed_by_name ?? ''}`
    const resubmissions = new Map(
        entries.filter(isResubmission).map(e => [keyOf(e), { ...e, source: 'resubmission', lines: [] }]),
    )
    const groups = new Map()
    const out = []
    for (const e of entries) {
        if (isResubmission(e)) {
            out.push(resubmissions.get(keyOf(e)))
            continue
        }
        if (e.source !== 'batch_vehicle') {
            out.push(e)
            continue
        }
        const key = keyOf(e)
        if (resubmissions.has(key)) {
            resubmissions.get(key).lines.push(e)
            continue
        }
        let group = groups.get(key)
        if (!group) {
            group = { performed_at: e.performed_at, performed_by_name: e.performed_by_name, source: 'batch_lines', lines: [] }
            groups.set(key, group)
            out.push(group)
        }
        group.lines.push(e)
    }
    return out
}
