/**
 * A supplier's running number (suppliers.supplier_number, MAIN-143), shown as "SUP-5"
 * and used in its two addresses: the supplier page and its ledger statement.
 */
export const SUP_PREFIX = 'SUP-'

export function formatSupplierNumber(n) {
    return `${SUP_PREFIX}${n}`
}

export function supplierPath(n) {
    return `/suppliers/${formatSupplierNumber(n)}`
}

export function supplierLedgerPath(n) {
    return `/supplier-ledger/${formatSupplierNumber(n)}`
}

/** "SUP-5", "sup-5" or "5" → 5; anything else → null. */
export function parseSupplierNumber(value) {
    const match = /^(?:SUP-)?([0-9]{1,9})$/i.exec(String(value ?? '').trim())
    return match ? Number(match[1]) : null
}
