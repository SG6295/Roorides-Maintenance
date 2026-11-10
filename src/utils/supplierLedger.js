import { formatBatchNumber } from './batchNumber'
import { formatDate, formatAs } from './datetime'
import { personName } from '../constants/supplierLedger'

/**
 * How ledger lines read (MAIN-119). Supplier lines come from get_supplier_statement
 * (invoice | advance | payment | cancelled | adjustment | reversed); a person's from
 * get_advance_statement (advance | repayment | cancelled). `detail` carries each kind's
 * own fields. Lines are in recording order, by `entry_at`.
 */
export const LINE_TAGS = {
    invoice:    { label: 'Invoice',    className: 'bg-blue-100 text-blue-800' },
    advance:    { label: 'Advance',    className: 'bg-violet-100 text-violet-800' },
    payment:    { label: 'Payment',    className: 'bg-green-100 text-green-800' },
    repayment:  { label: 'Repayment',  className: 'bg-green-100 text-green-800' },
    cancelled:  { label: 'Cancelled',  className: 'bg-red-100 text-red-800' },
    adjustment: { label: 'Adjustment', className: 'bg-orange-100 text-orange-800' },
    reversed:   { label: 'Reversed',   className: 'bg-red-100 text-red-800' },
}

/** Cancelled payments and reversed adjustments: shown, struck through, out of every total. */
export const isVoided = line => line.kind === 'cancelled' || line.kind === 'reversed'

const rupees = v => `₹${Number(v ?? 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

/** The job card, multi-vehicle invoice or refurbishment purchase a line belongs to. */
export function invoiceOwner(line) {
    if (line.detail?.purchase_invoice_id) return { label: 'Refurbishment', purchaseInvoiceId: line.detail.purchase_invoice_id }
    if (line.job_card_number != null) return { label: `Job card #${line.job_card_number}`, jobCardNumber: line.job_card_number }
    if (line.batch_number != null) return { label: formatBatchNumber(line.batch_number), batchNumber: line.batch_number }
    return null
}

function trail(d) {
    return [d.payment_method, d.bank].filter(Boolean).join(' · ')
}

/**
 * Where an invoice's approved value goes: to the supplier, and any advance — to repay
 * the person who paid it, or already paid from a company account.
 */
export function invoiceSplit(d) {
    const advance = Number(d.advance ?? 0)
    if (!(advance > 0)) return `${rupees(d.to_supplier)} to the supplier`
    const advancePart = d.advance_by_person
        ? `${rupees(advance)} advance to repay ${personName(d.paid_by)}`
        : `${rupees(advance)} advance paid from ${d.paid_by}`
    return `${rupees(d.to_supplier)} to the supplier + ${advancePart}`
}

/** { title, sub } for a supplier statement line; the owner link is added by the page. */
export function describeLine(line) {
    const d = line.detail ?? {}
    switch (line.kind) {
        case 'invoice':
            return {
                title: line.invoice_no || 'Invoice',
                sub: `Reached finance ${formatDate(d.submitted_on)} · due ${formatDate(line.due_date)} · ${invoiceSplit(d)}`,
            }
        case 'advance':
            return {
                title: `Advance – ${personName(d.paid_by)}`,
                sub: d.advance_by_person
                    ? `Paid to the vendor upfront on ${line.invoice_no || 'the invoice'}; repaid to ${personName(d.paid_by)} under Advances to repay`
                    : `Paid to the vendor upfront on ${line.invoice_no || 'the invoice'} from ${d.paid_by}`,
            }
        case 'payment':
            return {
                title: `Bill accounted · ${trail(d)}`,
                sub: [
                    `Paid ${formatDate(d.paid_on)}`,
                    Number(d.tds_amount) > 0 ? `${rupees(d.amount_paid)} + ${rupees(d.tds_amount)} TDS` : null,
                    d.utr && `UTR ${d.utr}`,
                    d.recorded_by && `recorded by ${d.recorded_by}`,
                ].filter(Boolean).join(' · '),
            }
        case 'cancelled':
            return {
                title: `Bill accounted · ${trail(d)} · ${rupees(Number(d.amount_paid) + Number(d.tds_amount))}`,
                sub: `Cancelled${d.cancelled_by ? ` by ${d.cancelled_by}` : ''}: ${d.cancel_reason ?? ''}`,
            }
        case 'adjustment':
        case 'reversed': {
            const base = `As of ${formatDate(d.as_of)} · app showed ${rupees(d.system_balance)} · confirmed ${rupees(d.confirmed_balance)} · ${d.reason}${d.created_by ? ` · by ${d.created_by}` : ''}`
            return {
                title: `Reconciled against ${d.confirmed_against === 'Tally' ? 'Tally' : "the vendor's statement"}`,
                sub: line.kind === 'reversed'
                    ? `${base}. Reversed${d.reversed_by ? ` by ${d.reversed_by}` : ''}: ${d.reverse_reason ?? ''}`
                    : base,
            }
        }
        default:
            return { title: line.kind, sub: '' }
    }
}

/** { title, sub } for a line of a person's advances statement. */
export function describeAdvanceLine(line) {
    const d = line.detail ?? {}
    switch (line.kind) {
        case 'advance':
            return {
                title: `Advance on ${line.invoice_no || 'invoice'} · ${d.supplier ?? ''}`,
                sub: `Reached finance ${formatDate(line.due_date)} · approved ${rupees(d.approved)}, ${rupees(d.to_supplier)} to the supplier`,
            }
        case 'repayment':
            return {
                title: `Repaid · ${trail(d)}`,
                sub: [`Paid ${formatDate(d.paid_on)}`, d.utr && `UTR ${d.utr}`, d.recorded_by && `recorded by ${d.recorded_by}`].filter(Boolean).join(' · '),
            }
        case 'cancelled':
            return {
                title: `Repaid · ${trail(d)}`,
                sub: `Cancelled${d.cancelled_by ? ` by ${d.cancelled_by}` : ''}: ${d.cancel_reason ?? ''}`,
            }
        default:
            return { title: line.kind, sub: '' }
    }
}

/** The local calendar day a line was recorded on. */
export const entryDay = line => formatAs(line.entry_at, 'yyyy-MM-dd', '')

/**
 * The app's balance at the end of a day — everything recorded up to then — from the
 * statement's running balance. The reconcile form shows it before saving; the database
 * recomputes it when posting.
 */
export function balanceAsOf(lines, isoDate) {
    let balance = 0
    for (const l of lines) {
        if (entryDay(l) > isoDate) break
        balance = Number(l.balance)
    }
    return balance
}
