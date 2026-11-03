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
 * Finance's review of an outsource invoice (MAIN-118) — "Finance status". Only finance
 * and super_admin may set it (enforced by guard_outsource_invoice_status_owners).
 * Mirrors outsource_invoices_finance_payment_status_check — keep in step.
 */
export const FINANCE_STATUSES = [
    'New',
    'Hold',
    'Reject',
    'Accepted',
    'GST reconciled & closed',
    'GST not applicable & closed',
]

/**
 * Where finance may move an invoice from each status. Reject and both GST-closed
 * statuses are final — a rejected invoice comes back only by being resubmitted
 * (MAIN-120). Mirrors the moves guard_outsource_invoice_status_owners allows — keep in
 * step.
 */
export const FINANCE_STATUS_MOVES = {
    'New':                         ['Hold', 'Reject', 'Accepted'],
    'Hold':                        ['New', 'Reject', 'Accepted'],
    'Accepted':                    ['Hold', 'Reject', 'GST reconciled & closed', 'GST not applicable & closed'],
    'Reject':                      [],
    'GST reconciled & closed':     [],
    'GST not applicable & closed': [],
}

/**
 * Once finance has accepted an invoice it is in the supplier ledger, so the exec can no
 * longer change it, reopen its job card or cancel its multi-vehicle invoice. Finance
 * moving it back to Hold, or on to Reject, lifts the lock.
 */
export const FINANCE_LOCKED_STATUSES = ['Accepted', 'GST reconciled & closed', 'GST not applicable & closed']

export const isLockedByFinance = invoice => FINANCE_LOCKED_STATUSES.includes(invoice?.finance_payment_status)

/**
 * The ledger finance posts a payment to. Distinct from Paid By, which is the exec's
 * note of who pays. The per-invoice payments these described went in MAIN-118; they
 * are kept for the supplier payments of MAIN-119.
 */
export const LEDGER_OPTIONS = ['Bill accounted', 'NVS 659 Manjunath', 'NVS 2954 Gokilavanan', 'PCN']

export const PAYMENT_METHODS = ['UPI', 'NEFT', 'RTGS', 'IMPS', 'Cash']

/**
 * Bank the payment went out from — required, with a UTR, for every method but
 * cash.
 */
export const BANK_OPTIONS = ['Union Bank of India', 'Kotak Mahindra']
