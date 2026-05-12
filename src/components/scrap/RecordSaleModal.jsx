import { useState, useRef } from 'react'
import { XMarkIcon, TrashIcon, ArrowUpTrayIcon, PaperClipIcon } from '@heroicons/react/24/outline'
import { useAuth } from '../../hooks/useAuth'
import { useScrapInventory, useRecordScrapDisposal } from '../../hooks/useScrap'
import { logAuditEvent } from '../../utils/auditLogger'
import { supabase } from '../../lib/supabase'

const PAYMENT_OPTIONS = [
    { value: 'cash',          label: 'Cash' },
    { value: 'upi',           label: 'UPI' },
    { value: 'bank_transfer', label: 'Bank Transfer' },
    { value: 'cheque',        label: 'Cheque' },
    { value: 'other',         label: 'Other' },
]

const emptyHeader = () => ({
    disposal_date:     '',
    buyer_name:        '',
    buyer_contact:     '',
    payment_mode:      'cash',
    payment_reference: '',
    notes:             '',
})

export default function RecordSaleModal({ onClose }) {
    const { userProfile } = useAuth()
    const { data: storageItems = [], isLoading: itemsLoading } = useScrapInventory({ status: 'in_storage' })
    const recordDisposal = useRecordScrapDisposal()
    const fileInputRef = useRef(null)

    const [header, setHeader] = useState(emptyHeader())
    const [photos, setPhotos] = useState([])
    const [selected, setSelected] = useState(new Set())
    const [valueAllocated, setValueAllocated] = useState({})
    const [error, setError] = useState(null)

    // ── Photo upload ──────────────────────────────────────────────────────────

    async function handleFileSelect(e) {
        const files = Array.from(e.target.files || [])
        if (!files.length) return
        e.target.value = ''

        for (const file of files) {
            const allowed = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/jpg']
            if (!allowed.includes(file.type)) {
                setError('Only image files (JPG, PNG) are allowed for receipt photos.')
                continue
            }
            if (file.size > 20 * 1024 * 1024) {
                setError('Each file must be under 20 MB.')
                continue
            }

            const placeholder = { name: file.name, url: null, uploading: true }
            setPhotos(prev => [...prev, placeholder])
            const idx = photos.length

            try {
                const formData = new FormData()
                formData.append('file', file)
                const { data: { session } } = await supabase.auth.getSession()
                const res = await fetch(
                    `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/upload-to-drive`,
                    { method: 'POST', headers: { Authorization: `Bearer ${session?.access_token}` }, body: formData }
                )
                if (!res.ok) throw new Error('Upload failed')
                const result = await res.json()
                setPhotos(prev => prev.map((p, i) =>
                    i === idx ? { name: file.name, url: result.url, uploading: false } : p
                ))
            } catch {
                setPhotos(prev => prev.filter((_, i) => i !== idx))
                setError('Failed to upload a photo. Please try again.')
            }
        }
    }

    function removePhoto(idx) {
        setPhotos(prev => prev.filter((_, i) => i !== idx))
    }

    // ── Item selection ────────────────────────────────────────────────────────

    function toggleItem(id) {
        setSelected(prev => {
            const next = new Set(prev)
            if (next.has(id)) {
                next.delete(id)
                setValueAllocated(v => { const n = { ...v }; delete n[id]; return n })
            } else {
                next.add(id)
            }
            return next
        })
    }

    function setItemValue(id, val) {
        setValueAllocated(prev => ({ ...prev, [id]: val }))
    }

    // ── Computed total (Mod 2: float-sum safety) ──────────────────────────────

    const itemsTotal = parseFloat(
        [...selected].reduce((sum, id) => sum + (parseFloat(valueAllocated[id]) || 0), 0).toFixed(2)
    )

    // ── Submit ────────────────────────────────────────────────────────────────

    async function handleSubmit(e) {
        e.preventDefault()
        setError(null)

        if (selected.size === 0) {
            setError('Select at least one scrap item.')
            return
        }
        const readyPhotos = photos.filter(p => p.url)
        if (readyPhotos.length === 0) {
            setError('At least one receipt photo is required.')
            return
        }
        if (photos.some(p => p.uploading)) {
            setError('Please wait for photo uploads to finish.')
            return
        }

        for (const id of selected) {
            const val = parseFloat(valueAllocated[id])
            if (!val || val <= 0) {
                setError('All selected items must have a positive value allocated.')
                return
            }
        }

        try {
            const result = await recordDisposal.mutateAsync({
                header: {
                    disposal_date:     header.disposal_date,
                    buyer_name:        header.buyer_name,
                    buyer_contact:     header.buyer_contact || null,
                    payment_mode:      header.payment_mode,
                    payment_reference: header.payment_mode === 'cash' ? null : (header.payment_reference || null),
                    total_value:       itemsTotal,
                    receipt_photos:    readyPhotos.map(p => p.url),
                    notes:             header.notes || null,
                },
                items: [...selected].map(id => ({
                    scrap_inventory_id: id,
                    value_allocated:    parseFloat((parseFloat(valueAllocated[id]) || 0).toFixed(2)),
                })),
            })

            await logAuditEvent(result.disposal_id, 'scrap_disposal', 'INSERT', userProfile.id, {
                oldData: null,
                newData: { disposal_date: header.disposal_date, buyer_name: header.buyer_name, total_value: itemsTotal },
                changedFields: [],
            })

            onClose()
        } catch (err) {
            setError(err.errorCode ? err.message : (err.message || 'An error occurred.'))
        }
    }

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-3xl max-h-[90vh] flex flex-col">
                {/* Header */}
                <div className="flex items-center justify-between px-6 py-4 border-b">
                    <h2 className="text-lg font-semibold text-gray-900">Record Scrap Sale</h2>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                <form onSubmit={handleSubmit} className="flex flex-col flex-1 overflow-hidden">
                    <div className="overflow-y-auto flex-1 px-6 py-4 space-y-6">

                        {/* Sale Details */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">Sale Details</h3>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Sale Date <span className="text-red-500">*</span>
                                    </label>
                                    <input
                                        required
                                        type="date"
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        value={header.disposal_date}
                                        onChange={e => setHeader(p => ({ ...p, disposal_date: e.target.value }))}
                                    />
                                </div>
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Buyer Name <span className="text-red-500">*</span>
                                    </label>
                                    <input
                                        required
                                        type="text"
                                        placeholder="e.g. Rajan Scrap Dealers"
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        value={header.buyer_name}
                                        onChange={e => setHeader(p => ({ ...p, buyer_name: e.target.value }))}
                                    />
                                </div>
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">Buyer Contact</label>
                                    <input
                                        type="text"
                                        placeholder="Phone or email (optional)"
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        value={header.buyer_contact}
                                        onChange={e => setHeader(p => ({ ...p, buyer_contact: e.target.value }))}
                                    />
                                </div>
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Payment Mode <span className="text-red-500">*</span>
                                    </label>
                                    <select
                                        required
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 bg-white"
                                        value={header.payment_mode}
                                        onChange={e => setHeader(p => ({ ...p, payment_mode: e.target.value, payment_reference: '' }))}
                                    >
                                        {PAYMENT_OPTIONS.map(o => (
                                            <option key={o.value} value={o.value}>{o.label}</option>
                                        ))}
                                    </select>
                                </div>
                                {header.payment_mode !== 'cash' && (
                                    <div className="sm:col-span-2">
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Payment Reference <span className="text-red-500">*</span>
                                        </label>
                                        <input
                                            required
                                            type="text"
                                            placeholder="UPI transaction ID / cheque number / etc."
                                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                            value={header.payment_reference}
                                            onChange={e => setHeader(p => ({ ...p, payment_reference: e.target.value }))}
                                        />
                                    </div>
                                )}
                                <div className="sm:col-span-2">
                                    <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
                                    <input
                                        type="text"
                                        placeholder="Optional"
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        value={header.notes}
                                        onChange={e => setHeader(p => ({ ...p, notes: e.target.value }))}
                                    />
                                </div>
                            </div>
                        </div>

                        {/* Receipt Photos */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">
                                Receipt Photos <span className="text-red-500">*</span>
                            </h3>
                            <input
                                ref={fileInputRef}
                                type="file"
                                accept="image/*"
                                multiple
                                onChange={handleFileSelect}
                                className="hidden"
                            />
                            <div className="space-y-2">
                                {photos.map((p, i) => (
                                    <div key={i} className={`flex items-center gap-2 px-3 py-2 border rounded-lg text-sm ${p.uploading ? 'bg-gray-50 text-gray-500' : 'bg-green-50 border-green-200'}`}>
                                        {p.uploading ? (
                                            <>
                                                <div className="w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin shrink-0" />
                                                <span className="truncate flex-1">Uploading {p.name}…</span>
                                            </>
                                        ) : (
                                            <>
                                                <PaperClipIcon className="w-4 h-4 text-green-600 shrink-0" />
                                                <a href={p.url} target="_blank" rel="noopener noreferrer" className="text-green-700 hover:underline truncate flex-1 text-xs">
                                                    {p.name}
                                                </a>
                                            </>
                                        )}
                                        <button type="button" onClick={() => removePhoto(i)} className="text-gray-400 hover:text-red-500 shrink-0">
                                            <XMarkIcon className="w-4 h-4" />
                                        </button>
                                    </div>
                                ))}
                                <button
                                    type="button"
                                    onClick={() => fileInputRef.current?.click()}
                                    className="flex items-center gap-2 px-4 py-2.5 border-2 border-dashed border-gray-300 rounded-lg text-sm text-gray-500 hover:border-blue-400 hover:text-blue-600 transition-colors w-full justify-center"
                                >
                                    <ArrowUpTrayIcon className="w-4 h-4" />
                                    {photos.length > 0 ? 'Add another photo' : 'Upload receipt photo'}
                                </button>
                            </div>
                        </div>

                        {/* Item Selection */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">
                                Select Items <span className="text-red-500">*</span>
                            </h3>
                            {itemsLoading ? (
                                <p className="text-sm text-gray-500">Loading available scrap items…</p>
                            ) : storageItems.length === 0 ? (
                                <p className="text-sm text-gray-400 italic">No items currently in storage.</p>
                            ) : (
                                <div className="border rounded-lg overflow-hidden">
                                    <table className="min-w-full text-sm divide-y divide-gray-100">
                                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                                            <tr>
                                                <th className="px-3 py-2 w-10"></th>
                                                <th className="px-3 py-2 text-left">Part</th>
                                                <th className="px-3 py-2 text-right">Qty</th>
                                                <th className="px-3 py-2 text-left">Unit</th>
                                                <th className="px-3 py-2 text-left">Vehicle</th>
                                                <th className="px-3 py-2 text-right">Value Allocated (₹)</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-gray-50">
                                            {storageItems.map(item => (
                                                <tr
                                                    key={item.id}
                                                    className={selected.has(item.id) ? 'bg-blue-50' : 'hover:bg-gray-50'}
                                                    onClick={() => toggleItem(item.id)}
                                                >
                                                    <td className="px-3 py-2 text-center">
                                                        <input
                                                            type="checkbox"
                                                            checked={selected.has(item.id)}
                                                            onChange={() => toggleItem(item.id)}
                                                            onClick={e => e.stopPropagation()}
                                                            className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                                                        />
                                                    </td>
                                                    <td className="px-3 py-2 font-medium text-gray-900">{item.part_name_snapshot}</td>
                                                    <td className="px-3 py-2 text-right text-gray-600">{item.quantity_snapshot}</td>
                                                    <td className="px-3 py-2 text-gray-500">{item.unit_snapshot}</td>
                                                    <td className="px-3 py-2 text-gray-500 text-xs">{item.source_vehicle_number || '—'}</td>
                                                    <td className="px-3 py-2 text-right" onClick={e => e.stopPropagation()}>
                                                        {selected.has(item.id) && (
                                                            <input
                                                                type="number"
                                                                min="0.01"
                                                                step="0.01"
                                                                placeholder="0.00"
                                                                className="w-28 border rounded px-2 py-1 text-sm text-right focus:ring-2 focus:ring-blue-500"
                                                                value={valueAllocated[item.id] || ''}
                                                                onChange={e => setItemValue(item.id, e.target.value)}
                                                                autoFocus
                                                            />
                                                        )}
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            )}
                        </div>

                        {error && (
                            <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{error}</p>
                        )}
                    </div>

                    {/* Footer */}
                    <div className="px-6 py-4 border-t flex items-center justify-between bg-gray-50 rounded-b-xl">
                        <div className="text-sm font-semibold text-gray-700">
                            Total: <span className="text-gray-900">₹{itemsTotal.toFixed(2)}</span>
                            {selected.size > 0 && (
                                <span className="ml-2 text-xs font-normal text-gray-400">
                                    ({selected.size} item{selected.size !== 1 ? 's' : ''} selected)
                                </span>
                            )}
                        </div>
                        <div className="flex gap-3">
                            <button
                                type="button"
                                onClick={onClose}
                                className="px-4 py-2 text-sm text-gray-700 border rounded-lg hover:bg-gray-100"
                            >
                                Cancel
                            </button>
                            <button
                                type="submit"
                                disabled={recordDisposal.isPending || photos.some(p => p.uploading)}
                                className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                            >
                                {recordDisposal.isPending ? 'Saving…' : 'Record Sale'}
                            </button>
                        </div>
                    </div>
                </form>
            </div>
        </div>
    )
}
