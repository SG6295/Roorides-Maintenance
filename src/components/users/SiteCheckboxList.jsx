import { useMemo, useState } from 'react'
import { MagnifyingGlassIcon } from '@heroicons/react/24/outline'
import { formatSiteLabel } from '../../utils/siteLabel'

/**
 * Multi-site picker shared by AddUserModal and EditUserModal. Supervisors are
 * RLS-scoped through user_sites, so this is what decides what they can see.
 *
 * Deliberately checkboxes rather than a chip combobox: there are ~68 sites and one
 * supervisor holds 49 of them, which a chip list cannot display usably.
 *
 * Callers pass every site, active or not. An inactive site is greyed and sorted last,
 * and its checkbox is disabled *unless it is already ticked* — that blocks new
 * assignments to a school that has left without hiding an existing assignment someone
 * needs to remove.
 */
export default function SiteCheckboxList({ sites = [], selected = [], onToggle, loading = false }) {
    const [query, setQuery] = useState('')

    // Inactive last, then alphabetical. Sites arrive ordered by name already, so this
    // only has to lift the active ones above the inactive ones.
    const ordered = useMemo(() => {
        return [...sites].sort((a, b) => {
            if (!!a.is_active !== !!b.is_active) return a.is_active ? -1 : 1
            return (a.name ?? '').localeCompare(b.name ?? '')
        })
    }, [sites])

    // A selected site always stays visible, even when the filter excludes it —
    // otherwise ticking a box makes it vanish and there is no way to untick it.
    const visible = useMemo(() => {
        const q = query.trim().toLowerCase()
        if (!q) return ordered
        return ordered.filter(site =>
            selected.includes(site.id) || formatSiteLabel(site).toLowerCase().includes(q)
        )
    }, [ordered, query, selected])

    if (loading) {
        return <p className="text-sm text-gray-500">Loading sites...</p>
    }

    if (sites.length === 0) {
        return <p className="text-sm text-gray-500">No sites available.</p>
    }

    return (
        <>
            <div className="relative mb-2">
                <MagnifyingGlassIcon className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                <input
                    type="text"
                    value={query}
                    onChange={e => setQuery(e.target.value)}
                    placeholder="Search sites..."
                    autoComplete="off"
                    className="w-full rounded-lg border border-gray-300 py-2 pl-9 pr-3 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
                />
            </div>

            <div className="max-h-72 overflow-y-auto border border-gray-300 rounded-lg divide-y divide-gray-100">
                {visible.length === 0 && (
                    <p className="px-3 py-4 text-sm text-gray-500">
                        No sites match &ldquo;{query}&rdquo;.
                    </p>
                )}
                {visible.map(site => {
                    const isSelected = selected.includes(site.id)
                    // Already-ticked inactive sites stay clickable so they can be removed.
                    const isDisabled = !site.is_active && !isSelected

                    return (
                        <label
                            key={site.id}
                            className={`flex items-center gap-3 px-3 py-2 ${
                                isDisabled ? 'cursor-not-allowed bg-gray-50' : 'cursor-pointer hover:bg-gray-50'
                            }`}
                        >
                            <input
                                type="checkbox"
                                checked={isSelected}
                                disabled={isDisabled}
                                onChange={() => onToggle(site.id)}
                                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500 disabled:cursor-not-allowed disabled:opacity-50"
                            />
                            <span className={`text-sm ${site.is_active ? 'text-gray-700' : 'text-gray-400'}`}>
                                {formatSiteLabel(site)}
                                {!site.is_active && (
                                    <span className="ml-2 text-xs italic">inactive</span>
                                )}
                            </span>
                        </label>
                    )
                })}
            </div>

            {/* Counts the whole selection, not just what survived the filter. */}
            {selected.length > 0 && (
                <p className="mt-1 text-xs text-gray-500">
                    {selected.length} site{selected.length > 1 ? 's' : ''} selected
                </p>
            )}
        </>
    )
}
