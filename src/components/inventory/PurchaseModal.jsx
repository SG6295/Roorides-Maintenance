import { useState, Fragment, useRef } from 'react'
import { useAuth } from '../../hooks/useAuth'
import { useParts, useRecordPurchase, useCreatePart, usePartUnits } from '../../hooks/useInventory'
import { PlusIcon, TrashIcon, XMarkIcon, CheckIcon, ChevronUpDownIcon, PaperClipIcon, ArrowUpTrayIcon } from '@heroicons/react/24/outline'
import { Listbox, ListboxButton, ListboxOptions, ListboxOption, Transition } from '@headlessui/react'
import CustomSelect from '../shared/CustomSelect'
import { supabase } from '../../lib/supabase'

const NEW_PART_SENTINEL = '__NEW__'
const emptyLine = () => ({ part_id: '', quantity: '', unit_price: '' })
const emptyNewPartForm = () => ({ name: '', part_number: '', unit: 'pcs', saving: false, error: null })

export default function PurchaseModal({ onClose }) {
    const { userProfile } = useAuth()
    const { data: parts = [] } = useParts()
    const { data: partUnits = [] } = usePartUnits()
    const recordPurchase = useRecordPurchase()
    const createPart = useCreatePart()
    const fileInputRef = useRef(null)

    // keyed by line index: { name, part_number, unit, saving, error }
    const [newPartForms, setNewPartForms] = useState({})

    const [invoice, setInvoice] = useState({
        invoice_number: '',
        supplier_name: '',
        invoice_date: '',
        notes: '',
    })
    const [lines, setLines] = useState([emptyLine()])
    const [error, setError] = useState(null)

    // Invoice file attachment
    const [invoiceFile, setInvoiceFile] = useState(null) // { name, url, uploading }

    async function handleFileSelect(e) {
        const file = e.target.files?.[0]
        if (!file) return

        const allowed = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/jpg', 'application/pdf']
        if (!allowed.includes(file.type)) {
            alert('Only images (JPG, PNG) and PDFs are allowed.')
            return
        }
        if (file.size > 20 * 1024 * 1024) {
            alert('File must be under 20MB.')
            return
        }

        setInvoiceFile({ name: file.name, url: null, uploading: true })

        try {
            const formData = new FormData()
            formData.append('file', file)
            const { data: { session } } = await supabase.auth.getSession()
            const response = await fetch(
                `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/upload-to-drive`,
                { method: 'POST', headers: { 'Authorization': `Bearer ${session?.access_token}` }, body: formData }
            )
            if (!response.ok) throw new Error('Upload failed')
            const result = await response.json()
            setInvoiceFile({ name: file.name, url: result.url, uploading: false })
        } catch (err) {
            console.error(err)
            alert('Failed to upload file. Please try again.')
            setInvoiceFile(null)
        }
        // Reset input so same file can be re-selected if removed
        e.target.value = ''
    }

    const invoiceTotal = lines.reduce((sum, l) => {
        const qty = parseFloat(l.quantity) || 0
        const price = parseFloat(l.unit_price) || 0
        return sum + qty * price
    }, 0)

    function updateLine(index, field, value) {
        setLines(prev => prev.map((l, i) => i === index ? { ...l, [field]: value } : l))
    }

    function handlePartSelect(index, value) {
        if (value === NEW_PART_SENTINEL) {
            setNewPartForms(prev => ({ ...prev, [index]: emptyNewPartForm() }))
            updateLine(index, 'part_id', '')
        } else {
            setNewPartForms(prev => { const n = { ...prev }; delete n[index]; return n })
            updateLine(index, 'part_id', value)
        }
    }

    function updateNewPartForm(index, field, value) {
        setNewPartForms(prev => ({ ...prev, [index]: { ...prev[index], [field]: value } }))
    }

    async function confirmNewPart(index) {
        const form = newPartForms[index]
        if (!form.name.trim()) {
            setNewPartForms(prev => ({ ...prev, [index]: { ...prev[index], error: 'Part name is required.' } }))
            return
        }
        setNewPartForms(prev => ({ ...prev, [index]: { ...prev[index], saving: true, error: null } }))
        try {
            const newPart = await createPart.mutateAsync({
                name: form.name.trim(),
                part_number: form.part_number.trim() || null,
                unit: form.unit.trim() || 'pcs',
                quantity_in_stock: 0,
            })
            updateLine(index, 'part_id', newPart.id)
            setNewPartForms(prev => { const n = { ...prev }; delete n[index]; return n })
        } catch (err) {
            setNewPartForms(prev => ({ ...prev, [index]: { ...prev[index], saving: false, error: err.message } }))
        }
    }

    function cancelNewPart(index) {
        setNewPartForms(prev => { const n = { ...prev }; delete n[index]; return n })
    }

    function addLine() {
        setLines(prev => [...prev, emptyLine()])
    }

    function removeLine(index) {
        setLines(prev => prev.filter((_, i) => i !== index))
    }

    async function handleSubmit(e) {
        e.preventDefault()
        setError(null)

        // Validate lines
        const validLines = lines.filter(l => l.part_id && l.quantity && l.unit_price)
        if (validLines.length === 0) {
            setError('Add at least one line item.')
            return
        }
        if (lines.some(l => l.part_id && (!l.quantity || !l.unit_price))) {
            setError('All line items must have a quantity and unit price.')
            return
        }

        try {
            await recordPurchase.mutateAsync({
                invoice: {
                    ...invoice,
                    total_amount: invoiceTotal,
                    created_by: userProfile.id,
                    ...(invoiceFile?.url ? { invoice_file_url: invoiceFile.url } : {}),
                },
                lineItems: validLines.map(l => ({
                    part_id: l.part_id,
                    quantity: parseFloat(l.quantity),
                    unit_price: parseFloat(l.unit_price),
                })),
            })
            onClose()
        } catch (err) {
            setError(err.message)
        }
    }

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-3xl max-h-[90vh] flex flex-col">
                {/* Header */}
                <div className="flex items-center justify-between px-6 py-4 border-b">
                    <h2 className="text-lg font-semibold text-gray-900">Record Purchase</h2>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                <form onSubmit={handleSubmit} className="flex flex-col flex-1 overflow-hidden">
                    <div className="overflow-y-auto flex-1 px-6 py-4 space-y-6">
                        {/* Invoice Details */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">Invoice Details</h3>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Supplier Name <span className="text-red-500">*</span>
                                    </label>
                                    <input
                                        required
                                        type="text"
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        value={invoice.supplier_name}
                                        onChange={e => setInvoice(p => ({ ...p, supplier_name: e.target.value }))}
                                        placeholder="e.g. AutoParts Ltd"
                                    />
                                </div>
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Invoice Number <span className="text-red-500">*</span>
                                    </label>
                                    <input
                                        required
                                        type="text"
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        value={invoice.invoice_number}
                                        onChange={e => setInvoice(p => ({ ...p, invoice_number: e.target.value }))}
                                        placeholder="e.g. INV-2024-001"
                                    />
                                </div>
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Invoice Date <span className="text-red-500">*</span>
                                    </label>
                                    <input
                                        required
                                        type="date"
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        value={invoice.invoice_date}
                                        onChange={e => setInvoice(p => ({ ...p, invoice_date: e.target.value }))}
                                    />
                                </div>
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
                                    <input
                                        type="text"
                                        className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                        value={invoice.notes}
                                        onChange={e => setInvoice(p => ({ ...p, notes: e.target.value }))}
                                        placeholder="Optional"
                                    />
                                </div>
                            </div>
                        </div>

                        {/* Invoice File Attachment */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">Invoice Document</h3>
                            <input
                                ref={fileInputRef}
                                type="file"
                                accept="image/*,application/pdf"
                                onChange={handleFileSelect}
                                className="hidden"
                            />
                            {!invoiceFile ? (
                                <button
                                    type="button"
                                    onClick={() => fileInputRef.current?.click()}
                                    className="flex items-center gap-2 px-4 py-2.5 border-2 border-dashed border-gray-300 rounded-lg text-sm text-gray-500 hover:border-blue-400 hover:text-blue-600 transition-colors w-full justify-center"
                                >
                                    <ArrowUpTrayIcon className="w-4 h-4" />
                                    Attach invoice image or PDF
                                </button>
                            ) : invoiceFile.uploading ? (
                                <div className="flex items-center gap-2 px-4 py-2.5 border rounded-lg text-sm text-gray-500 bg-gray-50">
                                    <div className="w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
                                    Uploading {invoiceFile.name}…
                                </div>
                            ) : (
                                <div className="flex items-center gap-2 px-4 py-2.5 border border-green-200 rounded-lg bg-green-50">
                                    <PaperClipIcon className="w-4 h-4 text-green-600 shrink-0" />
                                    <a href={invoiceFile.url} target="_blank" rel="noopener noreferrer" className="text-sm text-green-700 hover:underline truncate flex-1">
                                        {invoiceFile.name}
                                    </a>
                                    <button type="button" onClick={() => setInvoiceFile(null)} className="text-gray-400 hover:text-red-500 shrink-0">
                                        <XMarkIcon className="w-4 h-4" />
                                    </button>
                                </div>
                            )}
                        </div>

                        {/* Line Items */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">Line Items</h3>
                            <div className="space-y-2">
                                {/* Column headers */}
                                <div className="grid grid-cols-12 gap-2 px-1 text-xs font-medium text-gray-500">
                                    <div className="col-span-5">Part</div>
                                    <div className="col-span-2">Qty</div>
                                    <div className="col-span-2">Unit Price</div>
                                    <div className="col-span-2">Line Total</div>
                                    <div className="col-span-1"></div>
                                </div>

                                {lines.map((line, i) => {
                                    const lineTotal = (parseFloat(line.quantity) || 0) * (parseFloat(line.unit_price) || 0)
                                    const npf = newPartForms[i]
                                    const selectedPart = parts.find(p => p.id === line.part_id)
                                    return (
                                        <div key={i} className="grid grid-cols-12 gap-2 items-start">
                                            <div className="col-span-5">
                                                {npf ? (
                                                    /* ── Inline new-part form ── */
                                                    <div className="border border-blue-300 rounded-lg p-2 bg-blue-50 space-y-1.5">
                                                        <p className="text-xs font-medium text-blue-700">New part</p>
                                                        <input
                                                            autoFocus
                                                            type="text"
                                                            placeholder="Part name *"
                                                            className="w-full border rounded px-2 py-1 text-xs focus:ring-1 focus:ring-blue-400"
                                                            value={npf.name}
                                                            onChange={e => updateNewPartForm(i, 'name', e.target.value)}
                                                        />
                                                        <div className="flex gap-1">
                                                            <input
                                                                type="text"
                                                                placeholder="Part # (optional)"
                                                                className="flex-1 border rounded px-2 py-1 text-xs focus:ring-1 focus:ring-blue-400"
                                                                value={npf.part_number}
                                                                onChange={e => updateNewPartForm(i, 'part_number', e.target.value)}
                                                            />
                                                            <div className="w-24">
                                                                <CustomSelect
                                                                    compact
                                                                    value={npf.unit}
                                                                    onChange={val => updateNewPartForm(i, 'unit', val)}
                                                                    options={partUnits.map(u => u.name)}
                                                                />
                                                            </div>
                                                        </div>
                                                        {npf.error && (
                                                            <p className="text-xs text-red-600">{npf.error}</p>
                                                        )}
                                                        <div className="flex gap-2 pt-0.5">
                                                            <button
                                                                type="button"
                                                                onClick={() => confirmNewPart(i)}
                                                                disabled={npf.saving}
                                                                className="flex items-center gap-1 px-2 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
                                                            >
                                                                <CheckIcon className="w-3 h-3" />
                                                                {npf.saving ? 'Adding…' : 'Add part'}
                                                            </button>
                                                            <button
                                                                type="button"
                                                                onClick={() => cancelNewPart(i)}
                                                                className="px-2 py-1 text-xs text-gray-500 hover:text-gray-700"
                                                            >
                                                                Cancel
                                                            </button>
                                                        </div>
                                                    </div>
                                                ) : (
                                                    /* ── Part dropdown ── */
                                                    <Listbox value={line.part_id} onChange={val => handlePartSelect(i, val)}>
                                                        <div className="relative">
                                                            <ListboxButton className="relative w-full cursor-default rounded-lg bg-white border border-gray-300 py-2.5 pl-3 pr-10 text-left text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500">
                                                                <span className={line.part_id ? 'text-gray-900' : 'text-gray-400'}>
                                                                    {line.part_id
                                                                        ? (() => { const p = parts.find(p => p.id === line.part_id); return p ? `${p.name}${p.part_number ? ` (${p.part_number})` : ''} · ${p.unit}` : 'Select part…' })()
                                                                        : 'Select part…'}
                                                                </span>
                                                                <span className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-2">
                                                                    <ChevronUpDownIcon className="h-4 w-4 text-gray-400" />
                                                                </span>
                                                            </ListboxButton>
                                                            <Transition as={Fragment} leave="transition ease-in duration-100" leaveFrom="opacity-100" leaveTo="opacity-0">
                                                                <ListboxOptions anchor="bottom start" className="z-[100] mt-1 max-h-60 w-[var(--button-width)] overflow-auto rounded-md bg-white py-1 text-sm shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
                                                                    {/* Create new part */}
                                                                    <ListboxOption value={NEW_PART_SENTINEL} className={({ active }) => `cursor-default select-none py-2 pl-3 pr-9 text-blue-600 font-medium ${active ? 'bg-blue-50' : ''}`}>
                                                                        + Create new part…
                                                                    </ListboxOption>
                                                                    <div className="my-1 border-t border-gray-100" />
                                                                    {/* Existing parts */}
                                                                    {parts.map(p => (
                                                                        <ListboxOption
                                                                            key={p.id}
                                                                            value={p.id}
                                                                            className={({ active }) => `cursor-default select-none py-2 pl-3 pr-9 ${active ? 'bg-blue-600 text-white' : 'text-gray-900'}`}
                                                                        >
                                                                            {({ selected, active }) => (
                                                                                <>
                                                                                    <span className={selected ? 'font-semibold' : 'font-normal'}>
                                                                                        {p.name}{p.part_number ? ` (${p.part_number})` : ''} · {p.unit}
                                                                                    </span>
                                                                                    {selected && (
                                                                                        <span className={`absolute inset-y-0 right-0 flex items-center pr-3 ${active ? 'text-white' : 'text-blue-600'}`}>
                                                                                            <CheckIcon className="h-4 w-4" />
                                                                                        </span>
                                                                                    )}
                                                                                </>
                                                                            )}
                                                                        </ListboxOption>
                                                                    ))}
                                                                </ListboxOptions>
                                                            </Transition>
                                                        </div>
                                                    </Listbox>
                                                )}
                                            </div>
                                            <div className="col-span-2 pt-1">
                                                <div className="relative">
                                                    <input
                                                        type="number"
                                                        min="0.01"
                                                        step="0.01"
                                                        className={`w-full border rounded-lg px-2 py-2 text-sm focus:ring-2 focus:ring-blue-500 ${selectedPart ? 'pr-10' : ''}`}
                                                        placeholder="0"
                                                        value={line.quantity}
                                                        onChange={e => updateLine(i, 'quantity', e.target.value)}
                                                    />
                                                    {selectedPart && (
                                                        <span className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-gray-400 pointer-events-none">
                                                            {selectedPart.unit}
                                                        </span>
                                                    )}
                                                </div>
                                            </div>
                                            <div className="col-span-2 pt-1">
                                                <input
                                                    type="number"
                                                    min="0"
                                                    step="0.01"
                                                    className="w-full border rounded-lg px-2 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                                    placeholder="0.00"
                                                    value={line.unit_price}
                                                    onChange={e => updateLine(i, 'unit_price', e.target.value)}
                                                />
                                            </div>
                                            <div className="col-span-2 text-sm text-gray-700 text-right pr-2 pt-3">
                                                {lineTotal > 0 ? lineTotal.toFixed(2) : '—'}
                                            </div>
                                            <div className="col-span-1 flex justify-center pt-3">
                                                {lines.length > 1 && (
                                                    <button
                                                        type="button"
                                                        onClick={() => removeLine(i)}
                                                        className="text-gray-400 hover:text-red-500"
                                                    >
                                                        <TrashIcon className="w-4 h-4" />
                                                    </button>
                                                )}
                                            </div>
                                        </div>
                                    )
                                })}
                            </div>

                            <button
                                type="button"
                                onClick={addLine}
                                className="mt-3 flex items-center gap-1 text-sm text-blue-600 hover:text-blue-800"
                            >
                                <PlusIcon className="w-4 h-4" />
                                Add line item
                            </button>
                        </div>

                        {error && (
                            <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{error}</p>
                        )}
                    </div>

                    {/* Footer */}
                    <div className="px-6 py-4 border-t flex items-center justify-between bg-gray-50 rounded-b-xl">
                        <div className="text-sm font-semibold text-gray-700">
                            Invoice Total: <span className="text-gray-900">{invoiceTotal.toFixed(2)}</span>
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
                                disabled={recordPurchase.isPending}
                                className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                            >
                                {recordPurchase.isPending ? 'Saving…' : 'Record Purchase'}
                            </button>
                        </div>
                    </div>
                </form>
            </div>
        </div>
    )
}
