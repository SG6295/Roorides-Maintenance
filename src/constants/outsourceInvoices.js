/**
 * Who pays an outsourced repair invoice — the "Paid By" choice on the job card's
 * invoice form, and the Paid By filter on Outsource Invoices. The people's entries are
 * their repayment ledgers' names (MAIN-119), so an advance they paid matches its
 * repayment with no mapping; Accounts and NVS Maintenance account are company money.
 *
 * Mirrors the outsource_invoices_paid_by_check constraint — keep in step.
 */
export const PAID_BY_OPTIONS = ['Accounts', 'NVS Maintenance account', 'NVS 659 Manjunath', 'NVS 2954 Gokilavanan', 'PCN']

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
    'New (invoice pending)',
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
    'New (invoice pending)':       ['Hold', 'Reject'],
    'Hold':                        ['New', 'New (invoice pending)', 'Reject', 'Accepted'],
    'Accepted':                    ['Hold', 'Reject', 'GST reconciled & closed', 'GST not applicable & closed'],
    'Reject':                      [],
    'GST reconciled & closed':     [],
    'GST not applicable & closed': [],
}

/**
 * True for a purchase invoice whose file has not been uploaded yet (MAIN-129). Finance
 * cannot accept it; uploading the file in Edit Purchase moves it to New.
 */
export const isInvoiceFilePending = invoice =>
    !!invoice?.purchase_invoice_id && !invoice.purchase_invoice?.invoice_file_url

/**
 * The moves finance may make from this invoice's status. A purchase invoice waiting for
 * its file can only go back to New (invoice pending), not New or Accepted; every other
 * invoice never goes to it. Mirrors guard_outsource_invoice_status_owners.
 */
export function financeStatusMoves(invoice) {
    const moves = FINANCE_STATUS_MOVES[invoice.finance_payment_status] ?? []
    return isInvoiceFilePending(invoice)
        ? moves.filter(m => m !== 'New' && m !== 'Accepted')
        : moves.filter(m => m !== 'New (invoice pending)')
}

/**
 * Once finance has accepted an invoice it is in the supplier ledger, so the exec can no
 * longer change it, reopen its job card or cancel its multi-vehicle invoice. Finance
 * moving it back to Hold, or on to Reject, lifts the lock.
 */
export const FINANCE_LOCKED_STATUSES = ['Accepted', 'GST reconciled & closed', 'GST not applicable & closed']

export const isLockedByFinance = invoice => FINANCE_LOCKED_STATUSES.includes(invoice?.finance_payment_status)

/** How a supplier payment or an advance repayment was made (MAIN-119). */
export const PAYMENT_METHODS = ['UPI', 'NEFT', 'RTGS', 'IMPS', 'Cash']

/**
 * Bank the payment went out from — required, with a UTR, for every method but
 * cash. Mirrors the supplier_payments and advance_repayments bank checks.
 */
export const BANK_OPTIONS = ['Union Bank of India', 'Kotak Mahindra']
