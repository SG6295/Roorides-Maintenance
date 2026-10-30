import * as XLSX from 'xlsx'
import { format, parseISO } from 'date-fns'
import { ROLE_LABELS } from '../constants/userRoles'

/**
 * Labour utilisation as .xlsx (MAIN-117): the technician × day grid as shown, and every
 * row behind the page — including unattributed hours, which the grid leaves out.
 * Both come from what the page already holds, so the file cannot disagree with the screen.
 */
export function exportLabourToExcel({ grid, days, rows, dateRange }) {
    const header = ['Technician', 'Trade', ...days.map(d => format(parseISO(d), 'dd MMM')), 'Total']
    const gridRows = grid.technicians.map(t => [
        t.name, ROLE_LABELS[t.role] || t.role || '', ...t.cells.map(c => c.hours || ''), t.total,
    ])
    const totals = ['Day total', '', ...grid.dayTotals.map(h => h || ''), grid.grandTotal]

    const detail = rows.map(r => ({
        'Completed On': r.completed_on || 'Not yet done',
        'Technician': r.attributed ? (r.technician_name || '') : 'Unattributed',
        'Trade': r.attributed ? (ROLE_LABELS[r.technician_role] || r.technician_role || '') : '',
        'Hours': parseFloat(r.hours) || 0,
        'Site': r.site || '',
        'Vehicle': r.vehicle_number || '',
        'Job Card': r.job_card_number,
        'Work Item': r.issue_number || '',
        'Description': r.description || '',
        'Category': r.category || '',
    }))

    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([header, ...gridRows, totals]), 'Per day')
    XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(detail), 'All rows')
    XLSX.writeFile(wb, `labour_${dateRange.start}_to_${dateRange.end}.xlsx`)
}
