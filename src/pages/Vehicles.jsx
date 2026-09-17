import { useState } from 'react'
import { Link } from 'react-router-dom'
import { formatDate } from '../utils/datetime'
import Navigation from '../components/shared/Navigation'
import FilterSelect from '../components/shared/FilterSelect'
import { TicketListSkeleton } from '../components/shared/LoadingSkeleton'
import { useVehicles, useUpdateVehicle } from '../hooks/useVehicles'
import { useDebouncedValue } from '../hooks/useDebouncedValue'
import { useAuth } from '../hooks/useAuth'
import {
    MagnifyingGlassIcon,
    PencilSquareIcon,
    TruckIcon,
    XMarkIcon,
} from '@heroicons/react/24/outline'

// ── Edit Modal ────────────────────────────────────────────────────────────────
// Edit only — there is no add path. Vehicles come from the Roorides feed (MAIN-68).
// Only year and notes are offered: the sync rewrites registration_number, make, model,
// type and is_active on every run, so editing one of those here would be reverted
// within 24 hours. is_active is shown read-only for the same reason (MAIN-69).
function EditVehicleModal({ vehicle, onClose }) {
    const updateVehicle = useUpdateVehicle()

    const [form, setForm] = useState({
        year: vehicle.year || '',
        notes: vehicle.notes || '',
    })
    const [error, setError] = useState(null)

    const set = (field, value) => setForm(p => ({ ...p, [field]: value }))

    async function handleSubmit(e) {
        e.preventDefault()
        setError(null)
        try {
            await updateVehicle.mutateAsync({
                id: vehicle.id,
                year: form.year ? parseInt(form.year) : null,
                notes: form.notes,
            })
            onClose()
        } catch (err) {
            setError(err.message)
        }
    }

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-md">
                <div className="flex items-center justify-between px-6 py-4 border-b">
                    <div>
                        <h2 className="text-base font-semibold text-gray-900">Edit Vehicle</h2>
                        <p className="text-xs text-gray-500 font-mono mt-0.5">
                            {vehicle.registration_number}
                        </p>
                    </div>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                <form onSubmit={handleSubmit} className="px-6 py-5 space-y-4">
                    {/* Feed-owned fields, shown for context only */}
                    <div className="bg-gray-50 rounded-lg px-3 py-2.5 space-y-1.5">
                        <div className="flex items-center justify-between text-xs">
                            <span className="text-gray-500">Make / Model</span>
                            <span className="text-gray-700">
                                {[vehicle.make, vehicle.model].filter(Boolean).join(' ') || '—'}
                            </span>
                        </div>
                        <div className="flex items-center justify-between text-xs">
                            <span className="text-gray-500">Site</span>
                            <span className="text-gray-700">
                                {vehicle.vehicle_sites?.map(vs => vs.site_name).join(', ') || '—'}
                            </span>
                        </div>
                        <div className="flex items-center justify-between text-xs">
                            <span className="text-gray-500">Status</span>
                            {vehicle.is_active
                                ? <span className="px-2 py-0.5 text-xs rounded-full bg-green-100 text-green-700">Active</span>
                                : <span className="px-2 py-0.5 text-xs rounded-full bg-gray-100 text-gray-500">Inactive</span>
                            }
                        </div>
                        <p className="text-xs text-gray-400 pt-1 border-t border-gray-200">
                            Set by the Roorides sync — change these at source in Roorides.
                        </p>
                    </div>

                    <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1">Year</label>
                        <input
                            autoFocus
                            type="number"
                            min="1990"
                            max="2099"
                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                            value={form.year}
                            onChange={e => set('year', e.target.value)}
                            placeholder="e.g. 2022"
                        />
                    </div>

                    <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
                        <textarea
                            rows={2}
                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 resize-none"
                            value={form.notes}
                            onChange={e => set('notes', e.target.value)}
                            placeholder="Optional"
                        />
                    </div>

                    {error && (
                        <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{error}</p>
                    )}

                    <div className="flex justify-end gap-3 pt-2">
                        <button
                            type="button"
                            onClick={onClose}
                            className="px-4 py-2 text-sm text-gray-700 border rounded-lg hover:bg-gray-100"
                        >
                            Cancel
                        </button>
                        <button
                            type="submit"
                            disabled={updateVehicle.isPending}
                            className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                        >
                            {updateVehicle.isPending ? 'Saving…' : 'Save Changes'}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    )
}

