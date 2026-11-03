import * as XLSX from 'xlsx'
import { describeLine, invoiceOwner, LINE_TAGS } from './supplierLedger'

/**
 * Supplier ledger exports (MAIN-119), built from what the page already holds so the
 * file cannot disagree with the screen.
 */

export function exportSupplierBalances(rows, { thisRun, nextRun, today }) {
    const sheet = rows.map(r => ({
        'Supplier':                   r.entity_name,
        'Credit days':                r.credit_days ?? 0,
        'Outstanding':                r.outstanding,
        'Overdue':                    r.overdue,
        [`Due Wed ${thisRun}`]:       r.due_this_wednesday,
        [`Due Wed ${nextRun}`]:       r.due_next_wednesday,
        'Later':                      r.later,
        'Last payment':               r.last_payment_on || '',
        'Last reconciled':            r.last_reconciled_on || '',
        'Invoices awaiting acceptance': r.awaiting_acceptance,
    }))
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(sheet), 'Suppliers')
    XLSX.writeFile(wb, `supplier_ledger_${today}.xlsx`)
}

export function exportSupplierStatement(supplierName, lines, today) {
    const sheet = lines.map(l => {
        const { title, sub } = describeLine(l)
        const owner = l.kind === 'invoice' || l.kind === 'advance' ? invoiceOwner(l)?.label : ''
        const amount = Number(l.amount)
        return {
            'Date':     l.entry_date,
            'Type':     LINE_TAGS[l.kind]?.label ?? l.kind,
            'Entry':    [title, owner].filter(Boolean).join(' · '),
            'Detail':   sub,
            'Owed':     amount > 0 ? amount : '',
            'Paid':     amount < 0 ? -amount : '',
            'Counts':   l.counts ? 'Yes' : 'No',
            'Balance':  Number(l.balance),
        }
    })
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(sheet), 'Statement')
    const safe = supplierName.replace(/[^A-Za-z0-9]+/g, '_').replace(/^_|_$/g, '')
    XLSX.writeFile(wb, `ledger_${safe}_${today}.xlsx`)
}
