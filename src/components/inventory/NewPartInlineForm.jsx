import { useState } from 'react'
import { CheckIcon } from '@heroicons/react/24/outline'
import { useCreatePart, usePartUnits } from '../../hooks/useInventory'
import CustomSelect from '../shared/CustomSelect'

/** Adds a part to the catalog from inside a line item, without leaving the form. */
export default function NewPartInlineForm({ onCreated, onCancel }) {
    const { data: partUnits = [] } = usePartUnits()
    const createPart = useCreatePart()
    const [form, setForm] = useState({ name: '', part_number: '', unit: 'pcs' })
    const [error, setError] = useState(null)

    const setField = (field, value) => setForm(prev => ({ ...prev, [field]: value }))

    async function confirm() {
        if (!form.name.trim()) {
            setError('Part name is required.')
            return
        }
        setError(null)
        try {
            const newPart = await createPart.mutateAsync({
                name: form.name.trim(),
                part_number: form.part_number.trim() || null,
                unit: form.unit.trim() || 'pcs',
                quantity_in_stock: 0,
            })
            onCreated(newPart)
        } catch (err) {
            setError(err.message)
        }
    }

    return (
        <div className="border border-blue-300 rounded-lg p-2 bg-blue-50 space-y-1.5">
            <p className="text-xs font-medium text-blue-700">New part</p>
            <input
                autoFocus
                type="text"
                placeholder="Part name *"
                className="w-full border rounded px-2 py-1 text-xs focus:ring-1 focus:ring-blue-400"
                value={form.name}
                onChange={e => setField('name', e.target.value)}
            />
            <div className="flex gap-1">
                <input
                    type="text"
                    placeholder="Part # (optional)"
                    className="flex-1 border rounded px-2 py-1 text-xs focus:ring-1 focus:ring-blue-400"
                    value={form.part_number}
                    onChange={e => setField('part_number', e.target.value)}
                />
                <div className="w-24">
                    <CustomSelect
                        compact
                        value={form.unit}
                        onChange={val => setField('unit', val)}
                        options={partUnits.map(u => u.name)}
                    />
                </div>
            </div>
            {error && <p className="text-xs text-red-600">{error}</p>}
            <div className="flex gap-2 pt-0.5">
                <button
                    type="button"
                    onClick={confirm}
                    disabled={createPart.isPending}
                    className="flex items-center gap-1 px-2 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
                >
                    <CheckIcon className="w-3 h-3" />
                    {createPart.isPending ? 'Adding…' : 'Add part'}
                </button>
                <button
                    type="button"
                    onClick={onCancel}
                    className="px-2 py-1 text-xs text-gray-500 hover:text-gray-700"
                >
                    Cancel
                </button>
            </div>
        </div>
    )
}
