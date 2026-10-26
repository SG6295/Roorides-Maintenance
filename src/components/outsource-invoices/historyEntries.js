/**
 * The payment recalculation updates the invoice's finance status in the same
 * transaction as the payment, so the two share a timestamp and a performer. Fold
 * that status change into the payment entry, so it reads as one event.
 */
export function foldStatusChanges(entries) {
    const isRecalc = e =>
        e.source === 'invoice' &&
        e.action === 'UPDATE' &&
        e.changed_fields?.length === 1 &&
        e.changed_fields[0] === 'finance_payment_status'

    const folded = entries
        .filter(e => !isRecalc(e))
        .map(e => {
            if (e.source !== 'payment') return e
            const recalc = entries.find(r =>
                isRecalc(r) &&
                r.performed_at === e.performed_at &&
                r.performed_by_name === e.performed_by_name,
            )
            return recalc ? { ...e, statusChange: recalc } : e
        })

    // A status change with no payment beside it was made by hand — keep it.
    const orphans = entries.filter(r =>
        isRecalc(r) &&
        !entries.some(e => e.source === 'payment' && e.performed_at === r.performed_at && e.performed_by_name === r.performed_by_name),
    )
    return [...folded, ...orphans].sort((a, b) => (a.performed_at < b.performed_at ? 1 : -1))
}
