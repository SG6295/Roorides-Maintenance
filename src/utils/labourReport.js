import { eachDayOfInterval, parseISO, format, differenceInCalendarDays } from 'date-fns'

/**
 * Labour utilisation report (MAIN-117) — pure functions over the rows that
 * get_labour_report returns. Each row is one piece of labour on an in-house work item:
 *
 *   attributed = true   one technician's hours on one work item; completed_on is NULL
 *                       while the item is not yet Done
 *   attributed = false  pre-MAIN-116 hours with nobody attached
 *
 * Everything is placed by the work item's activity complete date.
 */

/** The per-day grid has a column per day; past this it stops being readable. */
export const MAX_GRID_DAYS = 92

/** Colour bands for a day's hours: 0 / ≤2 / 2–4 / 4–6 / 6–8 / 8+. */
export const HOUR_BANDS = [
    { label: '0', className: 'bg-gray-100 text-gray-400' },
    { label: '≤2', className: 'bg-blue-100 text-blue-900' },
    { label: '2–4', className: 'bg-blue-300 text-blue-950' },
    { label: '4–6', className: 'bg-blue-500 text-white' },
    { label: '6–8', className: 'bg-blue-700 text-white' },
    { label: '8+', className: 'bg-blue-950 text-white' },
]

export function hourBand(hours) {
    if (!(hours > 0)) return 0
    if (hours <= 2) return 1
    if (hours <= 4) return 2
    if (hours <= 6) return 3
    if (hours <= 8) return 4
    return 5
}

// Hours arrive as numeric strings; sums are rounded so 0.1 + 0.2 shows as 0.3.
const num = (v) => parseFloat(v) || 0
export const round2 = (n) => Math.round(n * 100) / 100

/** Every day from start to end inclusive, as "yyyy-MM-dd". */
export function enumerateDays(start, end) {
    if (!start || !end || start > end) return []
    return eachDayOfInterval({ start: parseISO(start), end: parseISO(end) }).map(d => format(d, 'yyyy-MM-dd'))
}

export function dayCount(start, end) {
    if (!start || !end || start > end) return 0
    return differenceInCalendarDays(parseISO(end), parseISO(start)) + 1
}

/**
 * Site filter applies to every row. A trade or technician filter is about people, so it
 * also drops unattributed hours, which have nobody to match.
 */
export function filterRows(rows, { sites = [], trade = '', technicianId = '' } = {}) {
    return (rows || []).filter(r => {
        if (sites.length && !sites.includes(r.site)) return false
        if (trade || technicianId) {
            if (!r.attributed) return false
            if (trade && r.technician_role !== trade) return false
            if (technicianId && r.technician_id !== technicianId) return false
        }
        return true
    })
}

/** Figures for the tiles. `rows` are already filtered. */
export function summarise(rows) {
    const dated = rows.filter(r => r.completed_on)
    const open = rows.filter(r => !r.completed_on)

    const attributed = dated.filter(r => r.attributed)
    const attributedHours = attributed.reduce((s, r) => s + num(r.hours), 0)
    const unattributedHours = dated.filter(r => !r.attributed).reduce((s, r) => s + num(r.hours), 0)
    const totalHours = attributedHours + unattributedHours

    // Average over the days each person actually logged hours, not over a calendar: the
    // workshop works every day of the week, so there is no working-day rule to divide by.
    const personDays = new Set(attributed.map(r => `${r.technician_id}|${r.completed_on}`))
    const technicians = new Set(attributed.map(r => r.technician_id))

    const ranked = rankSites(dated)
    const top = ranked[0]

    return {
        totalHours: round2(totalHours),
        attributedHours: round2(attributedHours),
        unattributedHours: round2(unattributedHours),
        openHours: round2(open.reduce((s, r) => s + num(r.hours), 0)),
        workItems: new Set(dated.map(r => r.issue_id)).size,
        technicianCount: technicians.size,
        avgPerTechnicianDay: personDays.size ? round2(attributedHours / personDays.size) : 0,
        sitesServed: ranked.length,
        topSite: top ? { site: top.site, share: totalHours ? top.hours / totalHours : 0 } : null,
    }
}

/**
 * Technician × day grid, attributed hours only, busiest technician first.
 * Each cell carries the work items behind it for the tooltip.
 */
export function buildGrid(rows, days) {
    const index = new Map(days.map((d, i) => [d, i]))
    const people = new Map()

    for (const r of rows) {
        if (!r.attributed || !r.completed_on || !index.has(r.completed_on)) continue
        if (!people.has(r.technician_id)) {
            people.set(r.technician_id, {
                id: r.technician_id,
                name: r.technician_name || 'Unknown',
                role: r.technician_role,
                cells: days.map(day => ({ day, hours: 0, items: [] })),
                total: 0,
            })
        }
        const person = people.get(r.technician_id)
        const cell = person.cells[index.get(r.completed_on)]
        cell.hours += num(r.hours)
        cell.items.push(`${r.issue_number} ${r.description} — ${round2(num(r.hours))} h`)
        person.total += num(r.hours)
    }

    const technicians = [...people.values()]
        .map(p => ({ ...p, total: round2(p.total), cells: p.cells.map(c => ({ ...c, hours: round2(c.hours) })) }))
        .sort((a, b) => b.total - a.total || a.name.localeCompare(b.name))

    const dayTotals = days.map((_, i) => round2(technicians.reduce((s, p) => s + p.cells[i].hours, 0)))
    const grandTotal = round2(dayTotals.reduce((s, h) => s + h, 0))

    return { technicians, dayTotals, grandTotal }
}

/** Every site with hours, busiest first. `rows` should be dated rows. */
export function rankSites(rows) {
    const bySite = new Map()
    for (const r of rows) {
        if (!r.completed_on) continue
        const site = r.site || '—'
        bySite.set(site, (bySite.get(site) || 0) + num(r.hours))
    }
    return [...bySite.entries()]
        .map(([site, hours]) => ({ site, hours: round2(hours) }))
        .filter(s => s.hours > 0)
        .sort((a, b) => b.hours - a.hours || a.site.localeCompare(b.site))
}

/** The donut: the top `topN` sites, and everything else folded into one slice. */
export function siteSlices(ranked, topN = 6) {
    const total = ranked.reduce((s, r) => s + r.hours, 0)
    if (!total) return []
    const top = ranked.slice(0, topN)
    const rest = ranked.slice(topN)
    const slices = top.map(r => ({ label: r.site, hours: r.hours, share: r.hours / total }))
    if (rest.length) {
        const hours = round2(rest.reduce((s, r) => s + r.hours, 0))
        slices.push({ label: `Other ${rest.length} site${rest.length === 1 ? '' : 's'}`, hours, share: hours / total, other: true })
    }
    return slices
}
