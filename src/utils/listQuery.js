/**
 * The state of a sortable, filterable list (MAIN-151), and how it travels in the address.
 *
 * Every list keeps its sort, filters, search, page and date range in the URL, so a reload
 * or a shared link opens the same view — and so MAIN-152's Analytics drill-down can open a
 * list with filters already set, in a new tab that remembers nothing else.
 *
 * Address format (readable on purpose):
 *   q=brake                      the search box
 *   sort=site&dir=asc            sort column and direction
 *   page=3                       page number (1 when absent)
 *   from=2026-11-01&to=2026-11-30   the date range box (IST dates)
 *   f.site=BWIS&f.site=KUNS      a tick-list filter, one entry per ticked value;
 *                                an empty value means "(Blank)"
 *   min.value=1000&max.value=5000   a number between
 *   from.raised_on=2026-11-10&to.raised_on=2026-11-20   a date between
 *
 *   an.from=…&an.to=…&an.site=…&an.acceptance=Violated   opened from an Analytics number
 *                                (MAIN-152, src/utils/analyticsDrill.js); while present the
 *                                Analytics period replaces from/to
 *
 * The state turns into the `p_query` the database's list functions take (list_query,
 * migration main151_list_engine) with `toServerQuery`.
 */
import { parseAnalytics, appendAnalytics, analyticsToServer } from './analyticsDrill'

/** A filter on one column: { values: (string|null)[] } or { min, max } or { from, to }. */

export const DEFAULT_PAGE_SIZE = 50

/**
 * @param {URLSearchParams} params
 * @param {{ sort: string, dir: 'asc'|'desc', from?: string, to?: string }} defaults
 */
export function parseListState(params, defaults) {
    const filters = {}
    const put = (key, patch) => { filters[key] = { ...(filters[key] || {}), ...patch } }

    for (const [name, raw] of params.entries()) {
        const dot = name.indexOf('.')
        if (dot <= 0) continue
        const kind = name.slice(0, dot)
        const key = name.slice(dot + 1)
        if (!key) continue
        if (kind === 'f') {
            const prev = filters[key]?.values || []
            put(key, { values: [...prev, raw === '' ? null : raw] })
        } else if (kind === 'min' || kind === 'max' || kind === 'from' || kind === 'to') {
            if (raw !== '') put(key, { [kind]: raw })
        }
    }

    const dir = params.get('dir')
    const page = parseInt(params.get('page') || '1', 10)
    const analytics = parseAnalytics(params)
    return {
        ...(analytics ? { analytics } : {}),
        search: params.get('q') || '',
        sort: params.get('sort') || defaults.sort,
        dir: dir === 'asc' || dir === 'desc' ? dir : defaults.dir,
        page: Number.isFinite(page) && page > 0 ? page : 1,
        from: params.has('from') ? params.get('from') : (defaults.from ?? ''),
        to: params.has('to') ? params.get('to') : (defaults.to ?? ''),
        filters,
    }
}

/**
 * The state as URL parameters. Sort and direction are left out when they are the
 * defaults, so a plain link stays short; the date range is always written, so a shared
 * link opens the same period whatever month it is opened in — or, for a list opened from
 * Analytics, the Analytics selection instead.
 */
export function listStateToParams(state, defaults) {
    const p = new URLSearchParams()
    if (state.search) p.set('q', state.search)
    if (state.sort !== defaults.sort || state.dir !== defaults.dir) {
        p.set('sort', state.sort)
        p.set('dir', state.dir)
    }
    if (state.page > 1) p.set('page', String(state.page))
    if (state.analytics) appendAnalytics(p, state.analytics)
    else {
        p.set('from', state.from || '')
        p.set('to', state.to || '')
    }

    for (const [key, spec] of Object.entries(state.filters || {})) {
        if (!isActiveFilter(spec)) continue
        if (spec.values) for (const v of spec.values) p.append(`f.${key}`, v ?? '')
        for (const kind of ['min', 'max', 'from', 'to']) {
            if (spec[kind] !== undefined && spec[kind] !== null && spec[kind] !== '') {
                p.set(`${kind}.${key}`, String(spec[kind]))
            }
        }
    }
    return p
}

/** Whether a column filter narrows anything. An empty tick list is still a filter (nothing passes). */
export function isActiveFilter(spec) {
    if (!spec) return false
    if (Array.isArray(spec.values)) return true
    return ['min', 'max', 'from', 'to'].some(k => spec[k] !== undefined && spec[k] !== null && spec[k] !== '')
}

/**
 * The database's p_query for a page of rows, or — with `facet` — for one column's values.
 * A facet ignores the page and sort; the database also ignores that column's own filter.
 */
export function toServerQuery(state, { pageSize = DEFAULT_PAGE_SIZE, facet } = {}) {
    const filters = {}
    for (const [key, spec] of Object.entries(state.filters || {})) {
        if (!isActiveFilter(spec)) continue
        const out = {}
        if (spec.values) out.values = spec.values
        for (const kind of ['min', 'max', 'from', 'to']) {
            if (spec[kind] !== undefined && spec[kind] !== null && spec[kind] !== '') out[kind] = spec[kind]
        }
        filters[key] = out
    }
    const q = {
        from: state.analytics ? null : (state.from || null),
        to: state.analytics ? null : (state.to || null),
        search: state.search?.trim() || null,
        filters,
    }
    if (state.analytics) q.analytics = analyticsToServer(state.analytics)
    if (facet) return { ...q, facet }
    return { ...q, sort: state.sort, dir: state.dir, page: state.page, page_size: pageSize }
}

/**
 * Apply a tick-list choice. Every listed value ticked means no filter at all, so new
 * values that appear later are not silently left out.
 *
 * @param {(string|null)[]} ticked
 * @param {(string|null)[]} allValues  the column's values as the menu listed them
 */
export function tickListFilter(ticked, allValues) {
    const chosen = new Set(ticked)
    if (allValues.length > 0 && allValues.every(v => chosen.has(v))) return null
    return { values: [...chosen] }
}

/** Short description of a filter, for the "Filtered by" strip. */
export function describeFilter(spec, formatValue = v => v) {
    if (!spec) return ''
    if (Array.isArray(spec.values)) {
        if (spec.values.length === 0) return 'none'
        const labels = spec.values.map(v => (v === null ? '(Blank)' : formatValue(v)))
        return labels.length <= 2 ? labels.join(', ') : `${labels.slice(0, 2).join(', ')} +${labels.length - 2} more`
    }
    const lo = spec.min ?? spec.from
    const hi = spec.max ?? spec.to
    if (lo !== undefined && hi !== undefined) return `${formatValue(lo)} – ${formatValue(hi)}`
    if (lo !== undefined) return `from ${formatValue(lo)}`
    if (hi !== undefined) return `up to ${formatValue(hi)}`
    return ''
}

/** The sort menu's two labels, worded for the column's kind. */
export function sortLabels(column) {
    if (column.filter === 'date') return ['Oldest first', 'Newest first']
    if (column.filter === 'number') return ['Smallest first', 'Largest first']
    return ['Sort A → Z', 'Sort Z → A']
}

/** The row field a column filters on (a date column filters its IST day, `raised_on`). */
export function columnFilterKey(column) {
    return column.filterKey || column.key
}
