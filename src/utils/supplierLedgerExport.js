import * as XLSX from 'xlsx'
import { describeLine, describeAdvanceLine, invoiceOwner, LINE_TAGS } from './supplierLedger'
import { formatAs } from './datetime'
import { companyShortLabel } from '../constants/vehicleCompanies'

/**
 * Supplier ledger exports (MAIN-119), built from what the page already holds so the
 * file cannot disagree with the screen. Each is one company's (MAIN-162), named in the file.
 */

const co = company => safe(companyShortLabel(company))

export function exportSupplierBalances(rows, { company, thisRun, nextRun, today }) {
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
    XLSX.writeFile(wb, `supplier_ledger_${co(company)}_${today}.xlsx`)
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

export function exportSupplierStatement(supplierName, company, lines, today) {
    write(statementSheet(lines, describeLine), 'Statement', `ledger_${safe(supplierName)}_${co(company)}_${today}.xlsx`)
}

export function exportAdvanceStatement(personName, company, lines, today) {
    write(statementSheet(lines, describeAdvanceLine), 'Advances', `advances_${safe(personName)}_${co(company)}_${today}.xlsx`)
}
