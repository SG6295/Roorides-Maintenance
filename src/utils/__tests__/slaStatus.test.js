import { describe, it, expect } from 'vitest'
import { isSlaTracked, notApplicableReason, ticketFinishedAt } from '../slaStatus'

describe('isSlaTracked', () => {
    it('splits at 14 Aug 2026 00:00 IST, with naive values read as UTC', () => {
        expect(isSlaTracked('2026-08-13 08:27:19')).toBe(false)
        expect(isSlaTracked('2026-08-13 18:29:59')).toBe(false)
        expect(isSlaTracked('2026-08-13 18:30:00')).toBe(true)
        expect(isSlaTracked('2026-08-17 07:06:37')).toBe(true)
        expect(isSlaTracked(null)).toBe(false)
    })
})

describe('notApplicableReason', () => {
    it('names pre-tracking first, then rejection, then no issues', () => {
        expect(notApplicableReason({ created_at: '2026-06-01 10:00:00', status: 'Rejected' })).toMatch(/before SLA tracking/)
        expect(notApplicableReason({ created_at: '2026-10-01 10:00:00', status: 'Rejected' })).toBe('Rejected with no issues')
        expect(notApplicableReason({ created_at: '2026-10-01 10:00:00', status: 'New' })).toBe('No issues yet')
    })
})

describe('ticketFinishedAt', () => {
    it('is the latest activity complete time once every issue is Done', () => {
        const issues = [
            { status: 'Done', completed_at: '2026-10-02T05:00:00+00:00' },
            { status: 'Done', completed_at: '2026-10-03T04:00:00+00:00' },
        ]
        expect(ticketFinishedAt(issues).toISOString()).toBe('2026-10-03T04:00:00.000Z')
    })

    it('is null while any issue is unfinished, or with no issues', () => {
        expect(ticketFinishedAt([
            { status: 'Done', completed_at: '2026-10-02T05:00:00+00:00' },
            { status: 'Open', completed_at: null },
        ])).toBeNull()
        expect(ticketFinishedAt([])).toBeNull()
    })
})
