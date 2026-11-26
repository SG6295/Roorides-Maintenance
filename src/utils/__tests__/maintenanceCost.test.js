import { describe, it, expect } from 'vitest'
import {
    linesFromResponse, categoryOf, hubOf, NO_HUB, financialYear, periodRange, ALL_TIME_START, istDayOf,
    filterLines, summarise, byCompany, byCategory, byHub, bySite, splitsIn, byMonth, median,
    perVehicle, topShare, compareWithFleet, bandOf, byOdometer, bandLabel, inr, inrExact,
    inrShort, explainTotal, explainCompare, explainSplit, explainBand,
} from '../maintenanceCost'

const line = (over) => ({
    line_id: 'x', kind: 'spare', cost_date: '2026-10-06', vehicle_number: 'KA1', company: 'nvs_travels',
    hub: 'Bannerghatta', site: 'DSUH', category: 'Tyre', split_count: null, amount: 100, hours: null,
    price_missing: false, awaiting_finance: false, job_card_id: 'j1', job_card_number: 1,
    job_card_status: 'Completed', job_card_type: 'InHouse', job_card_odometer: null,
    batch_number: null, work_type: null, work_type_other: null, ...over,
})

const FLEET = [
    line({ line_id: 'jc1', kind: 'job_card', amount: 0, category: null }),
    line({ line_id: 's1', amount: 49300, job_card_odometer: 42442 }),
    line({ line_id: 's2', amount: 1749.47, category: 'Emission', cost_date: '2026-11-25', job_card_id: 'j2', job_card_number: 2 }),
    line({ line_id: 'jc2', kind: 'job_card', amount: 0, category: null, job_card_id: 'j2', job_card_number: 2, job_card_status: 'Open' }),
    line({ line_id: 's3', vehicle_number: 'KA2', amount: 1000, job_card_id: 'j3', job_card_number: 3, site: 'TSAB', job_card_odometer: 15000 }),
    line({ line_id: 's4', vehicle_number: 'KA3', company: 'nvs_travel_solutions', amount: 500, job_card_id: 'j4', job_card_number: 4, hub: 'Mahadevpura' }),
    line({ line_id: 'o1', kind: 'outsourced', vehicle_number: 'KA2', amount: 2250, split_count: 2, category: 'Mechanical', job_card_id: 'j5', job_card_number: 5, awaiting_finance: true, job_card_type: 'Outsource', job_card_odometer: 18000 }),
    line({ line_id: 'o2', kind: 'outsourced', vehicle_number: 'KA2', amount: 2250, split_count: 2, category: 'Electrical', job_card_id: 'j5', job_card_number: 5, awaiting_finance: true, job_card_type: 'Outsource', job_card_odometer: 18000 }),
    line({ line_id: 'm1', kind: 'mvi', vehicle_number: 'KA1', amount: 300, hub: null, category: null, work_type: 'Greasing', job_card_id: null, job_card_number: null, batch_number: 3 }),
    line({ line_id: 'l1', kind: 'labour', amount: 0, hours: 0.25 }),
    line({ line_id: 'p1', amount: 0, price_missing: true, job_card_id: 'j6' }),
]

describe('reading the response', () => {
    it('turns column arrays into objects with numbers', () => {
        const lines = linesFromResponse({ columns: ['kind', 'amount', 'hours'], rows: [['spare', '12.50', null], ['labour', 0, '1.5']] })
        expect(lines).toEqual([
            { kind: 'spare', amount: 12.5, hours: null, quantity: null },
            { kind: 'labour', amount: 0, hours: 1.5, quantity: null },
        ])
        expect(linesFromResponse(null)).toEqual([])
    })

    it('names categories and hubs', () => {
        expect(categoryOf(line({}))).toBe('Tyre')
        expect(categoryOf(line({ kind: 'mvi', work_type: 'Other', work_type_other: 'Seat repair' }))).toBe('Multi-vehicle: Seat repair')
        expect(hubOf(line({ hub: null }))).toBe(NO_HUB)
    })
})

