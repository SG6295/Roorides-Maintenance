import { useMemo, useState } from 'react'
import { Popover, PopoverButton, PopoverPanel } from '@headlessui/react'
import { ChevronDownIcon, ArrowUpIcon, ArrowDownIcon, MagnifyingGlassIcon, CheckIcon, FunnelIcon } from '@heroicons/react/20/solid'
import { useListFacet } from '../../../hooks/useServerList'
import { isActiveFilter, tickListFilter, sortLabels, columnFilterKey } from '../../../utils/listQuery'

/**
 * The menu behind every column header (MAIN-151): sort, then a filter — a tick list of the
 * column's values with counts, or a "between" for dates and numbers.
 *
 * Column definition (shared with DataTable):
 *   { key, label, sortKey?, filter?: 'values'|'date'|'number', filterKey?, formatValue? }
 */

export default function ColumnMenu({ column, list, onSort, onFilter, trigger = 'header' }) {
    const fKey = columnFilterKey(column)
    const spec = list.state.filters[fKey]
    const filtered = isActiveFilter(spec)
    const sorted = column.sortKey && list.state.sort === column.sortKey
    const canSort = !!column.sortKey
    const canFilter = !!column.filter

    if (!canSort && !canFilter) {
        return <span>{column.label}</span>
    }

    const buttonClass = trigger === 'header'
        ? `inline-flex items-center gap-1 -ml-1.5 px-1.5 py-1 rounded-md uppercase tracking-wider text-xs font-medium hover:bg-gray-200/70 focus:outline-none focus:ring-2 focus:ring-blue-500 ${filtered ? 'bg-blue-100 text-blue-800' : sorted ? 'text-blue-800' : 'text-gray-600'}`
        : `w-full flex items-center justify-between gap-2 px-3 min-h-[44px] rounded-lg border text-sm ${filtered ? 'border-blue-300 bg-blue-50 text-blue-800' : 'border-gray-200 bg-white text-gray-800'}`

    return (
        <Popover className={trigger === 'header' ? 'inline-block' : 'block'}>
            <PopoverButton className={buttonClass} aria-label={`${column.label}: sort and filter`}>
                <span>{column.label}</span>
                {filtered
                    ? <FunnelIcon className="w-3.5 h-3.5 text-blue-600" aria-label="filtered" />
                    : sorted
                        ? (list.state.dir === 'asc'
                            ? <ArrowUpIcon className="w-3.5 h-3.5 text-blue-600" aria-label="sorted ascending" />
                            : <ArrowDownIcon className="w-3.5 h-3.5 text-blue-600" aria-label="sorted descending" />)
                        : <ChevronDownIcon className="w-3.5 h-3.5 text-gray-400" aria-hidden="true" />}
            </PopoverButton>
            <PopoverPanel
                anchor="bottom start"
                className="z-50 mt-1 w-72 max-h-[var(--anchor-max-height)] overflow-y-auto rounded-lg bg-white shadow-xl ring-1 ring-black/10 p-2 normal-case tracking-normal font-normal text-sm text-gray-900"
            >
                {({ close }) => (
                    <div className="flex flex-col gap-1">
                        {canSort && (
                            <SortOptions column={column} list={list} onSort={(dir) => { onSort(column.sortKey, dir); close() }} />
                        )}
                        {canSort && canFilter && <div className="h-px bg-gray-200 my-1" />}
                        {column.filter === 'values' && (
                            <ValuesFilter column={column} list={list} spec={spec} onApply={(next) => { onFilter(fKey, next); close() }} onCancel={close} />
                        )}
                        {(column.filter === 'date' || column.filter === 'number') && (
                            <BetweenFilter column={column} spec={spec} onApply={(next) => { onFilter(fKey, next); close() }} onCancel={close} />
                        )}
                    </div>
                )}
            </PopoverPanel>
        </Popover>
    )
}

function SortOptions({ column, list, onSort }) {
    const [ascLabel, descLabel] = sortLabels(column)
    const active = list.state.sort === column.sortKey ? list.state.dir : null
    return (
        <>
            {[['asc', ascLabel], ['desc', descLabel]].map(([dir, label]) => (
                <button
                    key={dir}
                    type="button"
                    onClick={() => onSort(dir)}
                    className={`flex items-center gap-2 text-left px-2.5 min-h-[40px] rounded-md ${active === dir ? 'bg-blue-50 text-blue-800 font-semibold' : 'hover:bg-gray-100'}`}
                >
                    <span className="w-4">{active === dir && <CheckIcon className="w-4 h-4" aria-hidden="true" />}</span>
                    {label}
                </button>
            ))}
        </>
    )
}

function SectionLabel({ children }) {
    return <div className="px-1.5 pt-1 text-xs font-semibold text-gray-600 uppercase tracking-wide">{children}</div>
}

