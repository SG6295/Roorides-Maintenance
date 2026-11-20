/**
 * The supplier ledger (MAIN-119). Payment fields reuse PAYMENT_METHODS and BANK_OPTIONS
 * from outsourceInvoices.js.
 */

/**
 * Who pays suppliers upfront and is repaid by accounts, in display order. `ledger` is
 * both their Paid By value and their repayment ledger. NVS Maintenance account is
 * repaid like the people (MAIN-122); only Accounts is company money. Mirrors the
 * database's advance_people() — keep in step.
 */
export const ADVANCE_PEOPLE = [
    { ledger: 'NVS 659 Manjunath',       name: 'Manjunath' },
    { ledger: 'NVS 2954 Gokilavanan',    name: 'Gokilavanan' },
    { ledger: 'PCN',                     name: 'Nithin (Petty Cash)' },
    { ledger: 'NVS Maintenance account', name: 'NVS Maintenance account' },
]

/** "Manjunath, Gokilavanan, … and NVS Maintenance account" — `or` for "… or …". */
export function advancePeopleNames(joiner = 'and') {
    return new Intl.ListFormat('en', { type: joiner === 'or' ? 'disjunction' : 'conjunction' })
        .format(ADVANCE_PEOPLE.map(p => p.name))
}

/** A person's short name from their ledger, or the Paid By value as it is. */
export function personName(ledger) {
    return ADVANCE_PEOPLE.find(p => p.ledger === ledger)?.name ?? ledger
}

/** Mirrors supplier_ledger_adjustments_source_check. */
export const RECONCILE_SOURCES = ['Tally', 'Vendor statement']

/** Who may record payments, reconcile and set credit days; exec reads only. */
export const LEDGER_WRITE_ROLES = ['finance', 'super_admin']
export const LEDGER_READ_ROLES = ['finance', 'super_admin', 'maintenance_exec']
