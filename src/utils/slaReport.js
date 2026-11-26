/**
 * Analytics › SLA & tickets (MAIN-171).
 *
 * The database decides which bucket every ticket and issue counts in
 * (analytics_ticket_rows / analytics_issue_rows) and get_maintenance_stats returns the
 * counts. This file only lays those counts out — for the screen and for the Download,
 * from the same structure, so the two cannot disagree. It never re-derives a count, so
 * a row always adds up to its table's total.
 *
 * A key the database returns that is not in a known list (a category or status added
 * later) is still shown, after the known ones, so nothing silently drops out of a table.
 */
import { ALL_ISSUE_CATEGORIES } from '../constants/issueCategories'

export const TICKET_STATUSES = ['New', 'Accepted', 'Work In Progress', 'Resolved', 'Closed', 'Rejected']

export const SEVERITIES = ['Major', 'Minor']

/** Job card types an issue can have: the job card's type, or none yet. */
export const JOB_CARD_TYPES = [
    { key: 'InHouse', label: 'In-house' },
    { key: 'Outsource', label: 'Outsource' },
    { key: 'none', label: 'No job card yet' },
]

/** Completion SLA columns: a ticket's job card type, plus tickets with no issues. */
export const COMPLETION_COLUMNS = [...JOB_CARD_TYPES, { key: 'no_issues', label: 'No issues' }]

export const SLA_RESULTS = [
    { key: 'Pending', label: 'Pending' },
    { key: 'Adhered', label: 'Adhered' },
    { key: 'Violated', label: 'Violated' },
    { key: 'NA', label: 'Not applicable' },
]

const num = v => Number(v) || 0

/** The known keys in order, then any other key the counts carry. */
export function orderedKeys(known, counts = {}) {
    const extra = Object.keys(counts || {}).filter(k => !known.includes(k)).sort()
    return [...known, ...extra]
}

/** Rounded percentage, or null when there is nothing to divide by. */
export function percent(part, whole) {
    return whole > 0 ? Math.round((part / whole) * 100) : null
}

/** A percentage as shown on screen and in the Download. */
export function percentText(p) {
    return p === null || p === undefined ? '–' : `${p}%`
}

/** Adhered ÷ (Adhered + Violated): pending and not-applicable tickets are not judged yet. */
export function slaPercent(counts = {}) {
    return percent(num(counts.Adhered), num(counts.Adhered) + num(counts.Violated))
}

function keyLabel(list, key) {
    return list.find(x => x.key === key)?.label ?? key
}

/**
 * @param {object|null} stats the jsonb get_maintenance_stats returns
 */
