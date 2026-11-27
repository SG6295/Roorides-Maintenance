/**
 * Analytics drill-down (MAIN-152): a number on Analytics › SLA & tickets opens, in a new
 * tab, the Tickets or Issues list showing exactly the records it counted.
 *
 * The link carries the Analytics selection — its period, sites, and the bucket that was
 * clicked — as `an.*` parameters:
 *
 *   /tickets?an.from=2026-01-01&an.to=2026-11-30&an.site=BWIS&an.acceptance=Violated
 *
 * The list sends it to the database as `p_query.analytics = { from, to, sites, where }`,
 * and list_query picks the rows with analytics_ticket_rows / analytics_issue_rows — the
 * same functions get_maintenance_stats counts — so the list's total equals the number.
 * While it is there the Analytics period replaces the list's own date range.
 *
 * `where` keys are the bucket columns of those functions:
 *   tickets: status, acceptance, completion, job_card_type, overdue
 *   issues:  severity, category, job_card_type, rating, rating_pending, rated
 *   labour:  completed_on, site, technician_id, technician_role, attributed
 *            (MAIN-176, analytics_labour_rows — Analytics › Labour utilisation; its
 *            trade and technician choices travel as technician_role / technician_id)
 */
import { format, parseISO } from 'date-fns'

const PREFIX = 'an.'
const SELECTION_KEYS = ['from', 'to', 'site']

/** @typedef {{ from: string, to: string, sites: string[], where: Record<string, string> }} Drill */

/** The drill-down in an address, or undefined when the list was not opened from Analytics. */
export function parseAnalytics(params) {
    let found = false
    const drill = { from: '', to: '', sites: [], where: {} }
    for (const [name, raw] of params.entries()) {
        if (!name.startsWith(PREFIX)) continue
        const key = name.slice(PREFIX.length)
        if (!key) continue
        found = true
        if (key === 'from' || key === 'to') drill[key] = raw
        else if (key === 'site') { if (raw) drill.sites.push(raw) }
        else drill.where[key] = raw
    }
    return found ? drill : undefined
}

/** Append a drill-down to URL parameters. */
export function appendAnalytics(params, drill) {
    if (!drill) return params
    // Always written, even empty, so a drill with no period (Currently Overdue) still reads as one.
    params.set(`${PREFIX}from`, drill.from || '')
    params.set(`${PREFIX}to`, drill.to || '')
    for (const s of drill.sites || []) params.append(`${PREFIX}site`, s)
    for (const [k, v] of Object.entries(drill.where || {})) {
        if (SELECTION_KEYS.includes(k)) continue
        params.set(`${PREFIX}${k}`, String(v))
    }
    return params
}

/** The database's p_query.analytics. */
export function analyticsToServer(drill) {
    if (!drill) return undefined
    return {
        from: drill.from || null,
        to: drill.to || null,
        sites: drill.sites || [],
        where: { ...(drill.where || {}) },
    }
}

/**
 * The address a number opens.
 *
 * @param {'tickets'|'issues'|'labour'} list
 * @param {{ from?: string, to?: string, sites?: string[] }} selection the Analytics filters;
 *        leave out from/to for a figure that ignores the period (Currently Overdue)
 * @param {Record<string, string|boolean>} where the bucket clicked ({} = everything)
 */
export function analyticsHref(list, selection, where = {}) {
    const params = appendAnalytics(new URLSearchParams(), {
        from: selection.from || '',
        to: selection.to || '',
        sites: selection.sites || [],
        where,
    })
    return `/${list}?${params.toString()}`
}

export const ACCEPTANCE_LABELS = { Adhered: 'On time', Violated: 'Late', NA: 'Not applicable', Pending: 'Awaiting issue' }
export const COMPLETION_LABELS = { Adhered: 'Adhered', Violated: 'Violated', NA: 'Not applicable', Pending: 'Pending' }
/** The ticket's job card type on Analytics (a ticket with no issues has its own). */
export const TICKET_JOB_CARD_TYPE_LABELS = { InHouse: 'In-house', Outsource: 'Outsource', none: 'No job card yet', no_issues: 'No issues' }
/** An issue's job card type, as the list (None) and Analytics (none) spell it. */
export const ISSUE_JOB_CARD_TYPE_LABELS = { InHouse: 'In-house', Outsource: 'Outsource', none: 'No job card yet', None: 'No job card yet' }

