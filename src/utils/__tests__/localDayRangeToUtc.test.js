/**
 * Regression tests for MAIN-83.
 *
 * The Tickets date range moved from the browser into the database query, and
 * `tickets.created_at` is naive UTC. These tests fix the boundaries for an IST viewer.
 */
/* global process */
import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { localDayRangeToUtc } from '../datetime'

let originalTz

beforeAll(() => {
    originalTz = process.env.TZ
    process.env.TZ = 'Asia/Kolkata'
})

afterAll(() => {
    process.env.TZ = originalTz
})

describe('localDayRangeToUtc', () => {
    it('starts at local midnight of the start day, in UTC', () => {
        const { from } = localDayRangeToUtc('2026-09-01', '2026-09-30')
        expect(from).toBe('2026-08-31T18:30:00.000Z')
    })

    it('ends at local midnight after the end day, so the whole last day is included', () => {
        const { to } = localDayRangeToUtc('2026-09-01', '2026-09-30')
        expect(to).toBe('2026-09-30T18:30:00.000Z')
    })

    it('puts a ticket created at 00:15 IST on the 1st inside that month', () => {
        // 00:15 IST on 1 Sep is 18:45 UTC on 31 Aug — the value stored in created_at.
        const createdAtUtc = '2026-08-31T18:45:00.000Z'
        const sep = localDayRangeToUtc('2026-09-01', '2026-09-30')
        const aug = localDayRangeToUtc('2026-08-01', '2026-08-31')

        expect(createdAtUtc >= sep.from && createdAtUtc < sep.to).toBe(true)
        expect(createdAtUtc >= aug.from && createdAtUtc < aug.to).toBe(false)
    })

    it('covers a single day', () => {
        expect(localDayRangeToUtc('2026-10-06', '2026-10-06')).toEqual({
            from: '2026-10-05T18:30:00.000Z',
            to: '2026-10-06T18:30:00.000Z',
        })
    })
})
