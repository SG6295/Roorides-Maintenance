import { describe, it, expect } from 'vitest'
import { buildSlaReport, slaReportCsv, orderedKeys, percent, percentText, slaPercent } from '../slaReport'

// Prod, 1 Dec 2025 – 30 Nov 2026, all sites, as get_maintenance_stats returned it on 27 Nov 2026.
const stats = {
    tickets: { total: 4809, by_status: { New: 41, Accepted: 357, 'Work In Progress': 10, Resolved: 4131, Closed: 19, Rejected: 251 } },
    acceptance: { Pending: 39, Adhered: 3018, Violated: 99, NA: 1653 },
    completion: {
        InHouse: { Pending: 2, Adhered: 2322, Violated: 192, NA: 1642 },
        Outsource: { Adhered: 3, NA: 6 },
        none: { Pending: 211, Adhered: 47, Violated: 182, NA: 4 },
        no_issues: { Pending: 39, NA: 159 },
    },
    issues: {
        total: 4640,
        by_job_card_type: { InHouse: 4176, Outsource: 9, none: 455 },
        by_severity: {
            Major: { total: 1543, by_category: { Body: 348, Electrical: 166, Emission: 328, Mechanical: 501, Other: 88, Tyre: 112 } },
            Minor: { total: 3097, by_category: { Body: 465, Electrical: 550, Emission: 959, GPS: 1, Mechanical: 649, Other: 396, Tyre: 77 } },
        },
    },
    ratings: { pending: 4146, collected: 19, by_rating: { Good: 15, Ok: 1, Bad: 3 } },
}

const sum = rows => rows.reduce((t, r) => t + r.value, 0)

describe('buildSlaReport', () => {
    const report = buildSlaReport(stats)

    it('returns null with no stats', () => {
        expect(buildSlaReport(null)).toBeNull()
    })

    it('every table adds up to its total', () => {
        expect(sum(report.status.rows)).toBe(report.status.total)
        expect(sum(report.jobCardType.rows)).toBe(report.jobCardType.total)
        report.severities.forEach(s => expect(sum(s.rows)).toBe(s.total))
        expect(report.severities.reduce((t, s) => t + s.total, 0)).toBe(report.jobCardType.total)
        const c = report.completion
        expect(Object.values(c.totals).reduce((t, n) => t + n, 0)).toBe(c.total)
        expect(c.rows.reduce((t, r) => t + r.all, 0)).toBe(c.total)
    })

    it('shows every category, zero ones included, in the app order', () => {
        expect(report.severities.map(s => s.severity)).toEqual(['Major', 'Minor'])
        expect(report.severities[0].rows.map(r => [r.label, r.value])).toEqual([
            ['Mechanical', 501], ['Electrical', 166], ['Body', 348], ['Tyre', 112], ['GPS', 0], ['Emission', 328], ['Other', 88],
        ])
    })

    it('keeps a category the list does not know yet, so the rows still add up', () => {
        const r = buildSlaReport({ ...stats, issues: { ...stats.issues, by_severity: { Major: { total: 3, by_category: { Mechanical: 1, Brakes: 2 } } } } })
        expect(r.severities[0].rows.at(-1)).toEqual({ key: 'Brakes', label: 'Brakes', value: 2 })
        expect(sum(r.severities[0].rows)).toBe(3)
    })

    it('labels job card types as the job card does', () => {
        expect(report.jobCardType.rows.map(r => [r.label, r.value])).toEqual([
            ['In-house', 4176], ['Outsource', 9], ['No job card yet', 455],
        ])
    })

    it('splits completion by the ticket’s job card type', () => {
        const c = report.completion
        expect(c.columns.map(col => col.label)).toEqual(['In-house', 'Outsource', 'No job card yet', 'No issues'])
        expect(c.rows.map(r => r.label)).toEqual(['Pending', 'Adhered', 'Violated', 'Not applicable'])
        expect(c.totals).toEqual({ InHouse: 4158, Outsource: 9, none: 444, no_issues: 198 })
        expect(c.all).toEqual({ Pending: 252, Adhered: 2372, Violated: 374, NA: 1811 })
        expect(c.percents).toEqual({ InHouse: 92, Outsource: 100, none: 21, no_issues: null })
        expect(c.percentAll).toBe(86)
    })

    it('works out acceptance and ratings', () => {
        expect(report.acceptance).toEqual({ pending: 39, adhered: 3018, violated: 99, na: 1653, total: 4809, percent: 97 })
        expect(report.ratings.collectionPercent).toBe(0)
        expect(report.ratings.csatPercent).toBe(82) // (2×15 + 1) ÷ (2×19)
    })
})

describe('helpers', () => {
    it('orderedKeys puts unknown keys last, sorted', () => {
        expect(orderedKeys(['a', 'b'], { c: 1, a: 1, z: 1 })).toEqual(['a', 'b', 'c', 'z'])
        expect(orderedKeys(['a'], null)).toEqual(['a'])
    })
    it('percent and slaPercent', () => {
        expect(percent(1, 0)).toBeNull()
        expect(percent(1, 3)).toBe(33)
        expect(slaPercent({ Adhered: 3 })).toBe(100)
        expect(slaPercent({ Pending: 4 })).toBeNull()
        expect(percentText(null)).toBe('–')
        expect(percentText(92)).toBe('92%')
    })
})

describe('slaReportCsv', () => {
    const csv = slaReportCsv(buildSlaReport(stats), { start: '2025-12-01', end: '2026-11-30', sites: ['AECS', 'Bad, name'] })
    const lines = csv.split('\n')

    it('states the selection, quoting a site name with a comma', () => {
        expect(lines[1]).toBe('Date range,2025-12-01 to 2026-11-30')
        expect(lines[2]).toBe('Sites,"AECS; Bad, name"')
        expect(lines[4]).toBe('Section,Row,Count')
    })

    it('carries the screen’s numbers', () => {
        expect(lines).toContain('Issues by Job Card Type,Outsource,9')
        expect(lines).toContain('Issues by Severity (Major),Emission,328')
        expect(lines).toContain('Issues by Severity (Minor),GPS,1')
        expect(lines).toContain('Completion SLA (Outsource),SLA % (Manjunath KPI),100%')
        expect(lines).toContain('Completion SLA (In-house),SLA % (Sharan KPI),92%')
        expect(lines).toContain('Completion SLA (All),Total,4809')
        expect(lines).toContain('Ratings & Feedback,CSAT % (Manjunath KPI),82%')
        expect(csv).not.toMatch(/undefined|NaN/)
    })

    it('says All sites when none are picked', () => {
        expect(slaReportCsv(buildSlaReport(stats), { start: 'a', end: 'b', sites: [] }).split('\n')[2]).toBe('Sites,All sites')
    })
})
