/**
 * Multi-site picker shared by AddUserModal and EditUserModal. Supervisors are
 * RLS-scoped through user_sites, so this is what decides what they can see.
 */
export default function SiteCheckboxList({ sites = [], selected = [], onToggle, loading = false }) {
    if (loading) {
        return <p className="text-sm text-gray-500">Loading sites...</p>
    }

    if (sites.length === 0) {
        return <p className="text-sm text-gray-500">No sites available.</p>
    }

    return (
        <>
            <div className="max-h-40 overflow-y-auto border border-gray-300 rounded-lg divide-y divide-gray-100">
                {sites.map(site => (
                    <label
                        key={site.id}
                        className="flex items-center gap-3 px-3 py-2 hover:bg-gray-50 cursor-pointer"
                    >
                        <input
                            type="checkbox"
                            checked={selected.includes(site.id)}
                            onChange={() => onToggle(site.id)}
                            className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                        />
                        <span className="text-sm text-gray-700">{site.name}</span>
                    </label>
                ))}
            </div>
            {selected.length > 0 && (
                <p className="mt-1 text-xs text-gray-500">
                    {selected.length} site{selected.length > 1 ? 's' : ''} selected
                </p>
            )}
        </>
    )
}
