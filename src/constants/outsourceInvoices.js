/**
 * Who pays an outsourced repair invoice — the "Paid By" choice on the job card's
 * invoice form, and the Paid By filter on Outsource Invoices.
 *
 * Mirrors the outsource_invoices_paid_by_check constraint — keep in step.
 */
export const PAID_BY_OPTIONS = ['Accounts', 'Nithin', 'Manjunath', 'Gokilavannan', 'NVS Maintenance account']

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
    'Paid',
    'Hold - on request',
    'Hold - further details required',
    'Reject - duplicate',
    'Reject - incorrect/insufficient details',
    'Reject - other',
]
