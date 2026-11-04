import * as XLSX from 'xlsx'
import { describeLine, describeAdvanceLine, invoiceOwner, LINE_TAGS } from './supplierLedger'
import { formatAs } from './datetime'

/**
 * Supplier ledger exports (MAIN-119), built from what the page already holds so the
 * file cannot disagree with the screen.
 */

export function exportSupplierBalances(rows, { thisRun, nextRun, today }) {
    const sheet = rows.map(r => ({
        'Supplier':                     r.entity_name,
        'Credit days':                  r.credit_days ?? 0,
        'Outstanding':                  r.outstanding,
        'Overdue':                      r.overdue,
        [`Due Wed ${thisRun}`]:         r.due_this_wednesday,
        [`Due Wed ${nextRun}`]:         r.due_next_wednesday,
        'Later':                        r.later,
        'Last payment':                 r.last_payment_on || '',
        'Last reconciled':              r.last_reconciled_on || '',
        'Invoices awaiting acceptance': r.awaiting_acceptance,
    }))
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(sheet), 'Suppliers')
    XLSX.writeFile(wb, `supplier_ledger_${today}.xlsx`)
}

function statementSheet(lines, describe) {
    return lines.map(l => {
        const { title, sub } = describe(l)
        const owner = invoiceOwner(l)?.label ?? ''
        const amount = Number(l.amount)
        return {
            'Entered':  formatAs(l.entry_at, 'dd MMM yyyy HH:mm', ''),
            'Type':     LINE_TAGS[l.kind]?.label ?? l.kind,
            'Entry':    [title, owner].filter(Boolean).join(' · '),
            'Detail':   sub,
            'Owed':     amount > 0 ? amount : '',
            'Paid':     amount < 0 ? -amount : '',
            'Counts':   l.counts ? 'Yes' : 'No',
            'Balance':  Number(l.balance),
        }
    })
}

function write(sheet, name, file) {
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(sheet), name)
    XLSX.writeFile(wb, file)
}

const safe = s => s.replace(/[^A-Za-z0-9]+/g, '_').replace(/^_|_$/g, '')

export function exportSupplierStatement(supplierName, lines, today) {
    write(statementSheet(lines, describeLine), 'Statement', `ledger_${safe(supplierName)}_${today}.xlsx`)
}

export function exportAdvanceStatement(personName, lines, today) {
    write(statementSheet(lines, describeAdvanceLine), 'Advances', `advances_${safe(personName)}_${today}.xlsx`)
}