function MenuFooter({ onCancel, onApply, disabled }) {
    return (
        <div className="flex justify-end gap-2 pt-2">
            <button type="button" onClick={onCancel} className="px-3.5 min-h-[40px] border border-gray-300 rounded-md bg-white text-gray-700 hover:bg-gray-50">Cancel</button>
            <button type="button" onClick={onApply} disabled={disabled} className="px-4 min-h-[40px] rounded-md bg-blue-600 text-white font-semibold hover:bg-blue-700 disabled:opacity-50">Apply</button>
        </div>
    )
}

function ValuesFilter({ column, list, spec, onApply, onCancel }) {
    const fKey = columnFilterKey(column)
    const { data: facet = [], isLoading, isError } = useListFacet(list.rpc, list.keyBase, list.state, fKey, true)
    const allValues = useMemo(() => facet.map(f => f.value), [facet])
    const [ticked, setTicked] = useState(null)
    const [search, setSearch] = useState('')

    const label = v => (v === null || v === undefined ? '(Blank)' : (column.formatValue ? column.formatValue(v) : v))
    const effective = ticked ?? (spec?.values ? spec.values : allValues)
    const isTicked = v => effective.includes(v)
    const term = search.trim().toLowerCase()
    const visible = term ? facet.filter(f => String(label(f.value)).toLowerCase().includes(term)) : facet

    const toggle = v => setTicked(isTicked(v) ? effective.filter(x => x !== v) : [...effective, v])
    const selectAll = () => setTicked([...new Set([...effective, ...visible.map(f => f.value)])])
    const clear = () => {
        const hide = new Set(visible.map(f => f.value))
        setTicked(effective.filter(v => !hide.has(v)))
    }

    return (
        <>
            <SectionLabel>Filter by values</SectionLabel>
            <label className="relative flex items-center">
                <MagnifyingGlassIcon className="w-4 h-4 text-gray-500 absolute left-2.5" aria-hidden="true" />
                <input
                    value={search}
                    onChange={e => setSearch(e.target.value)}
                    placeholder={`Search ${column.label.toLowerCase()}`}
                    aria-label={`Search ${column.label}`}
                    className="w-full min-h-[40px] pl-8 pr-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:outline-none"
                />
            </label>
            <div className="flex gap-3 px-1.5 py-1 text-xs">
                <button type="button" onClick={selectAll} className="text-blue-600 font-medium hover:underline">Select all</button>
                <button type="button" onClick={clear} className="text-blue-600 font-medium hover:underline">Clear</button>
            </div>
            <div className="max-h-52 overflow-y-auto border-y border-gray-100">
                {isLoading && <div className="px-2 py-3 text-gray-500">Loading values…</div>}
                {isError && <div className="px-2 py-3 text-red-700">Couldn&apos;t load the values.</div>}
                {!isLoading && visible.length === 0 && <div className="px-2 py-3 text-gray-500">No values</div>}
                {visible.map(f => (
                    <label key={f.value ?? '__blank'} className="flex items-center gap-2.5 px-2 min-h-[36px] cursor-pointer hover:bg-gray-50">
                        <input
                            type="checkbox"
                            checked={isTicked(f.value)}
                            onChange={() => toggle(f.value)}
                            className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                        />
                        <span className="flex-1 truncate">{label(f.value)}</span>
                        <span className="text-xs text-gray-500 tabular-nums">{f.n}</span>
                    </label>
                ))}
            </div>
            <MenuFooter
                onCancel={onCancel}
                disabled={isLoading}
                onApply={() => onApply(ticked === null ? (spec ?? null) : tickListFilter(effective, allValues))}
            />
        </>
    )
}

function BetweenFilter({ column, spec, onApply, onCancel }) {
    const isDate = column.filter === 'date'
    const [lo, setLo] = useState((isDate ? spec?.from : spec?.min) ?? '')
    const [hi, setHi] = useState((isDate ? spec?.to : spec?.max) ?? '')
    const bad = lo !== '' && hi !== '' && (isDate ? lo > hi : Number(lo) > Number(hi))

    const apply = () => {
        if (lo === '' && hi === '') return onApply(null)
        const next = {}
        if (lo !== '') next[isDate ? 'from' : 'min'] = lo
        if (hi !== '') next[isDate ? 'to' : 'max'] = hi
        onApply(next)
    }

    const inputClass = 'w-full min-h-[40px] px-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:outline-none'
    return (
        <>
            <SectionLabel>Between</SectionLabel>
            <div className="flex gap-2 px-0.5">
                <label className="flex-1 flex flex-col gap-1 text-xs text-gray-600">From
                    <input type={isDate ? 'date' : 'number'} value={lo} onChange={e => setLo(e.target.value)} className={inputClass} />
                </label>
                <label className="flex-1 flex flex-col gap-1 text-xs text-gray-600">To
                    <input type={isDate ? 'date' : 'number'} value={hi} onChange={e => setHi(e.target.value)} className={inputClass} />
                </label>
            </div>
            {bad && <p className="px-1.5 text-xs text-red-700">“From” is after “To”.</p>}
            {isDate && <p className="px-1.5 text-xs text-gray-500">Indian dates. This narrows inside the date range above the table.</p>}
            <MenuFooter onCancel={onCancel} onApply={apply} disabled={bad} />
        </>
    )
}
