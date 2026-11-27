import { useListFacet } from '../../hooks/useServerList'

// The status sections, now one-click shortcuts above the table (MAIN-151). Each count is
// the Status column's own values under every other filter, so a site or vehicle filter
// narrows the counts and the rows together (MAIN-82).
const STATUSES = [
    { value: 'New', className: 'bg-yellow-50 text-yellow-800' },
    { value: 'Accepted', className: 'bg-blue-50 text-blue-800' },
    { value: 'Work In Progress', className: 'bg-purple-50 text-purple-800' },
    { value: 'Resolved', className: 'bg-green-50 text-green-800' },
    { value: 'Closed', className: 'bg-gray-50 text-gray-700' },
    { value: 'Rejected', className: 'bg-red-50 text-red-800' },
]

export default function StatusShortcuts({ list }) {
    const { data: facet = [] } = useListFacet(list.rpc, list.keyBase, list.state, 'status')
    const count = Object.fromEntries(facet.map(f => [f.value, f.n]))
    const all = facet.reduce((sum, f) => sum + f.n, 0)
    const chosen = list.state.filters.status?.values
    const only = chosen?.length === 1 ? chosen[0] : null

    const pill = (selected, extra) =>
        `flex-none inline-flex items-center gap-2 px-4 min-h-[44px] rounded-full text-sm font-semibold ${selected ? 'border-2 border-blue-600 ring-1 ring-blue-600/20' : 'border border-gray-200'} ${extra}`

    return (
        <div className="flex gap-2 overflow-x-auto pb-1 sm:flex-wrap sm:overflow-visible" role="group" aria-label="Status shortcuts">
            <button
                type="button"
                aria-pressed={!chosen}
                onClick={() => list.setFilter('status', null)}
                className={pill(!chosen, 'bg-blue-50 text-blue-800')}
            >
                All <span className="bg-white rounded-full px-2 py-0.5 text-xs text-gray-700">{all.toLocaleString('en-IN')}</span>
            </button>
            {STATUSES.map(s => (
                <button
                    key={s.value}
                    type="button"
                    aria-pressed={only === s.value}
                    onClick={() => list.setFilter('status', { values: [s.value] })}
                    className={pill(only === s.value, s.className)}
                >
                    {s.value} <span className="bg-white rounded-full px-2 py-0.5 text-xs text-gray-700">{(count[s.value] ?? 0).toLocaleString('en-IN')}</span>
                </button>
            ))}
        </div>
    )
}
