/**
 * A purchase invoice has no page of its own: this opens it from Purchase History, in the
 * purchase or refurbishment form by its kind (MAIN-130). Outsource Invoices and the
 * supplier ledger link here (MAIN-123).
 */
export function purchaseInvoicePath(id) {
    return `/inventory?tab=history&invoice=${id}`
}
