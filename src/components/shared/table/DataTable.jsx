import { Popover, PopoverButton, PopoverPanel } from '@headlessui/react'
import { AdjustmentsHorizontalIcon, ChevronLeftIcon, ChevronRightIcon, XMarkIcon, MagnifyingGlassIcon } from '@heroicons/react/20/solid'
import ColumnMenu from './ColumnMenu'
import { describeDrill } from '../../../utils/analyticsDrill'
import { describeFilter, isActiveFilter, DEFAULT_PAGE_SIZE, columnFilterKey, sortLabels } from '../../../utils/listQuery'

/**
 * A sortable, filterable table (MAIN-151). One look for every list: each header opens
 * ColumnMenu, the rows come already sorted, filtered and paged (by the database for the big
 * lists), and the page controls sit underneath.
 *
 * `list` = useListState(...) plus { rpc, keyBase }; `columns` as ColumnMenu describes, plus
 * `render(row)`, optional `align: 'right'` and `headerClassName` / `cellClassName`.
 */
export default function DataTable({
    list, columns, rows = [], total = 0, loading = false, stale = false,
    rowKey = r => r.id, onRowClick, emptyText = 'Nothing matches these filters.',
    pageSize = DEFAULT_PAGE_SIZE,
}) {
    return (
        <div className="bg-white rounded-lg shadow border border-gray-200">
            <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200 text-sm">
                    <thead className="bg-gray-50">
                        <tr>
                            {columns.map(c => (
                                <th
                                    key={c.key}
                                    scope="col"
                                    className={`px-4 py-2.5 text-xs font-medium text-gray-600 uppercase tracking-wider whitespace-nowrap ${c.align === 'right' ? 'text-right' : 'text-left'} ${list.state.filters[columnFilterKey(c)] ? 'bg-blue-50' : ''} ${c.headerClassName || ''}`}
                                >
                                    <ColumnMenu column={c} list={list} onSort={list.setSort} onFilter={list.setFilter} />
                                </th>
                            ))}
                        </tr>
                    </thead>
                    <tbody className={`bg-white divide-y divide-gray-100 ${stale ? 'opacity-60 transition-opacity' : ''}`}>
                        {loading && rows.length === 0 && (
                            <tr><td colSpan={columns.length} className="px-4 py-12 text-center text-gray-600">Loading…</td></tr>
                        )}
                        {!loading && rows.length === 0 && (
                            <tr><td colSpan={columns.length} className="px-4 py-12 text-center text-gray-600">{emptyText}</td></tr>
                        )}
                        {rows.map(row => (
                            <tr
                                key={rowKey(row)}
                                onClick={onRowClick ? () => onRowClick(row) : undefined}
                                className={`hover:bg-gray-50 ${onRowClick ? 'cursor-pointer' : ''}`}
                            >
                                {columns.map(c => (
                                    <td key={c.key} className={`px-4 py-3 ${c.align === 'right' ? 'text-right' : ''} ${c.cellClassName ?? 'whitespace-nowrap'}`}>
                                        {c.render ? c.render(row) : (row[c.key] ?? '—')}
                                    </td>
                                ))}
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
            <Pagination page={list.state.page} pageSize={pageSize} total={total} onPage={list.setPage} />
        </div>
    )
}

export function Pagination({ page, pageSize, total, onPage }) {
    const pages = Math.max(1, Math.ceil(total / pageSize))
    if (total === 0) return null
    const first = (page - 1) * pageSize + 1
    const last = Math.min(total, page * pageSize)
    const start = Math.max(1, Math.min(page - 2, pages - 4))
    const numbers = Array.from({ length: Math.min(5, pages) }, (_, i) => start + i)
    const btn = 'min-w-[40px] min-h-[40px] px-2 rounded-md border text-sm disabled:opacity-40'

    return (
        <div className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 border-t border-gray-200 text-sm text-gray-600">
            <span>Showing {first.toLocaleString('en-IN')}–{last.toLocaleString('en-IN')} of {total.toLocaleString('en-IN')}</span>
            {pages > 1 && (
                <nav className="flex gap-1" aria-label="Pages">
                    <button type="button" className={`${btn} border-gray-300 bg-white`} disabled={page <= 1} onClick={() => onPage(page - 1)} aria-label="Previous page">
                        <ChevronLeftIcon className="w-4 h-4 mx-auto" />
                    </button>
                    {numbers.map(n => (
                        <button
                            key={n}
                            type="button"
                            onClick={() => onPage(n)}
                            aria-current={n === page ? 'page' : undefined}
                            className={`${btn} ${n === page ? 'border-blue-600 bg-blue-600 text-white font-semibold' : 'border-gray-300 bg-white text-gray-700 hover:bg-gray-50'}`}
                        >
                            {n}
                        </button>
                    ))}
                    <button type="button" className={`${btn} border-gray-300 bg-white`} disabled={page >= pages} onClick={() => onPage(page + 1)} aria-label="Next page">
                        <ChevronRightIcon className="w-4 h-4 mx-auto" />
                    </button>
                </nav>
            )}
        </div>
    )
}

/** The list's one search box. */
export function ListSearch({ list, placeholder }) {
    return (
        <label className="relative flex items-center flex-1 min-w-[200px] sm:max-w-md">
            <MagnifyingGlassIcon className="w-5 h-5 text-gray-500 absolute left-3" aria-hidden="true" />
            <input
                type="search"
                value={list.state.search}
                onChange={e => list.setSearch(e.target.value)}
                placeholder={placeholder}
                aria-label={placeholder}
                className="w-full pl-10 pr-3 min-h-[44px] text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:outline-none"
            />
        </label>
    )
}

/**
 * "Filtered by:" — every active filter and a non-default sort, each removable, plus Clear all.
 * Renders nothing when the list is unfiltered.
 */
export function ActiveFilters({ list, columns, defaults, extra = null }) {
    const byFilterKey = Object.fromEntries(columns.map(c => [columnFilterKey(c), c]))
    const bySortKey = Object.fromEntries(columns.filter(c => c.sortKey).map(c => [c.sortKey, c]))
    const active = Object.entries(list.state.filters).filter(([, spec]) => isActiveFilter(spec))
    const customSort = list.state.sort !== defaults.sort || list.state.dir !== defaults.dir
    const sortCol = bySortKey[list.state.sort]
    if (active.length === 0 && !customSort && !list.state.search && !extra) return null

    const chip = 'inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-md border border-blue-200 bg-blue-50 text-blue-800 text-xs hover:bg-blue-100'
    return (
        <div className="flex flex-wrap items-center gap-2 text-sm">
            <span className="text-gray-600">Filtered by:</span>
            {extra}
            {active.map(([key, spec]) => {
                const col = byFilterKey[key]
                const name = col?.label ?? key
                return (
                    <button key={key} type="button" className={chip} onClick={() => list.setFilter(key, null)} aria-label={`Remove filter ${name}`}>
                        {name}: {describeFilter(spec, col?.formatValue)}
                        <XMarkIcon className="w-3.5 h-3.5" aria-hidden="true" />
                    </button>
                )
            })}
            {customSort && sortCol && (
                <button type="button" className={chip} onClick={() => list.setSort(defaults.sort, defaults.dir)} aria-label="Remove sort">
                    Sorted: {sortCol.label}, {sortChipLabel(sortCol, list.state.dir)}
                    <XMarkIcon className="w-3.5 h-3.5" aria-hidden="true" />
                </button>
            )}
            <button type="button" onClick={list.clearAll} className="px-1 py-1.5 text-blue-600 font-medium hover:underline">Clear all</button>
        </div>
    )
}

function sortChipLabel(column, dir) {
    const label = sortLabels(column)[dir === 'asc' ? 0 : 1]
    return label.startsWith('Sort ') ? label.slice(5) : label.toLowerCase()
}

/** Show or hide columns, for this visit only (as on Invoices, MAIN-98). */
export function ColumnsButton({ columns, visibleKeys, onChange, defaultKeys }) {
    const toggle = key =>
        onChange(visibleKeys.includes(key) ? visibleKeys.filter(k => k !== key) : [...visibleKeys, key])
    return (
        <Popover className="relative">
            <PopoverButton className="inline-flex items-center gap-2 px-3.5 min-h-[44px] text-sm text-gray-700 border border-gray-300 rounded-lg bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500">
                <AdjustmentsHorizontalIcon className="w-4 h-4 text-gray-500" />
                Columns ({visibleKeys.length}/{columns.length})
            </PopoverButton>
            <PopoverPanel anchor="bottom end" className="z-50 mt-1 w-60 rounded-lg bg-white shadow-lg ring-1 ring-black/5 p-3">
                <div className="max-h-80 overflow-y-auto space-y-1">
                    {columns.map(c => (
                        <label key={c.key} className="flex items-center gap-2 text-sm text-gray-700 py-1 cursor-pointer">
                            <input
                                type="checkbox"
                                checked={visibleKeys.includes(c.key)}
                                onChange={() => toggle(c.key)}
                                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                            />
                            {c.label}
                        </label>
                    ))}
                </div>
                <div className="flex justify-between gap-2 pt-3 mt-2 border-t border-gray-100">
                    <button type="button" onClick={() => onChange(columns.map(c => c.key))} className="text-xs text-blue-600 hover:underline">Show all</button>
                    <button type="button" onClick={() => onChange(defaultKeys)} className="text-xs text-gray-600 hover:underline">Reset to default</button>
                </div>
            </PopoverPanel>
        </Popover>
    )
}

/**
 * "From Analytics: Acceptance SLA: Late · tickets raised 1 Jan – 30 Nov 2026 · all sites"
 * on a list opened from an Analytics number (MAIN-152). It stands in for the date range box
 * while it is there; ✕ goes back to the plain list.
 *
 * @param {'tickets'|'issues'} listName
 */
export function AnalyticsOrigin({ list, listName }) {
    const drill = list.state.analytics
    if (!drill) return null
    const parts = describeDrill(listName, drill)
    return (
        <div className="inline-flex items-center gap-2 min-h-[44px] pl-3 pr-1.5 rounded-lg border border-indigo-200 bg-indigo-50 text-sm text-indigo-900 max-w-full">
            <span className="min-w-0">
                <span className="font-semibold">From Analytics:</span> {parts.join(' · ')}
            </span>
            <button
                type="button"
                onClick={list.clearAnalytics}
                className="shrink-0 p-1.5 rounded-md hover:bg-indigo-100"
                aria-label="Show the plain list instead"
                title="Show the plain list instead"
            >
                <XMarkIcon className="w-4 h-4" aria-hidden="true" />
            </button>
        </div>
    )
}
