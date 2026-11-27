import { describe, it, expect } from 'vitest'
import { analyticsHref, parseAnalytics, analyticsToServer, describeDrill, periodText } from '../analyticsDrill'
import { parseListState, listStateToParams, toServerQuery } from '../listQuery'

const defaults = { sort: 'created_at', dir: 'desc', from: '2026-11-01', to: '2026-11-30' }
const selection = { from: '2026-01-01', to: '2026-11-30', sites: ['BWIS', 'KUNS'] }
const paramsOf = href => new URLSearchParams(href.split('?')[1])

describe('analyticsHref', () => {
    it('carries the period, every site and the bucket clicked', () => {
        const href = analyticsHref('tickets', selection, { completion: 'Violated', job_card_type: 'InHouse' })
        expect(href.startsWith('/tickets?')).toBe(true)
        expect(parseAnalytics(paramsOf(href))).toEqual({
            from: '2026-01-01', to: '2026-11-30', sites: ['BWIS', 'KUNS'],
            where: { completion: 'Violated', job_card_type: 'InHouse' },
        })
    })

    it('still reads as a drill-down with no period, sites or bucket (Currently Overdue, Total)', () => {
        expect(parseAnalytics(paramsOf(analyticsHref('tickets', {}, { overdue: 'true' }))))
            .toEqual({ from: '', to: '', sites: [], where: { overdue: 'true' } })
        expect(parseAnalytics(paramsOf(analyticsHref('issues', selection, {})))).toBeDefined()
    })

    it('keeps a site name with spaces or an ampersand intact', () => {
        const href = analyticsHref('issues', { ...selection, sites: ['A & B School'] }, { category: 'Body & Paint' })
        const d = parseAnalytics(paramsOf(href))
        expect(d.sites).toEqual(['A & B School'])
        expect(d.where.category).toBe('Body & Paint')
    })
})

describe('a list opened from Analytics', () => {
    const href = analyticsHref('tickets', selection, { acceptance: 'Violated' })

    it('is not a drill-down without an.* parameters', () => {
        expect(parseListState(new URLSearchParams('from=2026-10-01&to=2026-10-31'), defaults).analytics).toBeUndefined()
    })

    it('sends the selection and no list date window to the database', () => {
        const state = parseListState(paramsOf(href), defaults)
        const q = toServerQuery(state)
        expect(q.from).toBeNull()
        expect(q.to).toBeNull()
        expect(q.analytics).toEqual({
            from: '2026-01-01', to: '2026-11-30', sites: ['BWIS', 'KUNS'], where: { acceptance: 'Violated' },
        })
    })

    it('keeps the selection, not a date range, when its own filters change', () => {
        const state = parseListState(paramsOf(href), defaults)
        const next = listStateToParams({ ...state, filters: { site: { values: ['BWIS'] } } }, defaults)
        expect(next.has('from')).toBe(false)
        expect(next.getAll('f.site')).toEqual(['BWIS'])
        expect(parseListState(next, defaults).analytics).toEqual(state.analytics)
    })

    it('goes back to the plain list with its default period once the selection is dropped', () => {
        const state = parseListState(paramsOf(href), defaults)
        const plain = listStateToParams({ ...state, analytics: undefined, from: defaults.from, to: defaults.to }, defaults)
        expect([...plain.keys()].some(k => k.startsWith('an.'))).toBe(false)
        expect(plain.get('from')).toBe('2026-11-01')
        expect(toServerQuery(parseListState(plain, defaults)).analytics).toBeUndefined()
    })
})

describe('describeDrill', () => {
    it('says what was clicked, the period and the sites', () => {
        expect(describeDrill('tickets', parseAnalytics(paramsOf(analyticsHref('tickets', selection, { acceptance: 'Violated' })))))
            .toEqual(['Acceptance SLA: Late', 'tickets raised 1 Jan – 30 Nov 2026', 'sites BWIS, KUNS'])
    })

    it('says issues are placed by their ticket\'s raise day', () => {
        const parts = describeDrill('issues', { from: '2026-01-01', to: '2026-11-30', sites: [], where: { rating_pending: 'true' } })
        expect(parts).toEqual(['Rating pending', 'on tickets raised 1 Jan – 30 Nov 2026', 'all sites'])
    })

    it('reads a live figure with no period', () => {
        expect(describeDrill('tickets', { from: '', to: '', sites: ['BWIS'], where: { overdue: 'true' } }))
            .toEqual(['Currently overdue', 'site BWIS'])
    })

    it('shortens a long site list', () => {
        const parts = describeDrill('tickets', { ...selection, sites: ['A', 'B', 'C', 'D', 'E'], where: {} })
        expect(parts).toEqual(['All tickets', 'tickets raised 1 Jan – 30 Nov 2026', 'sites A, B, C +2 more'])
    })
})

describe('periodText', () => {
    it('shows both years when the period crosses one', () => {
        expect(periodText('2025-12-01', '2026-11-30')).toBe('1 Dec 2025 – 30 Nov 2026')
    })
    it('is null with no period', () => {
        expect(periodText('', '')).toBeNull()
    })
})

describe('analyticsToServer', () => {
    it('is undefined without a drill-down', () => {
        expect(analyticsToServer(undefined)).toBeUndefined()
    })
})
