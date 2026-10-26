/**
 * Who pays an outsourced repair invoice — the "Paid By" choice on the job card's
 * invoice form, and the Paid By filter on Outsource Invoices.
 *
 * Mirrors the outsource_invoices_paid_by_check constraint — keep in step.
 */
export const PAID_BY_OPTIONS = ['Accounts', 'Nithin', 'Manjunath', 'Gokilavanan', 'NVS Maintenance account']

/**
 * The maintenance exec's decision at job card closure — "Payment status reported
 * by maintenance". Mirrors outsource_invoices_maintenance_payment_status_check.
 */
export const MAINTENANCE_PAYMENT_STATUSES = ['Approved', 'Hold', 'Reject']

/**
 * Finance's own decision — "Payment status reported by finance". Only finance and
 * super_admin may set it (enforced by guard_outsource_invoice_status_owners).
 * Mirrors outsource_invoices_finance_payment_status_check — keep in step.
 */
export const FINANCE_PAYMENT_STATUSES = [
    'Due',
    'Partly Paid',
    'Paid',
    'Hold - on request',
    'Hold - further details required',
    'Reject - duplicate',
    'Reject - incorrect/insufficient details',
    'Reject - other',
]

/**
 * Partly Paid and Paid follow from the recorded payments (MAIN-95) — the database
 * refuses them when set by hand — so the status dropdown offers only the rest.
 */
export const PAYMENT_DERIVED_STATUSES = ['Partly Paid', 'Paid']
export const MANUAL_FINANCE_PAYMENT_STATUSES = FINANCE_PAYMENT_STATUSES.filter(
    s => !PAYMENT_DERIVED_STATUSES.includes(s),
)

/**
 * The ledger finance posted a payment to. Distinct from Paid By, which is the
 * exec's note of who pays. Mirrors outsource_invoice_payments_ledger_check.
 */
export const LEDGER_OPTIONS = ['Bill accounted', 'NVS 659 Manjunath', 'NVS 2954 Gokilavanan', 'PCN']

/** Mirrors outsource_invoice_payments_method_check. */
export const PAYMENT_METHODS = ['UPI', 'NEFT', 'RTGS', 'IMPS', 'Cash']

/**
 * Bank the payment went out from — required, with a UTR, for every method but
 * cash. Mirrors outsource_invoice_payments_bank_check.
 */
export const BANK_OPTIONS = ['Union Bank of India', 'Kotak Mahindra']
