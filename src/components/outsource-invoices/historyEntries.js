/**
 * A multi-vehicle invoice (MAIN-99) logs one entry per vehicle line, so creating one for
 * fifteen buses would read as fifteen events. Lines changed in the same save share a
 * timestamp and a performer; fold them into one 'batch_lines' entry whose `lines` are
 * the individual changes. Everything else passes through, newest first as before.
 */
export function groupBatchLines(entries) {
    const groups = new Map()
    const out = []
    for (const e of entries) {
        if (e.source !== 'batch_vehicle') {
            out.push(e)
            continue
        }
        const key = `${e.performed_at}|${e.performed_by_name ?? ''}`
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
