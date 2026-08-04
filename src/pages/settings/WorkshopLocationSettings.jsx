import { useState } from 'react'
import { PlusIcon, PencilSquareIcon, CheckIcon, XMarkIcon } from '@heroicons/react/24/outline'
import {
    useWorkshopLocations,
    useCreateWorkshopLocation,
    useUpdateWorkshopLocation,
    useToggleWorkshopLocation,
} from '../../hooks/useWorkshopLocations'

export default function WorkshopLocationSettings() {
    const { data: locations = [], isLoading } = useWorkshopLocations({ includeInactive: true })
    const createLocation = useCreateWorkshopLocation()
    const updateLocation = useUpdateWorkshopLocation()
    const toggleLocation = useToggleWorkshopLocation()

    const [form, setForm] = useState({ name: '', address: '' })
    const [editing, setEditing] = useState(null) // { id, name, address }
    const [error, setError] = useState(null)

    const duplicateName = (name, ignoreId = null) =>
        locations.some(l => l.id !== ignoreId && l.name.toLowerCase() === name.trim().toLowerCase())

    async function handleAdd(e) {
        e.preventDefault()
        const name = form.name.trim()
        if (!name) return
        if (duplicateName(name)) {
            setError('A workshop with that name already exists.')
            return
        }
        setError(null)
        try {
            await createLocation.mutateAsync(form)
            setForm({ name: '', address: '' })
        } catch (err) {
            setError(err.message)
        }
    }

    async function handleSaveEdit() {
        const name = editing.name.trim()
        if (!name) {
            setError('Workshop name cannot be empty.')
            return
        }
        if (duplicateName(name, editing.id)) {
            setError('A workshop with that name already exists.')
            return
        }
        setError(null)
        try {
            await updateLocation.mutateAsync(editing)
            setEditing(null)
        } catch (err) {
            setError(err.message)
        }
    }

    async function handleToggle(location) {
        const verb = location.is_active ? 'Deactivate' : 'Reactivate'
        if (!window.confirm(`${verb} "${location.name}"? Existing job cards and invoices keep their location either way.`)) return
        setError(null)
        try {
            await toggleLocation.mutateAsync({ id: location.id, is_active: !location.is_active })
        } catch (err) {
            setError(err.message)
        }
    }

    return (
        <div>
            <div className="mb-6">
                <h2 className="text-lg font-semibold text-gray-900">Workshop Locations</h2>
                <p className="text-sm text-gray-500 mt-1">
                    The physical workshops where repairs are carried out and parts are held. Each job card
                    is worked at one workshop and draws stock from it. Renaming a workshop is safe — the
                    address is kept alongside the name so everyone can tell them apart.
                </p>
            </div>

            {/* Add new location */}
            <form onSubmit={handleAdd} className="bg-gray-50 border rounded-lg p-4 mb-6 space-y-3">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1">Workshop name</label>
                        <input
                            type="text"
                            placeholder="e.g. Whitefield"
                            value={form.name}
                            onChange={e => { setForm(f => ({ ...f, name: e.target.value })); setError(null) }}
                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                        />
                    </div>
                    <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1">Address</label>
                        <input
                            type="text"
                            placeholder="Street, area, city"
                            value={form.address}
                            onChange={e => setForm(f => ({ ...f, address: e.target.value }))}
                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                        />
                    </div>
                </div>
                <button
                    type="submit"
                    disabled={createLocation.isPending || !form.name.trim()}
                    className="flex items-center gap-1 px-4 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 disabled:opacity-50"
                >
                    <PlusIcon className="w-4 h-4" />
                    Add Workshop
                </button>
            </form>

            {error && <p className="text-sm text-red-600 mb-4">{error}</p>}

            {isLoading ? (
                <p className="text-sm text-gray-400">Loading…</p>
            ) : (
                <ul className="divide-y border rounded-lg overflow-hidden">
                    {locations.map(location => (
                        <li key={location.id} className="px-4 py-3 bg-white">
                            {editing?.id === location.id ? (
                                <div className="space-y-2">
                                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                                        <input
                                            type="text"
                                            value={editing.name}
                                            onChange={e => setEditing(p => ({ ...p, name: e.target.value }))}
                                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        />
                                        <input
                                            type="text"
                                            placeholder="Address"
                                            value={editing.address || ''}
                                            onChange={e => setEditing(p => ({ ...p, address: e.target.value }))}
                                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        />
                                    </div>
                                    <div className="flex gap-2">
                                        <button
                                            onClick={handleSaveEdit}
                                            disabled={updateLocation.isPending}
                                            className="flex items-center gap-1 px-3 py-1.5 bg-blue-600 text-white text-xs rounded-lg hover:bg-blue-700 disabled:opacity-50"
                                        >
                                            <CheckIcon className="w-3.5 h-3.5" /> Save
                                        </button>
                                        <button
                                            onClick={() => { setEditing(null); setError(null) }}
                                            className="flex items-center gap-1 px-3 py-1.5 border text-gray-600 text-xs rounded-lg hover:bg-gray-50"
                                        >
                                            <XMarkIcon className="w-3.5 h-3.5" /> Cancel
                                        </button>
                                    </div>
                                </div>
                            ) : (
                                <div className="flex items-start justify-between gap-4">
                                    <div className="min-w-0">
                                        <div className="flex items-center gap-2">
                                            <span className="text-sm font-medium text-gray-900">{location.name}</span>
                                            {!location.is_active && (
                                                <span className="px-2 py-0.5 text-xs rounded-full bg-gray-100 text-gray-500">
                                                    Inactive
                                                </span>
                                            )}
                                        </div>
                                        <p className="text-xs text-gray-500 mt-0.5">
                                            {location.address || 'No address recorded'}
                                        </p>
                                    </div>
                                    <div className="flex items-center gap-3 flex-shrink-0">
                                        <button
                                            onClick={() => { setEditing({ ...location }); setError(null) }}
                                            className="text-gray-400 hover:text-blue-600"
                                            title="Rename or edit address"
                                        >
                                            <PencilSquareIcon className="w-4 h-4" />
                                        </button>
                                        <button
                                            onClick={() => handleToggle(location)}
                                            disabled={toggleLocation.isPending}
                                            className="text-xs text-gray-500 hover:text-gray-900 disabled:opacity-50"
                                        >
                                            {location.is_active ? 'Deactivate' : 'Reactivate'}
                                        </button>
                                    </div>
                                </div>
                            )}
                        </li>
                    ))}
                    {locations.length === 0 && (
                        <li className="px-4 py-3 text-sm text-gray-400">No workshops defined yet.</li>
                    )}
                </ul>
            )}
        </div>
    )
}
