import { invoiceSettlement, toPaise } from '../../utils/settlement'

/**
 * Adds what the list's calculated columns need to one invoice row: its settlement
 * (in paise), discount, and the date and ledger of its most recent active payment.
 * Cancelled payments count for nothing.
 */
export function enrichInvoice(inv) {
    const payments = inv.payments ?? []
    const latest = payments
        .filter(p => p.status !== 'Cancelled')
        .reduce((best, p) => {
            if (!best) return p
            const pKey = `${p.paid_on}|${p.created_at ?? ''}`
            const bestKey = `${best.paid_on}|${best.created_at ?? ''}`
            return pKey > bestKey ? p : best
        }, null)

    return {
        ...inv,
        settlement: invoiceSettlement(inv, payments),
        // Discount = Invoice value − Approved amount (MAIN-95).
        discount: toPaise(inv.invoice_value ?? 0) - toPaise(inv.approved_amount ?? 0),
        lastPaidOn: latest?.paid_on ?? null,
        lastLedger: latest?.ledger ?? null,
    }
}

/**
 * Whether a click on an invoice row landed on something with its own job — a
 * button, link, input or dropdown option — rather than on the row itself. Only a
 * click on the row expands it (MAIN-98). Dropdown options render in a portal but
 * their clicks still bubble through React to the row, hence the role checks.
 */
export function isInteractiveClick(target) {
    return !!target?.closest?.('button, a, input, textarea, select, label, [role="option"], [role="listbox"]')
}
