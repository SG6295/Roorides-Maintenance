import { describe, it, expect } from 'vitest'
import {
    emptyGstRow,
    isGstBreakdownEmpty,
    gstRowPaise,
    gstRowsInclPaise,
    gstBreakdownProblem,
    gstRowsToBreakdown,
    breakdownToGstRows,
    breakdownGstTotal,
    breakdownLines,
    sameBreakdown,
} from '../gstBreakdown'
import { GST_RATES, gstRateOptions } from '../../constants/gstRates'

const row = (rate, amount, entered = 'incl') => ({ rate: String(rate), amount: String(amount), entered })

describe('gst rates', () => {
    it('offers 0 to 40% as strings, and keeps a saved rate no longer offered', () => {
        expect(GST_RATES).toEqual([0, 5, 12, 18, 28, 40])
        expect(gstRateOptions().map(o => o.value)).toEqual(['0', '5', '12', '18', '28', '40'])
        expect(gstRateOptions(18).length).toBe(6)
        expect(gstRateOptions('3').map(o => o.value)).toEqual(['0', '3', '5', '12', '18', '28', '40'])
    })
})

describe('gstRowPaise', () => {
    it('splits an amount incl. GST, GST taking the remainder', () => {
        expect(gstRowPaise(row(18, '100'))).toEqual({ before: 8475, gst: 1525, incl: 10000 })
        expect(gstRowPaise(row(28, '1280'))).toEqual({ before: 100000, gst: 28000, incl: 128000 })
    })
    it('adds GST to an amount before GST, rounding to the paisa', () => {
        expect(gstRowPaise(row(18, '84.75', 'before'))).toEqual({ before: 8475, gst: 1526, incl: 10001 })
        expect(gstRowPaise(row(18, '1000', 'before'))).toEqual({ before: 100000, gst: 18000, incl: 118000 })
    })
    it('treats 0% as no GST', () => {
        expect(gstRowPaise(row(0, '250'))).toEqual({ before: 25000, gst: 0, incl: 25000 })
    })
    it('is null without a usable amount', () => {
        expect(gstRowPaise(emptyGstRow())).toBeNull()
        expect(gstRowPaise(row(18, '1.234'))).toBeNull()
    })
})

describe('gstBreakdownProblem', () => {
    it('needs at least one amount', () => {
        expect(isGstBreakdownEmpty([emptyGstRow()])).toBe(true)
        expect(gstBreakdownProblem([emptyGstRow()], '100')).toBe('Add the GST breakdown.')
    })
    it('refuses a repeated rate and an empty row beside a filled one', () => {
        expect(gstBreakdownProblem([row(18, 50), row(18, 50)], '100')).toBe('Use one row per GST rate.')
        expect(gstBreakdownProblem([row(18, 100), emptyGstRow(28)], '100')).toBe('Every GST row needs an amount.')
    })
    it('must add up to the Invoice Value exactly', () => {
        expect(gstBreakdownProblem([row(18, 100)], '100.01'))
            .toBe('The GST rows add up to ₹100.00 but the Invoice Value is ₹100.01.')
        expect(gstBreakdownProblem([row(28, 1280), row(18, 2920)], '4200')).toBeNull()
        expect(gstRowsInclPaise([row(28, 1280), row(18, 2474.58, 'before')])).toBe(128000 + 292000)
    })
})

describe('saved breakdown', () => {
    it('round-trips through the form unchanged, however it was entered', () => {
        for (const rows of [[row(18, '100')], [row(18, '84.75', 'before')], [row(28, '1000', 'before'), row(5, '77.77')]]) {
            const saved = gstRowsToBreakdown(rows)
            expect(gstRowsToBreakdown(breakdownToGstRows(saved))).toEqual(saved)
        }
    })
    it('totals, describes and compares', () => {
        const saved = gstRowsToBreakdown([row(28, 1280), row(18, 2920)])
        expect(saved[1]).toEqual({ rate: 18, before_gst: 2474.58, gst: 445.42, incl_gst: 2920 })
        expect(breakdownGstTotal(saved)).toBe(725.42)
        expect(breakdownGstTotal(null)).toBeNull()
        expect(breakdownLines(saved)[0]).toBe('28%: ₹1,000.00 + ₹280.00 GST = ₹1,280.00')
        expect(sameBreakdown(saved, JSON.parse(JSON.stringify(saved)))).toBe(true)
        expect(sameBreakdown(saved, null)).toBe(false)
        expect(sameBreakdown(null, undefined)).toBe(true)
    })
})
