import { useState } from 'react'
import { XMarkIcon, ArrowRightIcon, ExclamationTriangleIcon } from '@heroicons/react/24/outline'
import CustomSelect from '../shared/CustomSelect'
import { useTransferStock } from '../../hooks/useInventory'

/**
 * Move selected parts from one workshop to another.
 *
 * @param {object} props
 * @param {object} props.fromLocation      the workshop the parts are leaving
 * @param {Array}  props.locations         all active workshops
 * @param {Array}  props.parts             the selected rows, each with quantity_here
 * @param {Function} props.onClose
 */
export default function MoveStockModal({ fromLocation, locations, parts, onClose }) {
    const transferStock = useTransferStock()

    const [toLocationId, setToLocationId] = useState('')
    const [notes, setNotes] = useState('')
    const [error, setError] = useState(null)
    // Start every line empty. Prefilling the full available quantity means a stray
    // confirm empties the workshop, so nothing moves until it is typed in.
    const [quantities, setQuantities] = useState(() =>
        Object.fromEntries(parts.map(p => [p.id, '']))
    )

    const destinations = locations.filter(l => l.id !== fromLocation.id)

    const lines = parts.map(part => {
        const raw = quantities[part.id]
        const qty = raw === '' ? 0 : Number(raw)
        const invalid =
            raw !== '' && (Number.isNaN(qty) || qty < 0 || qty > part.quantity_here)
        return { part, raw, qty, invalid }
    })

    const movable = lines.filter(l => l.qty > 0 && !l.invalid)
    const anyInvalid = lines.some(l => l.invalid)
    const canSubmit = !!toLocationId && movable.length > 0 && !anyInvalid && !transferStock.isPending

    async function handleMove() {
        setError(null)
        try {
            await transferStock.mutateAsync({
                fromLocationId: fromLocation.id,
                toLocationId,
                items: movable.map(l => ({ part_id: l.part.id, quantity: l.qty })),
                notes,
            })
            onClose()
        } catch (err) {
            setError(err.message)
        }
    }

    return (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-xl w-full max-w-2xl flex flex-col max-h-[90vh]">
                {/* Header */}
                <div className="flex items-center justify-between px-6 py-4 border-b flex-shrink-0">
                    <div>
                        <h2 className="text-lg font-semibold text-gray-900">Move Stock</h2>
                        <p className="text-xs text-gray-500 mt-0.5">
                            {parts.length} part{parts.length !== 1 ? 's' : ''} selected from {fromLocation.name}
                        </p>
                    </div>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                {/* Lines */}
                <div className="flex-1 overflow-y-auto px-6 py-4">
                    <table className="w-full text-sm">
                        <thead className="text-xs font-medium text-gray-500 uppercase tracking-wide">
                            <tr>
                                <th className="text-left pb-2">Part</th>
                                <th className="text-right pb-2 w-28">Available</th>
                                <th className="text-right pb-2 w-32">Move</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-50">
                            {lines.map(({ part, raw, invalid }) => (
                                <tr key={part.id}>
                                    <td className="py-2 pr-2">
                                        <div className="font-medium text-gray-900">{part.name}</div>
                                        {part.part_number && (
                                            <div className="text-xs text-gray-400 font-mono">{part.part_number}</div>
                                        )}
                                    </td>
                                    <td className="py-2 text-right text-gray-500">
                                        {part.quantity_here} {part.unit}
                                    </td>
                                    <td className="py-2 text-right">
                                        <input
                                            type="number"
                                            min="0"
                                            max={part.quantity_here}
                                            step="0.01"
                                            placeholder="0"
                                            value={raw}
                                            onChange={e => {
                                                const v = e.target.value
                                                setQuantities(q => ({ ...q, [part.id]: v }))
                                                setError(null)
                                            }}
                                            className={`w-24 border rounded-lg px-2 py-1 text-sm text-right focus:ring-2 focus:ring-blue-500 ${
                                                invalid ? 'border-red-400 bg-red-50' : ''
                                            }`}
                                        />
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>

                    {anyInvalid && (
                        <p className="text-xs text-red-600 mt-3">
                            A quantity is higher than what this workshop holds. Reduce it to continue.
                        </p>
                    )}
                </div>

                {/* Destination + confirm */}
                <div className="border-t px-6 py-4 space-y-3 flex-shrink-0">
                    <div className="flex items-center gap-3">
                        <span className="text-sm text-gray-500 flex-shrink-0">{fromLocation.name}</span>
                        <ArrowRightIcon className="w-4 h-4 text-gray-400 flex-shrink-0" />
                        <div className="flex-1 min-w-0">
                            <CustomSelect
                                value={toLocationId}
                                onChange={v => { setToLocationId(v); setError(null) }}
                                options={destinations.map(l => ({
                                    value: l.id,
                                    label: l.address ? `${l.name} — ${l.address}` : l.name,
                                }))}
                                placeholder="Move to workshop…"
                                compact
                            />
                        </div>
                    </div>

                    <input
                        type="text"
                        placeholder="Notes (optional) — e.g. who carried it, vehicle used"
                        value={notes}
                        onChange={e => setNotes(e.target.value)}
                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                    />

                    <p className="flex items-start gap-1.5 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">
                        <ExclamationTriangleIcon className="w-4 h-4 flex-shrink-0 mt-px" />
                        <span>A move cannot be undone. To correct one, move the parts back.</span>
                    </p>

                    {error && <p className="text-sm text-red-600">{error}</p>}

                    <div className="flex justify-end gap-2">
                        <button
                            onClick={onClose}
                            className="px-4 py-2 border text-gray-600 text-sm rounded-lg hover:bg-gray-50"
                        >
                            Cancel
                        </button>
                        <button
                            onClick={handleMove}
                            disabled={!canSubmit}
                            className="px-4 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 disabled:opacity-50"
                        >
                            {transferStock.isPending
                                ? 'Moving…'
                                : movable.length === 0
                                    ? 'Move'
                                    : `Move ${movable.length} part${movable.length !== 1 ? 's' : ''}`}
                        </button>
                    </div>
                </div>
            </div>
        </div>
    )
}
