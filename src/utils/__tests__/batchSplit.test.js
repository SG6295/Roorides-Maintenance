import { describe, it, expect } from 'vitest'
import { splitEvenly, linesSummary } from '../batchSplit'

describe('splitEvenly', () => {
    it('splits an amount that divides evenly', () => {
        expect(splitEvenly('750', 15)).toEqual(Array(15).fill('50.00'))
    })

    it('puts the leftover paise on the last line', () => {
        expect(splitEvenly('100', 3)).toEqual(['33.33', '33.33', '33.34'])
        expect(splitEvenly('0.10', 3)).toEqual(['0.03', '0.03', '0.04'])
    })

    it('always adds back up to the approved amount', () => {
        const parts = splitEvenly('1234.57', 7)
        const total = parts.reduce((s, p) => s + Math.round(Number(p) * 100), 0)
        expect(total).toBe(123457)
    })

    it('returns nothing to split for no vehicles or a bad amount', () => {
        expect(splitEvenly('750', 0)).toEqual([])
        expect(splitEvenly('', 3)).toEqual([])
        expect(splitEvenly('abc', 3)).toEqual([])
        expect(splitEvenly('0', 3)).toEqual([])
    })
})

describe('linesSummary', () => {
    it('reports an exact match', () => {
        const s = linesSummary([{ amount: '250' }, { amount: '400' }, { amount: '100.00' }], '750')
        expect(s).toMatchObject({ total: 75000, approved: 75000, difference: 0, invalid: [] })
    })

    it('reports amount left to allocate and over-allocation', () => {
        expect(linesSummary([{ amount: '700' }], '750').difference).toBe(5000)
        expect(linesSummary([{ amount: '800' }], '750').difference).toBe(-5000)
    })

    it('flags blank, malformed and zero lines without counting them', () => {
        const s = linesSummary([{ amount: '' }, { amount: '1.234' }, { amount: '0' }, { amount: '50' }], '50')
        expect(s.invalid).toEqual([0, 1, 2])
        expect(s.total).toBe(5000)
        expect(s.difference).toBe(0)
    })
})
