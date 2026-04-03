import { useState } from 'react'
import { useUpdatePart } from '../../hooks/useInventory'
import { XMarkIcon } from '@heroicons/react/24/outline'

export default function EditPartModal({ part, onClose }) {
    const updatePart = useUpdatePart()

    const [form, setForm] = useState({
        name: part.name,
        part_number: part.part_number || '',
        unit: part.unit || 'pcs',
    })
    const [error, setError] = useState(null)

    async function handleSubmit(e) {
        e.preventDefault()
        setError(null)
        if (!form.name.trim()) {
            setError('Part name is required.')
            return
        }
        try {
            await updatePart.mutateAsync({
                id: part.id,
                name: form.name.trim(),
                part_number: form.part_number.trim() || null,
                unit: form.unit.trim() || 'pcs',
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
                    <h2 className="text-base font-semibold text-gray-900">Edit Part</h2>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                <form onSubmit={handleSubmit} className="px-6 py-5 space-y-4">
                    <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1">
                            Part Name <span className="text-red-500">*</span>
                        </label>
                        <input
                            autoFocus
                            type="text"
                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                            value={form.name}
                            onChange={e => setForm(p => ({ ...p, name: e.target.value }))}
                        />
                    </div>

                    <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1">Part Number</label>
                        <input
                            type="text"
                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                            value={form.part_number}
                            onChange={e => setForm(p => ({ ...p, part_number: e.target.value }))}
                            placeholder="e.g. AF-001"
                        />
                    </div>

                    <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1">Unit</label>
                        <input
                            type="text"
                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                            value={form.unit}
                            onChange={e => setForm(p => ({ ...p, unit: e.target.value }))}
                            placeholder="e.g. pcs, L, kg"
                        />
                        <p className="text-xs text-gray-400 mt-1">
                            Changing the unit does not convert existing stock quantities.
                        </p>
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
                            disabled={updatePart.isPending}
                            className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                        >
                            {updatePart.isPending ? 'Saving…' : 'Save Changes'}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    )
}
