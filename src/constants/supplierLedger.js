/**
 * The supplier ledger (MAIN-119). Payment fields reuse LEDGER_OPTIONS, PAYMENT_METHODS
 * and BANK_OPTIONS from outsourceInvoices.js, mirrored by the supplier_payments CHECKs.
 */

/**
 * The one posted ledger that pays the vendor and reduces what it is owed. Every other
 * ledger is a person's — paying them back for an advance — and leaves the supplier's
 * balance alone. Mirrors supplier_ledger_lines().
 */
export const VENDOR_LEDGER = 'Bill accounted'

/** Mirrors supplier_ledger_adjustments_source_check. */
export const RECONCILE_SOURCES = ['Tally', 'Vendor statement']

/** Who may record payments, reconcile and set credit days; exec reads only. */
export const LEDGER_WRITE_ROLES = ['finance', 'super_admin']
export const LEDGER_READ_ROLES = ['finance', 'super_admin', 'maintenance_exec']
