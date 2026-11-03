import { formatBatchNumber } from './batchNumber'
import { formatDate } from './datetime'

/**
 * How one statement line reads (MAIN-119). `line` is a row of get_supplier_statement:
 * kind is invoice | advance | payment | reimbursement | cancelled | adjustment, and
 * `detail` carries the kind's own fields.
 */
export const LINE_TAGS = {
    invoice:       { label: 'Invoice',       className: 'bg-blue-100 text-blue-800' },
    advance:       { label: 'Advance',       className: 'bg-violet-100 text-violet-800' },
    payment:       { label: 'Payment',       className: 'bg-green-100 text-green-800' },
    reimbursement: { label: 'Reimbursement', className: 'bg-gray-100 text-gray-700' },
    cancelled:     { label: 'Cancelled',     className: 'bg-red-100 text-red-800' },
    adjustment:    { label: 'Adjustment',    className: 'bg-orange-100 text-orange-800' },
}

const rupees = v => `₹${Number(v ?? 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

/** The job card or multi-vehicle invoice an invoice line belongs to. */
export function invoiceOwner(line) {
    if (line.job_card_number != null) return { label: `Job card #${line.job_card_number}`, jobCardNumber: line.job_card_number }
    if (line.batch_number != null) return { label: formatBatchNumber(line.batch_number), batchNumber: line.batch_number }
    return null
}

function paymentTrail(d) {
    return [d.ledger, d.payment_method, d.bank].filter(Boolean).join(' · ')
}

function paidParts(d) {
    return Number(d.tds_amount) > 0
        ? `${rupees(d.amount_paid)} paid + ${rupees(d.tds_amount)} TDS`
        : `${rupees(d.amount_paid)} paid`
}

/** { title, sub } for a line; the invoice's owner link is added by the page. */
export function describeLine(line) {
    const d = line.detail ?? {}
    switch (line.kind) {
        case 'invoice':
            return {
                title: line.invoice_no || 'Invoice',
                sub: `Accepted by finance · due ${formatDate(line.due_date)}`,
            }
        case 'advance':
            return {
                title: `Advance – ${d.paid_by || 'unknown'}`,
                sub: `Paid to the vendor upfront on ${line.invoice_no || 'the invoice'}`,
            }
        case 'payment':
            return {
                title: paymentTrail(d),
                sub: [paidParts(d), d.utr && `UTR ${d.utr}`, d.recorded_by && `recorded by ${d.recorded_by}`].filter(Boolean).join(' · '),
            }
        case 'reimbursement':
            return {
                title: paymentTrail(d),
                sub: `${paidParts(d)} back to ${d.ledger} for an advance. Not counted in this supplier's balance.`,
            }
        case 'cancelled':
            return {
                title: `${paymentTrail(d)} · ${rupees(Number(d.amount_paid) + Number(d.tds_amount))}`,
                sub: `Cancelled${d.cancelled_by ? ` by ${d.cancelled_by}` : ''}: ${d.cancel_reason ?? ''}`,
            }
        case 'adjustment':
            return {
                title: `Reconciled against ${d.confirmed_against === 'Tally' ? 'Tally' : "the vendor's statement"}`,
                sub: `App showed ${rupees(d.system_balance)} · confirmed ${rupees(d.confirmed_balance)} · ${d.reason}${d.created_by ? ` · by ${d.created_by}` : ''}`,
            }
        default:
            return { title: line.kind, sub: '' }
    }
}

/**
 * The app's balance at the end of a day, from the statement's running balance — what
 * the reconcile form shows before saving. The database recomputes it when posting.
 */
export function balanceAsOf(lines, isoDate) {
    let balance = 0
    for (const l of lines) {
        if (l.entry_date > isoDate) break
        balance = Number(l.balance)
    }
    return balance
}
