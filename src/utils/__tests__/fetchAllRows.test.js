/**
 * Regression tests for MAIN-83.
 *
 * The bug: list queries awaited a single request, and the API answers any one request
 * with at most 1,000 rows — so tables past that size were silently cut off. These tests
 * pin down the batching loop that replaced it.
 */
import { describe, it, expect } from 'vitest'
import { fetchAllRows, PAGE_SIZE } from '../fetchAllRows'

/**
 * A stand-in for a Supabase query over `table`: `.range(from, to)` resolves to that slice,
 * as the API would. `ranges` records every range requested.
 */
function fakeQuery(table, { ranges = [], failOnBatch = null } = {}) {
    return () => ({
        range(from, to) {
            ranges.push([from, to])
            if (failOnBatch === ranges.length) {
                return Promise.resolve({ data: null, error: new Error('boom') })
            }
            return Promise.resolve({ data: table.slice(from, to + 1), error: null })
        },
    })
}

const rowsOf = (n) => Array.from({ length: n }, (_, i) => ({ id: `row-${i}` }))

describe('fetchAllRows', () => {
    it('makes one request when the result fits in a single batch', async () => {
        const ranges = []
        const rows = await fetchAllRows(fakeQuery(rowsOf(10), { ranges }))

        expect(rows).toHaveLength(10)
        expect(ranges).toEqual([[0, PAGE_SIZE - 1]])
    })

    it('returns every row of a table larger than one batch', async () => {
        const ranges = []
        const rows = await fetchAllRows(fakeQuery(rowsOf(2680), { ranges }))

        expect(rows).toHaveLength(2680)
        expect(rows[2679].id).toBe('row-2679')
        expect(ranges).toEqual([[0, 999], [1000, 1999], [2000, 2999]])
    })

    it('ends with an empty batch when the size is an exact multiple of a batch', async () => {
        const ranges = []
        const rows = await fetchAllRows(fakeQuery(rowsOf(2000), { ranges }))

        expect(rows).toHaveLength(2000)
        expect(ranges).toHaveLength(3)
    })

    it('returns an empty list for an empty result', async () => {
        expect(await fetchAllRows(fakeQuery([]))).toEqual([])
    })

    it('drops a row repeated across a batch boundary', async () => {
        // A row inserted mid-fetch pushes the last row of batch 1 into batch 2 as well.
        const table = rowsOf(1500)
        let call = 0
        const buildQuery = () => ({
            range(from, to) {
                call += 1
                const slice = call === 2 ? table.slice(from - 1, to) : table.slice(from, to + 1)
                return Promise.resolve({ data: slice, error: null })
            },
        })

        const rows = await fetchAllRows(buildQuery)

        expect(rows).toHaveLength(1500)
        expect(new Set(rows.map(r => r.id)).size).toBe(1500)
    })

    it('throws instead of returning a partial list when a batch fails', async () => {
        await expect(
            fetchAllRows(fakeQuery(rowsOf(2500), { failOnBatch: 2 }))
        ).rejects.toThrow('boom')
    })

    it('builds a fresh query for every batch', async () => {
        let built = 0
        const table = rowsOf(1200)
        await fetchAllRows(() => {
            built += 1
            return fakeQuery(table)()
        })

        expect(built).toBe(2)
    })
})
