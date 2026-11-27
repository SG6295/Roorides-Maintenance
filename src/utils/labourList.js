import { analyticsHref } from './analyticsDrill'
import { round2 } from './labourReport'
import { formatHours } from './labour'

/**
 * The Labour list (MAIN-176): one row per person per work item, from get_labour_list —
 * the same rows Analytics › Labour utilisation adds up (labour_report_rows).
 *
 * A row: { id, issue_id, completed_on (null = not yet Done), done, attributed,
 *          technician, technician_id, technician_employee_id, trade, hours,
 *          people_on_item, item_hours, issue_number, category, description,
 *          job_card_number, vehicle_number, ticket_number, site }
 */

export const TRADE_LABELS = { mechanic: 'Mechanic', electrician: 'Electrician' }

/** "Nobody recorded", "1 person", "3 people · 15.0 h". */
export function peopleLabel(people, itemHours) {
    const n = Number(people) || 0
    if (n === 0) return 'Nobody recorded'
    if (n === 1) return '1 person'
    return `${n} people · ${formatHours(round2(parseFloat(itemHours) || 0))} h`
}

/** The People on item filter's words for each value the database lists. */
export function peopleValueLabel(v) {
    const n = Number(v) || 0
    return n === 0 ? 'Nobody recorded' : n === 1 ? '1 person' : `${n} people`
}

/**
 * Whether each row gets the alternate shade: rows of the same work item share one, and the
 * shade changes whenever the work item does.
 */
export function itemShades(rows) {
    let shaded = false
    let prev
    return (rows || []).map((r, i) => {
        if (i > 0 && r.issue_id !== prev) shaded = !shaded
        prev = r.issue_id
        return shaded
    })
}

/** The tiles' shortcuts, as People on item filters. */
export const PEOPLE_SHORTCUTS = {
    many: { min: '2' },
    one: { values: ['1'] },
    nobody: { values: ['0'] },
}

/** Which shortcut a People on item filter is, if any. */
export function activeShortcut(spec) {
    if (!spec) return null
    if (spec.min === '2' && !spec.max && !spec.values) return 'many'
    if (Array.isArray(spec.values) && spec.values.length === 1 && !spec.min && !spec.max) {
        if (spec.values[0] === '1') return 'one'
        if (spec.values[0] === '0') return 'nobody'
    }
    return null
}

/**
 * The address a Labour utilisation figure opens: the Labour list with the report's period,
 * sites, trade and technician, narrowed to what was clicked.
 *
 * @param {{ start: string, end: string }} dateRange   the report's period
 * @param {{ sites?: string[], trade?: string, technicianId?: string }} choices  its filters
 * @param {{ technician_id?: string, completed_on?: string, site?: string, attributed?: boolean }} clicked
 */
export function labourHref(dateRange, { sites = [], trade = '', technicianId = '' } = {}, clicked = {}) {
    const where = {}
    if (trade) where.technician_role = trade
    if (technicianId) where.technician_id = technicianId
    const { site, ...rest } = clicked
    for (const [k, v] of Object.entries(rest)) {
        if (v !== undefined && v !== null && v !== '') where[k] = v
    }
    // A clicked site becomes the selection's sites (the address's an.site): it is one of the
    // sites already chosen, so the rows are the same, and the strip reads "site TSB".
    return analyticsHref('labour', { from: dateRange.start, to: dateRange.end, sites: site ? [site] : sites }, where)
}

/** Export rows, in the list's column order. */
export function buildLabourExportRows(rows) {
    return (rows || []).map(r => ({
        'Activity Complete': r.completed_on || 'Not yet done',
        'Technician': r.technician || '',
        'Employee ID': r.technician_employee_id || '',
        'Trade': TRADE_LABELS[r.trade] || r.trade || '',
        'Hours': parseFloat(r.hours) || 0,
        'People on Item': Number(r.people_on_item) || 0,
        'Item Hours': parseFloat(r.item_hours) || 0,
        'Work Item': r.issue_number || '',
        'Category': r.category || '',
        'Description': r.description || '',
        'Job Card': r.job_card_number ?? '',
        'Vehicle': r.vehicle_number || '',
        'Ticket': r.ticket_number ?? '',
        'Site': r.site || '',
    }))
}