describe('periods', () => {
    it('knows the financial year either side of April', () => {
        expect(financialYear('2026-11-25')).toEqual({ start: '2026-04-01', end: '2027-03-31' })
        expect(financialYear('2027-02-10')).toEqual({ start: '2026-04-01', end: '2027-03-31' })
        expect(financialYear('2027-04-01')).toEqual({ start: '2027-04-01', end: '2028-03-31' })
    })

    it('reads database timestamps as Indian dates, whatever the browser zone', () => {
        // 20:00 UTC on 24 Nov is 01:30 on 25 Nov in India.
        expect(istDayOf('2026-11-24T20:00:00')).toBe('2026-11-25')
        expect(istDayOf('2026-11-24 20:00:00')).toBe('2026-11-25')
        expect(istDayOf('2026-11-24T20:00:00+00:00')).toBe('2026-11-25')
        expect(istDayOf('2026-11-24T10:00:00Z')).toBe('2026-11-24')
        expect(istDayOf(null)).toBe(null)
    })

    it('works out each preset', () => {
        expect(periodRange('all', '2026-11-25')).toEqual({ start: ALL_TIME_START, end: '2026-11-25' })
        expect(periodRange('90d', '2026-11-25')).toEqual({ start: '2026-08-28', end: '2026-11-25' })
    })
})

describe('totals', () => {
    it('adds spares, outsourced and multi-vehicle lines, leaving out unpriced spares', () => {
        const s = summarise(FLEET)
        expect(s.spares).toBe(52549.47)
        expect(s.outsourcedCards).toBe(4500)
        expect(s.mvi).toBe(300)
        expect(s.total).toBe(57349.47)
        expect(s.awaitingFinance).toBe(4500)
        expect(s.jobCards).toBe(2)
        expect(s.openJobCards).toBe(1)
        expect(s.labourHours).toBe(0.25)
        expect(s.missingPrices).toBe(1)
        expect(s.spareLines).toBe(4)
        expect(s.vehiclesWithCost).toBe(3)
    })

    it('adds in paise, so tenths of a rupee do not drift', () => {
        const lines = Array.from({ length: 10 }, (_, i) => line({ line_id: String(i), amount: 0.1 }))
        expect(summarise(lines).total).toBe(1)
    })

    it('groups by company, hub, site and category, largest first', () => {
        expect(byCompany(FLEET).map(g => [g.key, g.amount, g.vehicles])).toEqual([
            ['nvs_travels', 56849.47, 2],
            ['nvs_travel_solutions', 500, 1],
        ])
        expect(byHub(FLEET).map(g => g.key)).toEqual(['Bannerghatta', 'Mahadevpura', NO_HUB])
        expect(bySite(FLEET)[0]).toMatchObject({ key: 'DSUH', amount: 56349.47, vehicles: 3 })
        const cats = byCategory(FLEET)
        expect(cats.map(c => c.key)).toEqual(['Tyre', 'Electrical', 'Mechanical', 'Emission', 'Multi-vehicle: Greasing'])
        expect(cats.find(c => c.key === 'Mechanical').split).toBe(true)
        expect(cats.find(c => c.key === 'Tyre').split).toBe(false)
    })

    it('explains a split outsourced amount', () => {
        const [split] = splitsIn(FLEET, 'Mechanical')
        expect(split).toEqual({ jobCardNumber: 5, count: 2, share: 2250, approved: 4500 })
        expect(explainSplit(split)).toBe('Approved ₹4,500.00 ÷ 2 issues = ₹2,250.00 each (job card 5). The invoice has one amount, so it is shared equally among the card\'s issues for the category totals.')
    })

    it('fills every month of the period, empty ones as 0, split by company', () => {
        const months = byMonth(FLEET, { start: '2026-09-15', end: '2026-11-25' })
        expect(months.map(m => [m.key, m.amount])).toEqual([
            ['2026-09', 0],
            ['2026-10', 55600],
            ['2026-11', 1749.47],
        ])
        expect(months[1].byCompany).toEqual({ nvs_travels: 55100, nvs_travel_solutions: 500 })
    })

    it('filters by every dimension', () => {
        expect(summarise(filterLines(FLEET, { companies: ['nvs_travel_solutions'] })).total).toBe(500)
        expect(summarise(filterLines(FLEET, { hubs: [NO_HUB] })).total).toBe(300)
        expect(summarise(filterLines(FLEET, { sites: ['TSAB'] })).total).toBe(1000)
        expect(summarise(filterLines(FLEET, { categories: ['Mechanical'] })).total).toBe(2250)
        expect(summarise(filterLines(FLEET, { vehicle: 'KA2' })).total).toBe(5500)
    })
})

