import { useState } from 'react'
import { formatDate } from '../../utils/datetime'
import { MagnifyingGlassIcon } from '@heroicons/react/24/outline'
import FilterSelect from '../shared/FilterSelect'
import { TicketListSkeleton } from '../shared/LoadingSkeleton'
import { useScrapInventory } from '../../hooks/useScrap'
import { useDebouncedValue } from '../../hooks/useDebouncedValue'
import { useWorkshopLocations } from '../../hooks/useWorkshopLocations'

const STATUS_BADGE = {
    in_storage:  'bg-green-100 text-green-700',
    sold:        'bg-gray-100 text-gray-600',
    written_off: 'bg-red-100 text-red-700',
}

const STATUS_LABEL = {
    in_storage:  'In Storage',
    sold:        'Sold',
    written_off: 'Written Off',
}

export default function ScrapInventoryTab() {
    const [filters, setFilters] = useState({ status: '', search: '', vehicle: '', location_id: '', dateFrom: '', dateTo: '' })
    const search = useDebouncedValue(filters.search)
    const vehicle = useDebouncedValue(filters.vehicle)
    const { data: items = [], isLoading } = useScrapInventory({ ...filters, search, vehicle })
    const { data: locations = [] } = useWorkshopLocations()

    return (
        <div className="space-y-4">
            <div className="bg-white p-4 rounded-lg shadow-sm">
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
                    <div className="relative sm:col-span-2">
                        <input
                            type="text"
                            placeholder="Search by part name…"
                            className="w-full pl-10 pr-4 py-2 border rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                            value={filters.search}
                            onChange={e => setFilters(p => ({ ...p, search: e.target.value }))}
                        />
                        <MagnifyingGlassIcon className="w-4 h-4 text-gray-400 absolute left-3 top-2.5" />
                    </div>
                    <FilterSelect
                        value={filters.status}
                        onChange={v => setFilters(p => ({ ...p, status: v }))}
                        placeholder="All Statuses"
                        options={[
                            { value: 'in_storage',  label: 'In Storage' },
                            { value: 'sold',        label: 'Sold' },
                            { value: 'written_off', label: 'Written Off' },
                        ]}
                    />
                    <input
                        type="text"
                        placeholder="Filter by vehicle…"
                        className="border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                        value={filters.vehicle}
                        onChange={e => setFilters(p => ({ ...p, vehicle: e.target.value }))}
                    />
                    {locations.length > 1 && (
                        <FilterSelect
                            value={filters.location_id}
                            onChange={v => setFilters(p => ({ ...p, location_id: v }))}
                            placeholder="All Workshops"
                            options={locations.map(l => ({ value: l.id, label: l.name }))}
                        />
                    )}
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-3">
                    <div className="flex items-center gap-2 text-sm text-gray-600">
                        <span className="shrink-0 w-8">From</span>
                        <input
                            type="date"
                            className="border rounded-lg px-3 py-1.5 text-sm focus:ring-2 focus:ring-blue-500 flex-1"
                            value={filters.dateFrom}
                            onChange={e => setFilters(p => ({ ...p, dateFrom: e.target.value }))}
                        />
                    </div>
                    <div className="flex items-center gap-2 text-sm text-gray-600">
                        <span className="shrink-0 w-8">To</span>
                        <input
                            type="date"
                            className="border rounded-lg px-3 py-1.5 text-sm focus:ring-2 focus:ring-blue-500 flex-1"
                            value={filters.dateTo}
                            onChange={e => setFilters(p => ({ ...p, dateTo: e.target.value }))}
                        />
                    </div>
                </div>
            </div>

            {isLoading ? (
                <TicketListSkeleton />
            ) : items.length === 0 ? (
                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                    No scrap items found.
                </div>
            ) : (
                <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-100 text-sm">
                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                            <tr>
                                <th className="px-4 py-3 text-left">Part Name</th>
                                <th className="px-4 py-3 text-left">Part Number</th>
                                <th className="px-4 py-3 text-right">Qty</th>
                                <th className="px-4 py-3 text-left">Unit</th>
                                <th className="px-4 py-3 text-left">Source Vehicle</th>
                                <th className="px-4 py-3 text-left">Source JC</th>
                                <th className="px-4 py-3 text-left">Workshop</th>
                                <th className="px-4 py-3 text-left">Status</th>
                                <th className="px-4 py-3 text-left">Date Added</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-50">
                            {items.map(item => (
                                <tr key={item.id} className="hover:bg-gray-50">
                                    <td className="px-4 py-3 font-medium text-gray-900">{item.part_name_snapshot}</td>
                                    <td className="px-4 py-3 text-gray-500 font-mono text-xs">{item.part_number_snapshot || '—'}</td>
                                    <td className="px-4 py-3 text-right text-gray-700">{item.quantity_snapshot}</td>
                                    <td className="px-4 py-3 text-gray-500">{item.unit_snapshot}</td>
                                    <td className="px-4 py-3 text-gray-700">{item.source_vehicle_number || '—'}</td>
                                    <td className="px-4 py-3 text-gray-500 font-mono text-xs">
                                        {item.job_card?.job_card_number || '—'}
                                    </td>
                                    <td className="px-4 py-3 text-gray-700">{item.location?.name || '—'}</td>
                                    <td className="px-4 py-3">
                                        <span className={`px-2 py-0.5 text-xs rounded-full ${STATUS_BADGE[item.status] || 'bg-gray-100 text-gray-600'}`}>
                                            {STATUS_LABEL[item.status] || item.status}
                                        </span>
                                    </td>
                                    <td className="px-4 py-3 text-gray-500 text-xs">
                                        {formatDate(item.created_at)}
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                    <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                        {items.length} item{items.length !== 1 ? 's' : ''}
                    </div>
                </div>
            )}
        </div>
    )
}
