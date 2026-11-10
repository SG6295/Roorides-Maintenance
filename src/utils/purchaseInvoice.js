/**
 * A purchase invoice has no page of its own: this opens it in Purchase History's Edit
 * Purchase popup. Outsource Invoices and the supplier ledger link here (MAIN-123).
 */
export function purchaseInvoicePath(id) {
    return `/inventory?tab=history&invoice=${id}`
}
