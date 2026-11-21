import { describe, it, expect } from 'vitest'
import { seedFailures } from '../seedResult'

describe('seedFailures', () => {
    it('is empty for a clean seed', () => {
        expect(seedFailures({ failures: [], public: [{ table: 'tickets', status: 'ok' }] })).toEqual([])
    })

    it('returns table and login failures alike', () => {
        const failures = [
            { phase: 'table', item: 'issue_parts', error: 'boom' },
            { phase: 'login create', item: 'a@b.c', error: 'already registered' },
        ]
        expect(seedFailures({ failures })).toEqual(failures)
    })

    it('falls back to failed tables when the response has no failures list', () => {
        expect(seedFailures({ public: [{ table: 'parts', status: 'error', error: 'x' }, { table: 'tickets', status: 'ok' }] }))
            .toEqual([{ phase: 'table', item: 'parts', error: 'x' }])
    })

    it('is empty with no result', () => {
        expect(seedFailures(null)).toEqual([])
    })
})
