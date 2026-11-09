/**
 * The reason lines of a stock-audit mismatch (MAIN-123). Each line carries a quantity, a
 * reason and a comment, and together they must add up to the difference.
 */

const toPaise = n => Math.round(Number(n || 0) * 100)

/** What the review table starts from: the saved lines, or one blank line for the whole difference. */
export function initialAuditLines(item) {
    const saved = [...(item.reason_lines ?? [])].sort((a, b) => a.sort_order - b.sort_order)
    if (saved.length > 0) {
        return saved.map(l => ({ quantity: String(Number(l.quantity)), reason: l.reason, notes: l.notes ?? '' }))
    }
    return [{ quantity: String(Math.abs(item.variance ?? 0)), reason: '', notes: '' }]
}

/** How much of the difference the lines do not cover yet. Negative when they cover too much. */
export function unallocatedQty(variance, lines) {
    const allocated = lines.reduce((sum, l) => sum + toPaise(l.quantity), 0)
    return (toPaise(Math.abs(variance)) - allocated) / 100
}

export function lineNeedsNote(line) {
    return line.reason === 'other' && !String(line.notes ?? '').trim()
}

/** True once the audit could complete as far as this part is concerned. */
export function isMismatchExplained(variance, lines) {
    return (
        unallocatedQty(variance, lines) === 0 &&
        lines.every(l => l.reason && Number(l.quantity) > 0 && !lineNeedsNote(l))
    )
}

/** The lines worth saving. A half-filled line stays on screen but is not sent. */
export function savableAuditLines(lines) {
    return lines
        .filter(l => l.reason && Number(l.quantity) > 0)
        .map(l => ({ quantity: Number(l.quantity), reason: l.reason, notes: l.notes?.trim() || null }))
}
