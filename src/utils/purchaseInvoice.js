/**
 * A purchase or refurbishment invoice's running number (purchase_invoices.purchase_number,
 * MAIN-143), shown as "PI-257" beside the supplier's own invoice number, which suppliers
 * reuse. It has no page of its own: the link opens it from Purchase History, in the
 * purchase or refurbishment form by its kind (MAIN-130). Invoices and the supplier
 * ledger link here (MAIN-123).
 */
export const PI_PREFIX = 'PI-'

export function formatPurchaseNumber(n) {
    return `${PI_PREFIX}${n}`
}

export function purchaseInvoicePath(n) {
    return `/inventory?tab=history&invoice=${formatPurchaseNumber(n)}`
}

/** "PI-257", "pi-257" or "257" → 257; anything else → null. */
export function parsePurchaseNumber(value) {
    const match = /^(?:PI-)?([0-9]{1,9})$/i.exec(String(value ?? '').trim())
    return match ? Number(match[1]) : null
}