const WHERE_TEXT = {
    tickets: {
        status: v => `Status: ${v}`,
        acceptance: v => `Acceptance SLA: ${ACCEPTANCE_LABELS[v] || v}`,
        completion: v => `Completion SLA: ${COMPLETION_LABELS[v] || v}`,
        job_card_type: v => `Job card type: ${TICKET_JOB_CARD_TYPE_LABELS[v] || v}`,
        overdue: v => (v === 'true' ? 'Currently overdue' : 'Not overdue'),
    },
    issues: {
        severity: v => `Severity: ${v}`,
        category: v => `Category: ${v}`,
        job_card_type: v => `Job card type: ${ISSUE_JOB_CARD_TYPE_LABELS[v] || v}`,
        rating: v => `Rating: ${v}`,
        rating_pending: v => (v === 'true' ? 'Rating pending' : 'Rating not pending'),
        rated: v => (v === 'true' ? 'Ratings collected' : 'Not rated'),
    },
    labour: {
        completed_on: v => `Completed ${dayText(v, true)}`,
        site: v => `Site: ${v}`,
        technician_role: v => `Trade: ${TRADE_LABELS[v] || v}`,
        attributed: v => (v === 'true' ? 'Attributed hours' : 'Unattributed hours'),
    },
}

const TRADE_LABELS = { mechanic: 'Mechanic', electrician: 'Electrician' }

function dayText(iso, withYear) {
    try { return format(parseISO(iso), withYear ? 'd MMM yyyy' : 'd MMM') } catch { return iso }
}

/** "1 Jan – 30 Nov 2026", or null with no period. */
export function periodText(from, to) {
    if (!from && !to) return null
    if (from && to) {
        const sameYear = from.slice(0, 4) === to.slice(0, 4)
        return `${dayText(from, !sameYear)} – ${dayText(to, true)}`
    }
    return from ? `from ${dayText(from, true)}` : `up to ${dayText(to, true)}`
}

const ALL_TEXT = { tickets: 'All tickets', issues: 'All issues', labour: 'All labour hours' }
// Tickets by the day they were raised, issues by their own Raised day, labour by the
// work item's activity complete day.
const PERIOD_TEXT = { tickets: 'tickets raised', issues: 'issues raised', labour: 'completed' }

/**
 * The parts of the "From Analytics" strip, e.g.
 * ["Acceptance SLA: Late", "tickets raised 1 Jan – 30 Nov 2026", "sites BWIS, KUNS"].
 *
 * `names` turns ids into words: { technician_id: { <uuid>: 'Ravi Kumar' } }.
 */
export function describeDrill(list, drill, names = {}) {
    if (!drill) return []
    const text = WHERE_TEXT[list] || {}
    const parts = Object.entries(drill.where || {}).map(([k, v]) => {
        if (names[k]) return names[k][v] || 'Technician'
        return text[k] ? text[k](String(v)) : `${k}: ${v}`
    })
    if (parts.length === 0) parts.push(ALL_TEXT[list] || 'All')
    const period = periodText(drill.from, drill.to)
    // A single day already names the period.
    if (period && !('completed_on' in (drill.where || {}))) parts.push(`${PERIOD_TEXT[list] || ''} ${period}`.trim())
    const sites = drill.sites || []
    parts.push(sites.length === 0 ? 'all sites'
        : sites.length <= 3 ? `${sites.length === 1 ? 'site' : 'sites'} ${sites.join(', ')}`
        : `sites ${sites.slice(0, 3).join(', ')} +${sites.length - 3} more`)
    return parts
}
