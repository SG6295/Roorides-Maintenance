import { useState } from 'react'
import CustomSelect from '../../components/shared/CustomSelect'
import { useAllSites } from '../../hooks/useSites'
import { useWorkshopLocations } from '../../hooks/useWorkshopLocations'
import { useSiteWorkshops, useSetSiteWorkshop } from '../../hooks/useSiteWorkshops'
import { formatSiteLabel } from '../../utils/siteLabel'

// CustomSelect matches options on a truthy value, so "Not assigned" needs one.
const NOT_ASSIGNED = 'none'

/**
 * Settings › Workshop Hub Mapping (MAIN-131). Assigns each site to the workshop that
 * serves it; Analytics uses this to tick a workshop's sites in its site filter.
 * Every site is listed, inactive ones too — Analytics still reports on them.
 */
export default function WorkshopHubMappingSettings() {
    // All sites, not just active — a departed site's history is still filterable.
    const { data: sites = [], isLoading: sitesLoading } = useAllSites()
    const { data: locations = [] } = useWorkshopLocations()
    const { data: mapping = [], isLoading: mappingLoading } = useSiteWorkshops()
    const setSiteWorkshop = useSetSiteWorkshop()
    const [error, setError] = useState(null)

    const locationBySite = new Map(mapping.map(m => [m.site_id, m.location_id]))
    const options = [
        ...locations.map(l => ({ value: l.id, label: l.name })),
        { value: NOT_ASSIGNED, label: 'Not assigned' },
    ]

    const counts = locations.map(l => ({
        name: l.name,
        count: mapping.filter(m => m.location_id === l.id).length,
    }))
    const unassigned = sites.filter(s => !locationBySite.has(s.id)).length

    async function pick(siteId, value) {
        setError(null)
        try {
            await setSiteWorkshop.mutateAsync({ siteId, locationId: value === NOT_ASSIGNED ? null : value })
        } catch (err) {
            setError(err.message)
        }
    }

    return (
        <div>
            <div className="mb-6">
                <h2 className="text-lg font-semibold text-gray-900">Workshop Hub Mapping</h2>
                <p className="text-sm text-gray-500 mt-1">
                    The workshop that serves each site. Picking a workshop in an Analytics site filter
                    selects the sites mapped to it here. Changes save as soon as you pick.
                </p>
                {!sitesLoading && !mappingLoading && (
                    <p className="text-sm text-gray-700 mt-3">
                        {counts.map(c => `${c.name}: ${c.count}`).join(' · ')}
                        {counts.length > 0 && ' · '}Not assigned: {unassigned}
                    </p>
                )}
            </div>

            {error && <p className="text-sm text-red-600 mb-4">{error}</p>}

            {sitesLoading || mappingLoading ? (
                <p className="text-sm text-gray-400">Loading…</p>
            ) : (
                <ul className="divide-y border rounded-lg">
                    {sites.map(site => (
                        <li key={site.id} className="px-4 py-2 bg-white flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                            <div className="min-w-0 flex items-center gap-2">
                                <span className="text-sm text-gray-900">{formatSiteLabel(site)}</span>
                                {!site.is_active && (
                                    <span className="px-2 py-0.5 text-xs rounded-full bg-gray-100 text-gray-500 flex-shrink-0">
                                        Inactive
                                    </span>
                                )}
                            </div>
                            <div className="sm:w-48 flex-shrink-0">
                                <CustomSelect
                                    value={locationBySite.get(site.id) ?? NOT_ASSIGNED}
                                    onChange={value => pick(site.id, value)}
                                    options={options}
                                    disabled={setSiteWorkshop.isPending}
                                    compact
                                />
                            </div>
                        </li>
                    ))}
                    {sites.length === 0 && (
                        <li className="px-4 py-3 text-sm text-gray-400">No sites yet.</li>
                    )}
                </ul>
            )}
        </div>
    )
}
