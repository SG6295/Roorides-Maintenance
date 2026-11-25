import * as XLSX from 'xlsx'
import { describeEntry, ENTRY_TAGS, GST_STATUSES, isAdjustment, lineAmount } from './companyLedger'
import { companyLabel } from '../constants/vehicleCompanies'
import { formatAs } from './datetime'

/**
 * A company ledger export (MAIN-156), built from the lines the page shows so the file
 * cannot disagree with the screen.
 */
export function exportCompanyLedger(company, lines, today) {
    const sheet = lines.map(l => {
        const { title, sub, link } = describeEntry(l, company)
        const adj = isAdjustment(l)
        return {
            'Entered':                formatAs(l.entry_at, 'dd MMM yyyy HH:mm', ''),
            'Type':                   ENTRY_TAGS[l.kind]?.label ?? l.kind,
            'Entry':                  [title, link?.label].filter(Boolean).join(' · '),
            'Detail':                 sub,
            'Amount (incl. GST)':     lineAmount(l),
            'GST':                    adj ? '' : l.gst == null ? 'Not recorded' : Number(l.gst),  // a spare transfer's is signed
            'GST status':             adj ? '' : GST_STATUSES[l.gst_status]?.label ?? l.gst_status,
            'Spent to date':          Number(l.spent_to_date),
            'Owed between companies': Number(l.owed_balance),
        }
    })
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(sheet), 'Ledger')
    const name = companyLabel(company).replace(/[^A-Za-z0-9]+/g, '_').replace(/^_|_$/g, '')
    XLSX.writeFile(wb, `company_ledger_${name}_${today}.xlsx`)
}
