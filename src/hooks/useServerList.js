import { useCallback, useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useQuery, keepPreviousData } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { parseListState, listStateToParams, toServerQuery } from '../utils/listQuery'

/**
 * A list's sort, filters, search, page and date range, kept in the address (MAIN-151).
 *
 * `defaults` must be stable (a module constant or memoised): { sort, dir, from, to }.
 * Any change but paging goes back to page 1. Typing in the search box replaces the history
 * entry instead of adding one per keystroke.
 */
export function useListState(defaults) {
    const [params, setParams] = useSearchParams()
    const state = useMemo(() => parseListState(params, defaults), [params, defaults])

    // A list opened with no date range in its address gets the default written in, so
    // that copying the address always shares the same period.
    useEffect(() => {
        if (!params.has('from')) {
            setParams(prev => listStateToParams(parseListState(prev, defaults), defaults), { replace: true })
        }
    }, [params, setParams, defaults])

    const update = useCallback((patchFn, { keepPage = false, replace = false } = {}) => {
        setParams(prev => {
            const cur = parseListState(prev, defaults)
            const next = { ...cur, ...patchFn(cur) }
            if (!keepPage) next.page = 1
            return listStateToParams(next, defaults)
        }, { replace })
    }, [setParams, defaults])

    return {
        state,
        setSearch: search => update(() => ({ search }), { replace: true }),
        setSort: (sort, dir) => update(() => ({ sort, dir })),
        setFilter: (key, spec) => update(cur => {
            const filters = { ...cur.filters }
            if (spec) filters[key] = spec
            else delete filters[key]
            return { filters }
        }),
        clearAll: () => update(() => ({ filters: {}, search: '', sort: defaults.sort, dir: defaults.dir })),
        setPage: page => update(() => ({ page }), { keepPage: true }),
        setDateRange: ({ start, end }) => update(() => ({ from: start || '', to: end || '' })),
    }
}

/** `value`, settled for `ms` — so the database is asked once the typing stops. */
export function useDebouncedValue(value, ms = 300) {
    const [settled, setSettled] = useState(value)
    useEffect(() => {
        const t = setTimeout(() => setSettled(value), ms)
        return () => clearTimeout(t)
    }, [value, ms])
    return settled
}

async function callList(rpc, pQuery) {
    const { data, error } = await supabase.rpc(rpc, { p_query: pQuery })
    if (error) throw error
    return data
}

/**
 * One page of a database-sorted list: { total, rows }.
 *
 * The cache key starts with `keyBase` ('tickets', 'issues', 'job_cards'), so every mutation
 * that already invalidates that key refreshes the list too. The previous page stays on
 * screen while the next one loads.
 */
export function useServerList(rpc, keyBase, state, { pageSize } = {}) {
    const search = useDebouncedValue(state.search)
    const pQuery = toServerQuery({ ...state, search }, { pageSize })
    return useQuery({
        queryKey: [keyBase, 'list', pQuery],
        queryFn: () => callList(rpc, pQuery),
        placeholderData: keepPreviousData,
    })
}

/**
 * One column's values with counts, under every other filter — asked for only while the
 * column's menu is open (`enabled`), or always for the status shortcuts.
 */
export function useListFacet(rpc, keyBase, state, column, enabled = true) {
    const search = useDebouncedValue(state.search)
    const pQuery = toServerQuery({ ...state, search }, { facet: column })
    return useQuery({
        queryKey: [keyBase, 'facet', pQuery],
        queryFn: () => callList(rpc, pQuery).then(d => d?.values || []),
        enabled: enabled && !!column,
        placeholderData: keepPreviousData,
    })
}

/** Every row the list's filters match, in its sort order — for Export. */
export async function fetchAllListRows(rpc, state) {
    const pageSize = 5000
    const rows = []
    for (let page = 1; ; page++) {
        const data = await callList(rpc, toServerQuery({ ...state, page }, { pageSize }))
        rows.push(...(data?.rows || []))
        if (rows.length >= (data?.total ?? 0) || (data?.rows || []).length < pageSize) return rows
    }
}