describe('per vehicle', () => {
    it('takes the median of an even and an odd list', () => {
        expect(median([3, 1, 2])).toBe(2)
        expect(median([4, 1, 3, 2])).toBe(2.5)
        expect(median([])).toBe(0)
    })

    it('averages over vehicles with a cost', () => {
        expect(perVehicle(FLEET)).toEqual({ vehicles: 3, average: 19116.49, median: 5500 })
    })

    it('finds the share of the costliest vehicles', () => {
        expect(topShare(FLEET, 0.1)).toMatchObject({ count: 1, amount: 51349.47 })
    })

    it('compares a vehicle with the average of its own company', () => {
        const c = compareWithFleet(FLEET, 'KA1', 'nvs_travels')
        expect(c).toMatchObject({ own: 51349.47, companyVehicles: 2, average: 28424.74, rank: 1, ranked: 3 })
        expect(explainCompare(c)).toBe(
            'This vehicle ₹51,349 ÷ NVS Travels average ₹28,425 = 1.8×. Average = NVS Travels cost ₹56,849 ÷ 2 vehicles that had a cost in the period. Rank: 1 of 3 vehicles with a cost, all companies.'
        )
    })
})

describe('odometer bands', () => {
    it('puts a reading in its 10,000 km band', () => {
        expect(bandOf(42442)).toBe(40000)
        expect(bandOf(9999)).toBe(0)
        expect(bandLabel(40000)).toBe('40k–50k km')
    })

    it('sums a vehicle from its lowest to its highest band, and states spend with no reading', () => {
        const { bands, noReading } = byOdometer(filterLines(FLEET, { vehicle: 'KA2' }))
        expect(bands.map(b => [b.start, b.amount])).toEqual([[10000, 5500]])
        expect(noReading.amount).toBe(0)
        const all = byOdometer(FLEET)
        expect(all.bands.map(b => b.start)).toEqual([10000, 20000, 30000, 40000])
        expect(all.bands[1].amount).toBe(0)
        expect(all.noReading).toEqual({ amount: 2549.47, jobCards: [2, 4, 'MVI-3'] })
        expect(explainBand(all.bands[3], 'total')).toBe('40k–50k km: ₹49,300 on 1 job card (JC 1).')
    })

    it('averages per vehicle for the report, marks thin bands and sums beyond the cap', () => {
        const { bands, beyond } = byOdometer(FLEET, { mode: 'perVehicle', cap: 40000 })
        expect(bands.map(b => b.start)).toEqual([0, 10000, 20000, 30000])
        expect(bands[1]).toMatchObject({ amount: 5500, vehicles: 1, thin: true })
        expect(bands[0]).toMatchObject({ amount: 0, vehicles: 0, thin: false })
        expect(beyond.amount).toBe(49300)
    })
})

describe('words', () => {
    it('formats rupees', () => {
        expect(inr(97764.2)).toBe('₹97,764')
        expect(inr(4104690)).toBe('₹41,04,690')
        expect(inrExact(30927.8)).toBe('₹30,927.80')
        expect(inrShort(4104690)).toBe('41.05L')
        expect(inrShort(53158)).toBe('53.2k')
        expect(inrShort(900)).toBe('900')
    })

    it('explains a total', () => {
        expect(explainTotal(summarise(FLEET))).toBe(
            'Spares ₹52,549 (4 lines on 4 job cards) + outsourced ₹4,500 + multi-vehicle invoices ₹300 = ₹57,349. ₹4,500 of it is awaiting finance\'s acceptance. 1 spare with no price is left out.'
        )
    })
})