// ── Main Page ─────────────────────────────────────────────────────────────────
export default function Vehicles() {
    const { userProfile } = useAuth()
    const canEdit = ['maintenance_exec', 'super_admin', 'finance'].includes(userProfile?.role)

    const [filters, setFilters] = useState({ search: '', site: '', active: 'active' })
    const search = useDebouncedValue(filters.search)
    const { data: vehicles = [], isLoading } = useVehicles({ ...filters, search })

    const [editingVehicle, setEditingVehicle] = useState(null)

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Vehicles' }]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8">
                {/* Header */}
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
                    <div>
                        <h1 className="text-2xl font-bold text-gray-900">Vehicles</h1>
                        <p className="text-xs text-gray-500 mt-1">
                            Synced nightly from Roorides — add or retire a vehicle at source.
                        </p>
                    </div>
                </div>

                {/* Filters */}
                <div className="bg-white p-4 rounded-lg shadow-sm mb-6">
                    <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
                        <div className="relative sm:col-span-2">
                            <input
                                type="text"
                                placeholder="Search by reg. number, make or model…"
                                className="w-full pl-10 pr-4 py-2 border rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                                value={filters.search}
                                onChange={e => setFilters(p => ({ ...p, search: e.target.value }))}
                            />
                            <MagnifyingGlassIcon className="w-4 h-4 text-gray-400 absolute left-3 top-2.5" />
                        </div>
                        <input
                            type="text"
                            placeholder="Filter by site…"
                            className="border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                            value={filters.site}
                            onChange={e => setFilters(p => ({ ...p, site: e.target.value }))}
                        />
                        <FilterSelect
                            value={filters.active}
                            onChange={v => setFilters(p => ({ ...p, active: v }))}
                            placeholder="All Vehicles"
                            options={[
                                { value: 'active', label: 'Active Only' },
                                { value: 'inactive', label: 'Inactive Only' },
                            ]}
                        />
                    </div>
                </div>

                {/* Table */}
                {isLoading ? (
                    <TicketListSkeleton />
                ) : vehicles.length === 0 ? (
                    <div className="bg-white rounded-lg shadow-sm p-16 text-center">
                        <TruckIcon className="w-10 h-10 text-gray-300 mx-auto mb-3" />
                        <p className="text-gray-400 text-sm">No vehicles found.</p>
                    </div>
                ) : (
                    <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                        <table className="min-w-full divide-y divide-gray-100 text-sm">
                            <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                                <tr>
                                    <th className="px-4 py-3 text-left">Registration</th>
                                    <th className="px-4 py-3 text-left">Make / Model</th>
                                    <th className="px-4 py-3 text-left">Year</th>
                                    <th className="px-4 py-3 text-left">Site</th>
                                    <th className="px-4 py-3 text-left">Status</th>
                                    <th className="px-4 py-3 text-left">Added</th>
                                    {canEdit && <th className="px-4 py-3 w-10"></th>}
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-50">
                                {vehicles.map(v => (
                                    <tr key={v.id} className="hover:bg-gray-50 group">
                                        <td className="px-4 py-3 font-medium">
                                            <Link
                                                to={`/vehicles/${encodeURIComponent(v.registration_number)}`}
                                                className="text-blue-600 hover:underline font-mono"
                                            >
                                                {v.registration_number}
                                            </Link>
                                        </td>
                                        <td className="px-4 py-3 text-gray-700">
                                            {[v.make, v.model].filter(Boolean).join(' ') || '—'}
                                        </td>
                                        <td className="px-4 py-3 text-gray-500">{v.year || '—'}</td>
                                        <td className="px-4 py-3 text-gray-500">
                                            {v.vehicle_sites?.map(vs => vs.site_name).join(', ') || '—'}
                                        </td>
                                        <td className="px-4 py-3">
                                            {v.is_active
                                                ? <span className="px-2 py-0.5 text-xs rounded-full bg-green-100 text-green-700">Active</span>
                                                : <span className="px-2 py-0.5 text-xs rounded-full bg-gray-100 text-gray-500">Inactive</span>
                                            }
                                        </td>
                                        <td className="px-4 py-3 text-gray-400 text-xs">
                                            {formatDate(v.created_at)}
                                        </td>
                                        {canEdit && (
                                            <td className="px-4 py-3 text-center">
                                                <button
                                                    onClick={() => setEditingVehicle(v)}
                                                    className="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-blue-600 transition-opacity"
                                                >
                                                    <PencilSquareIcon className="w-4 h-4" />
                                                </button>
                                            </td>
                                        )}
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                        <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                            {vehicles.length} vehicle{vehicles.length !== 1 ? 's' : ''}
                        </div>
                    </div>
                )}
            </div>

            {editingVehicle && (
                <EditVehicleModal vehicle={editingVehicle} onClose={() => setEditingVehicle(null)} />
            )}
        </div>
    )
}
