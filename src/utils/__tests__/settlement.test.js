import { describe, it, expect } from 'vitest'
import { toPaise, paiseToInput } from '../settlement'

describe('toPaise', () => {
    it('converts typed and stored amounts exactly', () => {
        expect(toPaise('4200')).toBe(420000)
        expect(toPaise('4191.33')).toBe(419133)
        expect(toPaise('0.5')).toBe(50)
        expect(toPaise(2178.5)).toBe(217850)
        expect(toPaise('4200.00')).toBe(420000)
    })

    it('treats blank as zero', () => {
        expect(toPaise('')).toBe(0)
        expect(toPaise(null)).toBe(0)
    })

    it('rejects more than two decimals, negatives and junk instead of rounding', () => {
        expect(toPaise('42.333')).toBeNaN()
        expect(toPaise('-5')).toBeNaN()
        expect(toPaise('1,000')).toBeNaN()
        expect(toPaise('abc')).toBeNaN()
    })

    it('adds without float drift', () => {
        expect(toPaise('0.1') + toPaise('0.2')).toBe(toPaise('0.3'))
    })
})

describe('paiseToInput', () => {
    it('formats paise as a two-decimal input value', () => {
        expect(paiseToInput(419100)).toBe('4191.00')
        expect(paiseToInput(5)).toBe('0.05')
        expect(paiseToInput(-80000)).toBe('-800.00')
    })
})
