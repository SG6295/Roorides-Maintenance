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
