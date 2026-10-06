import * as XLSX from 'xlsx'
import { supabase } from '../lib/supabase'
import { toDate } from './datetime'

const CREATED_AT_COLUMN = 'Ticket Creation Time'
const DATE_FORMAT = 'dd-mmm-yyyy hh:mm'

// Excel's day zero. Its serial dates count days from here, with the time as the fraction.
const EXCEL_EPOCH_MS = Date.UTC(1899, 11, 30)

/**
 * An instant as an Excel serial date, in the viewer's local wall-clock time.
 *
 * Not left to SheetJS: given a Date, it converts with the zone's *1899* offset, which for
 * India is +5:21:10 rather than +5:30, so every time lands ten seconds late — invisible
 * under a minutes-only format, but wrong for anyone who sorts or filters on it in Excel.
 */
function toExcelSerial(value) {
    const d = toDate(value)
    if (!d) return null
    const localMs = d.getTime() - d.getTimezoneOffset() * 60_000
    return (localMs - EXCEL_EPOCH_MS) / 86_400_000
}

/**
 * Tickets as export rows, columns in the order MAIN-84 specifies.
 *
 * @param {object[]} tickets
 * @param {Record<string, string>} emailByUserId
 */
export function buildTicketExportRows(tickets, emailByUserId) {
    return tickets.map(ticket => ({
        'Ticket ID': ticket.ticket_number,
        [CREATED_AT_COLUMN]: toExcelSerial(ticket.created_at),
        'Email Address of Creator': emailByUserId[ticket.created_by_user_id] ?? '',
        'Site': ticket.site,
        'Vehicle Number': ticket.vehicle_number,
        'Status': ticket.status,
    }))
}

/**
 * The export rows as a worksheet, with the creation time formatted as a date-time.
 */
export function buildTicketWorksheet(rows) {
    const ws = XLSX.utils.json_to_sheet(rows)
    if (!ws['!ref']) return ws

    const headers = Object.keys(rows[0] ?? {})
    const col = headers.indexOf(CREATED_AT_COLUMN)
    if (col === -1) return ws

    const range = XLSX.utils.decode_range(ws['!ref'])
    for (let r = range.s.r + 1; r <= range.e.r; r++) {
        const cell = ws[XLSX.utils.encode_cell({ r, c: col })]
        if (cell && cell.t === 'n') cell.z = DATE_FORMAT
    }
    return ws
}

/**
 * Download `tickets` — the list exactly as the Tickets page shows it — as an .xlsx file.
 *
 * The rows are the page's own filtered list rather than a second query, so the file
 * cannot disagree with the screen. Only the creators' emails are fetched, one lookup
 * for the handful of distinct creators.
 *
 * @param {object[]} tickets
 * @param {{ start: string, end: string }} dateRange
 */
export async function exportTicketsToExcel(tickets, dateRange) {
    const creatorIds = [...new Set(tickets.map(t => t.created_by_user_id).filter(Boolean))]

    let emailByUserId = {}
    if (creatorIds.length > 0) {
        const { data, error } = await supabase
            .from('users')
            .select('id, email')
            .in('id', creatorIds)
        if (error) throw error
        emailByUserId = Object.fromEntries((data || []).map(u => [u.id, u.email]))
    }

    const ws = buildTicketWorksheet(buildTicketExportRows(tickets, emailByUserId))
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, ws, 'Tickets')
    XLSX.writeFile(wb, `tickets_${dateRange.start}_to_${dateRange.end}.xlsx`)
}
