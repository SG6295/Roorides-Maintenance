import { useState, useRef } from 'react'
import { XMarkIcon, ArrowUpTrayIcon, PaperClipIcon } from '@heroicons/react/24/outline'
import { useAuth } from '../../hooks/useAuth'
import { useScrapInventory, useRecordScrapWriteoff } from '../../hooks/useScrap'
import { logAuditEvent } from '../../utils/auditLogger'
import { supabase } from '../../lib/supabase'

const REASON_OPTIONS = [
    { value: 'lost',                 label: 'Lost' },
    { value: 'damaged_unsaleable',   label: 'Damaged / Unsaleable' },
    { value: 'hazmat_disposal',      label: 'Hazmat Disposal' },
    { value: 'stocktake_adjustment', label: 'Stocktake Adjustment' },
    { value: 'donated',              label: 'Donated' },
    { value: 'other',                label: 'Other' },
]

const emptyHeader = () => ({
    writeoff_date: '',
    reason:        'lost',
    description:   '',
    notes:         '',
})

export default function RecordWriteoffModal({ onClose }) {
    const { userProfile } = useAuth()
    const { data: storageItems = [], isLoading: itemsLoading } = useScrapInventory({ status: 'in_storage' })
    const recordWriteoff = useRecordScrapWriteoff()
    const fileInputRef = useRef(null)

    const [header, setHeader] = useState(emptyHeader())
    const [photos, setPhotos] = useState([])
    const [selected, setSelected] = useState(new Set())
    const [error, setError] = useState(null)

    // ── Photo upload ──────────────────────────────────────────────────────────

    async function handleFileSelect(e) {
        const files = Array.from(e.target.files || [])
        if (!files.length) return
        e.target.value = ''

        for (const file of files) {
            const allowed = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/jpg']
            if (!allowed.includes(file.type)) {
                setError('Only image files (JPG, PNG) are allowed for evidence photos.')
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
            if (next.has(id)) next.delete(id)
            else next.add(id)
            return next
        })
    }

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
            setError('At least one evidence photo is required.')
            return
        }
        if (photos.some(p => p.uploading)) {
            setError('Please wait for photo uploads to finish.')
            return
        }

        try {
            const result = await recordWriteoff.mutateAsync({
                header: {
                    writeoff_date:   header.writeoff_date,
                    reason:          header.reason,
                    description:     header.description,
                    evidence_photos: readyPhotos.map(p => p.url),
                    notes:           header.notes || null,
                },
                items: [...selected].map(id => ({ scrap_inventory_id: id })),
            })

            await logAuditEvent(result.writeoff_id, 'scrap_writeoff', 'INSERT', userProfile.id, {
                oldData: null,
                newData: { writeoff_date: header.writeoff_date, reason: header.reason, description: header.description },
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
                    <h2 className="text-lg font-semibold text-gray-900">Record Scrap Write-off</h2>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                <form onSubmit={handleSubmit} className="flex flex-col flex-1 overflow-hidden">
                    <div className="overflow-y-auto flex-1 px-6 py-4 space-y-6">

                        {/* Write-off Details */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">Write-off Details</h3>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Write-off Date <span className="text-red-500">*</span>
                                    </label>
                                    <input
                                        required
                                        type="date"
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        value={header.writeoff_date}
                                        onChange={e => setHeader(p => ({ ...p, writeoff_date: e.target.value }))}
                                    />
                                </div>
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Reason <span className="text-red-500">*</span>
                                    </label>
                                    <select
                                        required
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 bg-white"
                                        value={header.reason}
                                        onChange={e => setHeader(p => ({ ...p, reason: e.target.value }))}
                                    >
                                        {REASON_OPTIONS.map(o => (
                                            <option key={o.value} value={o.value}>{o.label}</option>
                                        ))}
                                    </select>
                                </div>
                                <div className="sm:col-span-2">
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Description <span className="text-red-500">*</span>
                                    </label>
                                    <textarea
                                        required
                                        rows={3}
                                        placeholder="Describe the reason for write-off in detail…"
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 resize-none"
                                        value={header.description}
                                        onChange={e => setHeader(p => ({ ...p, description: e.target.value }))}
                                    />
                                </div>
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

                        {/* Evidence Photos */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">
                                Evidence Photos <span className="text-red-500">*</span>
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
                                    className="flex items-center gap-2 px-4 py-2.5 border-2 border-dashed border-gray-300 rounded-lg text-sm text-gray-500 hover:border-orange-400 hover:text-orange-600 transition-colors w-full justify-center"
                                >
                                    <ArrowUpTrayIcon className="w-4 h-4" />
                                    {photos.length > 0 ? 'Add another photo' : 'Upload evidence photo'}
                                </button>
                            </div>
                        </div>

                        {/* Item Selection */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">
                                Select Items to Write Off <span className="text-red-500">*</span>
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
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-gray-50">
                                            {storageItems.map(item => (
                                                <tr
                                                    key={item.id}
                                                    className={`cursor-pointer ${selected.has(item.id) ? 'bg-orange-50' : 'hover:bg-gray-50'}`}
                                                    onClick={() => toggleItem(item.id)}
                                                >
                                                    <td className="px-3 py-2 text-center">
                                                        <input
                                                            type="checkbox"
                                                            checked={selected.has(item.id)}
                                                            onChange={() => toggleItem(item.id)}
                                                            onClick={e => e.stopPropagation()}
                                                            className="rounded border-gray-300 text-orange-500 focus:ring-orange-500"
                                                        />
                                                    </td>
                                                    <td className="px-3 py-2 font-medium text-gray-900">{item.part_name_snapshot}</td>
                                                    <td className="px-3 py-2 text-right text-gray-600">{item.quantity_snapshot}</td>
                                                    <td className="px-3 py-2 text-gray-500">{item.unit_snapshot}</td>
                                                    <td className="px-3 py-2 text-gray-500 text-xs">{item.source_vehicle_number || '—'}</td>
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
                        <div className="text-sm text-gray-600">
                            {selected.size > 0
                                ? <span>{selected.size} item{selected.size !== 1 ? 's' : ''} selected</span>
                                : <span className="text-gray-400">No items selected</span>
                            }
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
                                disabled={recordWriteoff.isPending || photos.some(p => p.uploading)}
                                className="px-5 py-2 text-sm bg-orange-600 text-white rounded-lg hover:bg-orange-700 disabled:opacity-50"
                            >
                                {recordWriteoff.isPending ? 'Saving…' : 'Record Write-off'}
                            </button>
                        </div>
                    </div>
                </form>
            </div>
        </div>
    )
}
