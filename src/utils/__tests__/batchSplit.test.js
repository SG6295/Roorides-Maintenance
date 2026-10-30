import { describe, it, expect } from 'vitest'
import { lineAmount, linesSummary } from '../batchSplit'

describe('lineAmount', () => {
    it('is rate × quantity in paise', () => {
        expect(lineAmount({ rate: '50', quantity: '1' })).toBe(5000)
        expect(lineAmount({ rate: '33.33', quantity: '3' })).toBe(9999)
        expect(lineAmount({ rate: '0.10', quantity: 7 })).toBe(70)
    })

    it('is NaN for a blank, malformed or zero rate', () => {
        expect(lineAmount({ rate: '', quantity: '1' })).toBeNaN()
        expect(lineAmount({ rate: '1.234', quantity: '1' })).toBeNaN()
        expect(lineAmount({ rate: '0', quantity: '1' })).toBeNaN()
    })

    it('is NaN unless the quantity is a whole number of at least 1', () => {
        expect(lineAmount({ rate: '50', quantity: '' })).toBeNaN()
        expect(lineAmount({ rate: '50', quantity: '0' })).toBeNaN()
        expect(lineAmount({ rate: '50', quantity: '1.5' })).toBeNaN()
        expect(lineAmount({ rate: '50', quantity: '-2' })).toBeNaN()
    })
})

describe('linesSummary', () => {
    it('reports an exact match', () => {
        const s = linesSummary([{ rate: '50', quantity: '12' }, { rate: '50', quantity: '3' }], '750')
        expect(s).toMatchObject({ total: 75000, approved: 75000, difference: 0, invalid: [] })
    })

    it('reports amount left to allocate and over-allocation', () => {
        expect(linesSummary([{ rate: '700', quantity: '1' }], '750').difference).toBe(5000)
        expect(linesSummary([{ rate: '400', quantity: '2' }], '750').difference).toBe(-5000)
    })

    it('flags unusable lines without counting them', () => {
        const s = linesSummary([{ rate: '', quantity: '1' }, { rate: '50', quantity: '0' }, { rate: '50', quantity: '1' }], '50')
        expect(s.invalid).toEqual([0, 1])
        expect(s.total).toBe(5000)
        expect(s.difference).toBe(0)
    })
})
