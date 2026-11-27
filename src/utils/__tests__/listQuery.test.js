import { describe, it, expect } from 'vitest'
import {
    parseListState, listStateToParams, toServerQuery, tickListFilter, describeFilter, isActiveFilter,
} from '../listQuery'

const defaults = { sort: 'created_at', dir: 'desc', from: '2026-11-01', to: '2026-11-30' }

describe('parseListState', () => {
    it('falls back to the defaults on an empty address', () => {
        expect(parseListState(new URLSearchParams(''), defaults)).toEqual({
            search: '', sort: 'created_at', dir: 'desc', page: 1,
            from: '2026-11-01', to: '2026-11-30', filters: {},
        })
    })

    it('reads tick lists, blanks, ranges and dates', () => {
        const s = parseListState(new URLSearchParams(
            'q=brake&sort=site&dir=asc&page=3&from=2026-10-01&to=2026-10-31'
            + '&f.site=BWIS&f.site=KUNS&f.supervisor_name=&min.value=1000&max.value=5000&from.raised_on=2026-10-05'
        ), defaults)
        expect(s.search).toBe('brake')
        expect(s.sort).toBe('site')
        expect(s.dir).toBe('asc')
        expect(s.page).toBe(3)
        expect(s.from).toBe('2026-10-01')
        expect(s.filters).toEqual({
            site: { values: ['BWIS', 'KUNS'] },
            supervisor_name: { values: [null] },
            value: { min: '1000', max: '5000' },
            raised_on: { from: '2026-10-05' },
        })
    })

    it('keeps an explicitly empty date range (all time) rather than the default', () => {
        const s = parseListState(new URLSearchParams('from=&to='), defaults)
        expect(s.from).toBe('')
        expect(s.to).toBe('')
    })

    it('ignores a nonsense page or direction', () => {
        const s = parseListState(new URLSearchParams('page=-2&dir=up'), defaults)
        expect(s.page).toBe(1)
        expect(s.dir).toBe('desc')
    })
})

describe('listStateToParams', () => {
    it('round-trips', () => {
        const address = 'q=brake&sort=site&dir=asc&page=2&from=2026-10-01&to=2026-10-31&f.site=BWIS&f.site=&min.value=10'
        const state = parseListState(new URLSearchParams(address), defaults)
        const again = parseListState(listStateToParams(state, defaults), defaults)
        expect(again).toEqual(state)
    })

    it('leaves out the default sort and page 1, but always writes the dates', () => {
        const p = listStateToParams(parseListState(new URLSearchParams(''), defaults), defaults)
        expect(p.toString()).toBe('from=2026-11-01&to=2026-11-30')
    })
})

describe('toServerQuery', () => {
    const state = parseListState(new URLSearchParams('q=%20ka01%20&f.status=New&min.value=5'), defaults)

    it('builds a page request', () => {
        expect(toServerQuery(state)).toEqual({
            from: '2026-11-01', to: '2026-11-30', search: 'ka01',
            filters: { status: { values: ['New'] }, value: { min: '5' } },
            sort: 'created_at', dir: 'desc', page: 1, page_size: 50,
        })
    })

    it('builds a facet request without paging', () => {
        const q = toServerQuery(state, { facet: 'site' })
        expect(q.facet).toBe('site')
        expect(q.page).toBeUndefined()
        expect(q.filters.status).toEqual({ values: ['New'] })
    })
})

describe('tickListFilter', () => {
    it('everything ticked is no filter', () => {
        expect(tickListFilter(['A', 'B', null], ['A', null, 'B'])).toBeNull()
    })
    it('a subset is a filter, blanks included', () => {
        expect(tickListFilter(['A', null], ['A', 'B', null])).toEqual({ values: ['A', null] })
    })
    it('nothing ticked filters everything out', () => {
        const f = tickListFilter([], ['A', 'B'])
        expect(f).toEqual({ values: [] })
        expect(isActiveFilter(f)).toBe(true)
    })
})

describe('describeFilter', () => {
    it('names up to two values', () => {
        expect(describeFilter({ values: ['A', null] })).toBe('A, (Blank)')
        expect(describeFilter({ values: ['A', 'B', 'C', 'D'] })).toBe('A, B +2 more')
    })
    it('describes ranges', () => {
        expect(describeFilter({ min: '10', max: '20' })).toBe('10 – 20')
        expect(describeFilter({ from: '2026-11-01' })).toBe('from 2026-11-01')
        expect(describeFilter({ max: '5' })).toBe('up to 5')
    })
})
