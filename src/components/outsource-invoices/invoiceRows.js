import { toPaise } from '../../utils/settlement'

/**
 * Adds what the list's calculated columns need to one invoice row, in paise.
 */
export function enrichInvoice(inv) {
    return {
        ...inv,
        // A cancelled multi-vehicle invoice (MAIN-112) stays listed but is owed nothing.
        cancelled: inv.batch_service?.status === 'Cancelled',
        // A purchase invoice records whether it is a refurbishment (MAIN-130).
        refurbishment: inv.purchase_invoice?.kind === 'refurbishment',
        payable: toPaise(inv.approved_amount ?? 0) - toPaise(inv.advance_amount ?? 0),
        // Discount = Invoice value − Approved amount (MAIN-95).
        discount: toPaise(inv.invoice_value ?? 0) - toPaise(inv.approved_amount ?? 0),
    }
}
