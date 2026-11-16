import { toDate } from './datetime'

/**
 * Reading the SLA statuses the database stores (MAIN-135). The rules themselves live in
 * refresh_ticket_sla(); nothing here re-judges anything.
 */

// Mirrors is_sla_tracked(): tickets raised before 14 Aug 2026 00:00 IST were never tracked.
export const SLA_TRACKING_START = new Date('2026-08-13T18:30:00Z')

export function isSlaTracked(raisedAt) {
    const d = toDate(raisedAt)
    return !!d && d >= SLA_TRACKING_START
}

/** Why a ticket's Turnaround status is Not applicable. */
export function notApplicableReason(ticket) {
    if (!isSlaTracked(ticket.created_at)) return 'Raised before SLA tracking started (14 Aug 2026)'
    if (ticket.status === 'Rejected') return 'Rejected with no issues'
    return 'No issues yet'
}

/**
 * A ticket's finish: the latest activity complete time among its issues, once every issue
 * is Done. Null while any issue is unfinished.
 */
export function ticketFinishedAt(issues) {
    if (!issues?.length || issues.some(i => i.status !== 'Done')) return null
    return issues.reduce((latest, i) => {
        const d = toDate(i.completed_at)
        return d && (!latest || d > latest) ? d : latest
    }, null)
}

export const SLA_STATUS_LABELS = {
    Pending: 'Pending',
    Adhered: 'Adhered',
    Violated: 'Violated',
    NA: 'Not applicable',
}

export const SLA_STATUS_STYLES = {
    Pending: 'bg-blue-50 text-blue-700 border-blue-200',
    Adhered: 'bg-green-50 text-green-700 border-green-200',
    Violated: 'bg-red-50 text-red-700 border-red-200',
    NA: 'bg-gray-50 text-gray-500 border-gray-200',
}
