import { useState } from 'react'
import { PlusIcon, TrashIcon } from '@heroicons/react/24/outline'
import { usePartUnits, useAddPartUnit, useDeletePartUnit } from '../../hooks/useInventory'

export default function PartUnitsSettings() {
    const { data: units = [], isLoading } = usePartUnits()
    const addUnit = useAddPartUnit()
    const deleteUnit = useDeletePartUnit()
    const [newName, setNewName] = useState('')
    const [error, setError] = useState(null)

    async function handleAdd(e) {
        e.preventDefault()
        const trimmed = newName.trim()
        if (!trimmed) return
        if (units.some(u => u.name.toLowerCase() === trimmed.toLowerCase())) {
            setError('Unit already exists.')
            return
        }
        setError(null)
        try {
            await addUnit.mutateAsync(trimmed)
            setNewName('')
        } catch (err) {
            setError(err.message)
        }
    }

    async function handleDelete(unit) {
        if (!window.confirm(`Remove "${unit.name}"? Parts already using this unit are unaffected.`)) return
        try {
            await deleteUnit.mutateAsync(unit.id)
        } catch (err) {
            setError(err.message)
        }
    }

    return (
        <div>
            <div className="mb-6">
                <h2 className="text-lg font-semibold text-gray-900">Part Units</h2>
                <p className="text-sm text-gray-500 mt-1">
                    Manage the units of measure available when creating inventory parts.
                </p>
            </div>

            {/* Add new unit */}
            <form onSubmit={handleAdd} className="flex gap-2 mb-6">
                <input
                    type="text"
                    placeholder="e.g. dozen"
                    value={newName}
                    onChange={e => { setNewName(e.target.value); setError(null) }}
                    className="flex-1 max-w-xs border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                />
                <button
                    type="submit"
                    disabled={addUnit.isPending || !newName.trim()}
                    className="flex items-center gap-1 px-4 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 disabled:opacity-50"
                >
                    <PlusIcon className="w-4 h-4" />
                    Add Unit
                </button>
            </form>
            {error && <p className="text-sm text-red-600 mb-4">{error}</p>}

            {/* Units list */}
            {isLoading ? (
                <p className="text-sm text-gray-400">Loading…</p>
            ) : (
                <ul className="divide-y border rounded-lg overflow-hidden max-w-sm">
                    {units.map(unit => (
                        <li key={unit.id} className="flex items-center justify-between px-4 py-3 bg-white">
                            <span className="text-sm text-gray-800">{unit.name}</span>
                            <button
                                onClick={() => handleDelete(unit)}
                                className="text-gray-400 hover:text-red-500 transition-colors"
                                title="Remove unit"
                            >
                                <TrashIcon className="w-4 h-4" />
                            </button>
                        </li>
                    ))}
                    {units.length === 0 && (
                        <li className="px-4 py-3 text-sm text-gray-400">No units defined yet.</li>
                    )}
                </ul>
            )}
        </div>
    )
}