export function buildSlaReport(stats) {
    if (!stats) return null
    const tickets = stats.tickets || {}
    const issues = stats.issues || {}
    const ticketTotal = num(tickets.total)
    const issueTotal = num(issues.total)

    const status = {
        total: ticketTotal,
        rows: orderedKeys(TICKET_STATUSES, tickets.by_status)
            .map(key => ({ key, label: key, value: num(tickets.by_status?.[key]) })),
    }

    const jcTypes = issues.by_job_card_type || {}
    const jobCardType = {
        total: issueTotal,
        rows: orderedKeys(JOB_CARD_TYPES.map(t => t.key), jcTypes)
            .map(key => ({ key, label: keyLabel(JOB_CARD_TYPES, key), value: num(jcTypes[key]) })),
    }

    const bySeverity = issues.by_severity || {}
    const severities = orderedKeys(SEVERITIES, bySeverity).map(severity => {
        const s = bySeverity[severity] || {}
        return {
            severity,
            total: num(s.total),
            rows: orderedKeys(ALL_ISSUE_CATEGORIES, s.by_category)
                .map(key => ({ key, label: key, value: num(s.by_category?.[key]) })),
        }
    })

    const comp = stats.completion || {}
    const columns = orderedKeys(COMPLETION_COLUMNS.map(c => c.key), comp)
        .map(key => ({ key, label: keyLabel(COMPLETION_COLUMNS, key) }))
    const resultKeys = orderedKeys(SLA_RESULTS.map(r => r.key),
        Object.assign({}, ...Object.values(comp)))
    const cell = (col, result) => num(comp[col]?.[result])
    const all = Object.fromEntries(resultKeys.map(r => [r, columns.reduce((t, c) => t + cell(c.key, r), 0)]))
    const completion = {
        columns,
        rows: resultKeys.map(r => ({
            key: r,
            label: keyLabel(SLA_RESULTS, r),
            values: Object.fromEntries(columns.map(c => [c.key, cell(c.key, r)])),
            all: all[r],
        })),
        totals: Object.fromEntries(columns.map(c => [c.key, resultKeys.reduce((t, r) => t + cell(c.key, r), 0)])),
        total: ticketTotal,
        percents: Object.fromEntries(columns.map(c => [c.key, slaPercent(comp[c.key])])),
        percentAll: slaPercent(all),
        all,
    }

    const acc = stats.acceptance || {}
    const acceptance = {
        pending: num(acc.Pending),
        adhered: num(acc.Adhered),
        violated: num(acc.Violated),
        na: num(acc.NA),
        total: ticketTotal,
        percent: slaPercent(acc),
    }

    const r = stats.ratings || {}
    const good = num(r.by_rating?.Good)
    const ok = num(r.by_rating?.Ok)
    const bad = num(r.by_rating?.Bad)
    const collected = num(r.collected)
    const pending = num(r.pending)
    const ratings = {
        pending, collected, good, ok, bad,
        collectionPercent: percent(collected, pending + collected),
        // Good = 2, Ok = 1, Bad = 0, out of 2 per rating.
        csatPercent: percent(2 * good + ok, 2 * collected),
    }

    return { status, jobCardType, severities, completion, acceptance, ratings }
}

function csvField(v) {
    const s = String(v ?? '')
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

/**
 * The Download: the screen's tables, one line per number, as Section, Row, Count.
 *
 * @param {ReturnType<typeof buildSlaReport>} report
 * @param {{ start: string, end: string, sites: string[] }} selection
 */
export function slaReportCsv(report, { start, end, sites = [] }) {
    const lines = [
        ['Analytics', 'SLA & tickets'],
        ['Date range', `${start} to ${end}`],
        ['Sites', sites.length ? sites.join('; ') : 'All sites'],
        [],
        ['Section', 'Row', 'Count'],
    ]
    const add = (section, rows) => rows.forEach(([label, value]) => lines.push([section, label, value]))

    add('Tickets by Status', [['Total', report.status.total], ...report.status.rows.map(r => [r.label, r.value])])
    add('Issues by Job Card Type', [...report.jobCardType.rows.map(r => [r.label, r.value]), ['Total', report.jobCardType.total]])
    report.severities.forEach(s => add(`Issues by Severity (${s.severity})`,
        [[`${s.severity} Total`, s.total], ...s.rows.map(r => [r.label, r.value])]))

    const c = report.completion
    const kpi = { InHouse: ' (Sharan KPI)', Outsource: ' (Manjunath KPI)' }
    ;[...c.columns, { key: 'all', label: 'All' }].forEach(col => {
        const isAll = col.key === 'all'
        add(`Completion SLA (${col.label})`, [
            ...c.rows.map(r => [r.label, isAll ? r.all : r.values[col.key]]),
            ['Total', isAll ? c.total : c.totals[col.key]],
            [`SLA %${kpi[col.key] || ''}`, percentText(isAll ? c.percentAll : c.percents[col.key])],
        ])
    })

    const a = report.acceptance
    add('Acceptance SLA', [
        ['Pending (awaiting issue)', a.pending], ['Adhered (on time)', a.adhered], ['Violated (late)', a.violated],
        ['Not applicable', a.na], ['Total', a.total], ['SLA % (Sharan KPI)', percentText(a.percent)],
    ])

    const r = report.ratings
    add('Ratings & Feedback', [
        ['Rating Pending', r.pending], ['Ratings Collected', r.collected],
        ['Collection % (Sharan KPI)', percentText(r.collectionPercent)],
        ['Good', r.good], ['Ok', r.ok], ['Bad', r.bad], ['CSAT % (Manjunath KPI)', percentText(r.csatPercent)],
    ])

    return lines.map(l => l.map(csvField).join(',')).join('\n')
}
