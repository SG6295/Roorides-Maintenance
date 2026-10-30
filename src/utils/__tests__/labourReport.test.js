import { describe, it, expect } from 'vitest'
import {
    hourBand, enumerateDays, dayCount, filterRows, summarise, buildGrid, rankSites, siteSlices,
} from '../labourReport'

const row = (over) => ({
    issue_id: 'i1', issue_number: 'T-1-01', description: 'Brakes', completed_on: '2026-10-01',
    site: 'TSAB', technician_id: 'm1', technician_name: 'Manoj', technician_role: 'mechanic',
    hours: '2', attributed: true, ...over,
})

const ROWS = [
    row({}),
    row({ issue_id: 'i1', technician_id: 'e1', technician_name: 'Elangovan', technician_role: 'electrician', hours: '1.5' }),
    row({ issue_id: 'i2', issue_number: 'T-2-01', completed_on: '2026-10-02', site: 'RTL', hours: '3' }),
    row({ issue_id: 'i3', completed_on: '2026-10-02', site: 'RTL', technician_id: null, technician_name: null, technician_role: null, hours: '0.5', attributed: false }),
    row({ issue_id: 'i4', completed_on: null, hours: '4' }),  // labour on an item not yet Done
]

describe('hourBand', () => {
    it('buckets 0 / ≤2 / 2–4 / 4–6 / 6–8 / 8+', () => {
        expect([0, 0.25, 2, 2.5, 4, 5, 6, 7, 8, 8.5, 12].map(hourBand)).toEqual([0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
    })
})

describe('days', () => {
    it('lists every day inclusive, across a month end', () => {
        expect(enumerateDays('2026-09-29', '2026-10-02')).toEqual(['2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02'])
        expect(dayCount('2026-09-29', '2026-10-02')).toBe(4)
        expect(enumerateDays('2026-10-02', '2026-10-01')).toEqual([])
    })
})

describe('filterRows', () => {
    it('filters by site', () => {
        expect(filterRows(ROWS, { sites: ['RTL'] }).map(r => r.issue_id)).toEqual(['i2', 'i3'])
    })

    it('drops unattributed hours when filtering by trade or person', () => {
        expect(filterRows(ROWS, { trade: 'electrician' }).map(r => r.technician_id)).toEqual(['e1'])
        expect(filterRows(ROWS, { technicianId: 'm1' }).every(r => r.attributed)).toBe(true)
    })
})

describe('summarise', () => {
    it('totals dated hours, keeps open hours apart and averages per person-day', () => {
        const s = summarise(ROWS)
        expect(s.totalHours).toBe(7)          // 2 + 1.5 + 3 + 0.5
        expect(s.attributedHours).toBe(6.5)
        expect(s.unattributedHours).toBe(0.5)
        expect(s.openHours).toBe(4)
        expect(s.workItems).toBe(3)
        expect(s.technicianCount).toBe(2)
        // Manoj on Oct 1 and Oct 2, Elangovan on Oct 1 → 6.5 h over 3 person-days
        expect(s.avgPerTechnicianDay).toBe(2.17)
        expect(s.sitesServed).toBe(2)
        expect(s.topSite.site).toBe('RTL')
        expect(s.topSite.share).toBeCloseTo(3.5 / 7)
    })

    it('is all zeros for no rows', () => {
        expect(summarise([])).toMatchObject({ totalHours: 0, avgPerTechnicianDay: 0, topSite: null })
    })
})

describe('buildGrid', () => {
    it('lays attributed hours on their day, busiest person first', () => {
        const g = buildGrid(ROWS, enumerateDays('2026-10-01', '2026-10-03'))
        expect(g.technicians.map(t => [t.name, t.total])).toEqual([['Manoj', 5], ['Elangovan', 1.5]])
        expect(g.technicians[0].cells.map(c => c.hours)).toEqual([2, 3, 0])
        expect(g.technicians[0].cells[1].items).toEqual(['T-2-01 Brakes — 3 h'])
        expect(g.dayTotals).toEqual([3.5, 3, 0])
        expect(g.grandTotal).toBe(6.5)
    })

    it('adds two items on the same day into one cell', () => {
        const rows = [row({}), row({ issue_id: 'i9', hours: '0.1' }), row({ issue_id: 'i8', hours: '0.2' })]
        const g = buildGrid(rows, ['2026-10-01'])
        expect(g.technicians[0].cells[0].hours).toBe(2.3)
        expect(g.technicians[0].cells[0].items).toHaveLength(3)
    })
})

describe('sites', () => {
    it('ranks sites including unattributed hours, ignoring open items', () => {
        expect(rankSites(ROWS)).toEqual([{ site: 'RTL', hours: 3.5 }, { site: 'TSAB', hours: 3.5 }])
    })

    it('folds everything past the top N into one slice', () => {
        const ranked = ['A', 'B', 'C', 'D'].map((site, i) => ({ site, hours: 4 - i }))
        const slices = siteSlices(ranked, 2)
        expect(slices.map(s => s.label)).toEqual(['A', 'B', 'Other 2 sites'])
        expect(slices[2].hours).toBe(3)
        expect(slices.reduce((s, x) => s + x.share, 0)).toBeCloseTo(1)
        expect(siteSlices([], 6)).toEqual([])
    })
})
