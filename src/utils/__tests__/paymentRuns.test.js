import { describe, it, expect } from 'vitest'
import { paymentRunFor, upcomingRuns } from '../paymentRuns'

// MAIN-119 — finance releases payments every Wednesday. Mirrors payment_run_for().
describe('paymentRunFor', () => {
    it('keeps a Wednesday as its own run', () => {
        expect(paymentRunFor('2026-11-04')).toBe('2026-11-04')
    })

    it('moves every other day to the next Wednesday', () => {
        expect(paymentRunFor('2026-11-05')).toBe('2026-11-11') // Thursday
        expect(paymentRunFor('2026-11-08')).toBe('2026-11-11') // Sunday
        expect(paymentRunFor('2026-11-10')).toBe('2026-11-11') // Tuesday
    })

    it('crosses month and year ends', () => {
        expect(paymentRunFor('2026-12-31')).toBe('2027-01-06')
    })
})

describe('upcomingRuns', () => {
    it('gives this week’s run and the one after', () => {
        expect(upcomingRuns('2026-12-20')).toEqual({ thisRun: '2026-12-23', nextRun: '2026-12-30' })
    })

    it('treats a Wednesday as this week’s run', () => {
        expect(upcomingRuns('2026-12-23')).toEqual({ thisRun: '2026-12-23', nextRun: '2026-12-30' })
    })
})
