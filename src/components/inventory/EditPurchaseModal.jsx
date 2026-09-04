import { useState, useEffect } from 'react'
import { usePurchaseInvoiceItems, useUpdatePurchaseInvoice, useParts, useCreatePart, usePartUnits } from '../../hooks/useInventory'
import { useWorkshopLocations } from '../../hooks/useWorkshopLocations'
import {
    PlusIcon, TrashIcon, XMarkIcon, CheckIcon, ExclamationTriangleIcon,
} from '@heroicons/react/24/outline'
import CustomSelect from '../shared/CustomSelect'
import SearchableSelect from '../shared/SearchableSelect'
import MultiFileAttach from '../shared/MultiFileAttach'
import {
    round2,
    lineSubtotal,
    lineTotal as calcLineTotal,
    invoiceTotal as calcInvoiceTotal,
    totalDiscount as calcTotalDiscount,
    syncLineDiscount,
    distributeTotalDiscount,
} from '../../lib/invoiceDiscount'

const NEW_PART_SENTINEL = '__NEW__'
const GST_RATES = [
    { label: 'None', value: 0 },
    { label: '5%', value: 5 },
    { label: '12%', value: 12 },
    { label: '18%', value: 18 },
    { label: '28%', value: 28 },
]
// Line-item columns. Qty needs more than a 12th of the row so 2-decimal
// quantities aren't clipped by the in-field unit suffix; the trailing
// remove-button column needs less.
const LINE_GRID = 'grid gap-2 grid-cols-[minmax(0,3fr)_minmax(0,1.5fr)_minmax(0,2fr)_minmax(0,1fr)_minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_minmax(0,0.5fr)]'
const emptyNewLine = () => ({ id: null, part_id: '', quantity: '', unit_price: '', gst_rate: 0, discount_amount: '', discount_pct: '', discount_mode: 'amount' })
const emptyNewPartForm = () => ({ name: '', part_number: '', unit: 'pcs', saving: false, error: null })

export default function EditPurchaseModal({ invoice, onClose }) {
    const { data: existingItems, isLoading: itemsLoading } = usePurchaseInvoiceItems(invoice.id)
    const { data: parts = [] } = useParts()
    const { data: partUnits = [] } = usePartUnits()
    const { data: locations = [] } = useWorkshopLocations()
    const updateInvoice = useUpdatePurchaseInvoice()
    const createPart = useCreatePart()

    const [invoiceData, setInvoiceData] = useState({
        invoice_number: invoice.invoice_number,
        supplier_name: invoice.supplier_name,
        invoice_date: invoice.invoice_date,
        notes: invoice.notes || '',
        location_id: invoice.location_id,
    })

    // lines = mix of existing items (have id) and new items (id: null)
    const [lines, setLines] = useState(null)
    const [originalItems, setOriginalItems] = useState([])

    // keyed by line index — only for new (id: null) lines
    const [newPartForms, setNewPartForms] = useState({})

    const [error, setError] = useState(null)
    const [invoiceFile, setInvoiceFile] = useState(
        invoice.invoice_file_url
            ? { name: 'Existing document', url: invoice.invoice_file_url }
            : null
    )

    // Populate lines from loaded items (runs once)
    useEffect(() => {
        if (existingItems && lines === null) {
            const mapped = existingItems.map(item => {
                const disc = Number(item.discount_amount) || 0
                const sub = (Number(item.quantity) || 0) * (Number(item.unit_price) || 0)
                return {
                    id: item.id,
                    part_id: item.part_id,
                    part_name: item.part?.name || '',
                    part_number: item.part?.part_number || '',
                    part_unit: item.part?.unit || '',
                    quantity: String(item.quantity),
                    unit_price: String(item.unit_price),
                    gst_rate: item.gst_rate ?? 0,
                    discount_amount: disc ? String(disc) : '',
                    discount_pct: disc && sub > 0 ? String(round2((disc / sub) * 100)) : '',
                    discount_mode: 'amount',
                }
            })
            setLines(mapped)
            setOriginalItems(mapped.map(m => ({ id: m.id })))
        }
    }, [existingItems, lines])

    // ── Line helpers ───────────────────────────────────────────────────────────
    const invoiceTotal = calcInvoiceTotal(lines || [])
    const totalDiscount = calcTotalDiscount(lines || [])

    function updateLine(index, field, value) {
        setLines(prev => prev.map((l, i) => i === index ? { ...l, [field]: value } : l))
    }

    // Setter that keeps the discount %/amount pair in sync after an edit.
    function setLineField(index, field, value) {
        setLines(prev => prev.map((l, i) =>
            i === index ? syncLineDiscount({ ...l, [field]: value }, field) : l
        ))
    }

    function handleTotalDiscountChange(value) {
        setLines(prev => distributeTotalDiscount(prev, value === '' ? 0 : value))
    }

    function removeLine(index) {
        // Also clear any pending new-part form for this line
        setNewPartForms(prev => { const n = { ...prev }; delete n[index]; return n })
        setLines(prev => prev.filter((_, i) => i !== index))
    }

    function addLine() {
        setLines(prev => [...prev, emptyNewLine()])
    }

    // New-part form helpers (only for new lines, i.e. id === null)
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

    // Changing an invoice's workshop moves every quantity it inwarded, so say so first.
    const locationChanged = invoiceData.location_id !== invoice.location_id
    const locationName = id => locations.find(l => l.id === id)?.name || 'the previous workshop'
    const originalLocationName = locationName(invoice.location_id)
    const newLocationName = locationName(invoiceData.location_id)

    // ── Submit ─────────────────────────────────────────────────────────────────
    async function handleSubmit(e) {
        e.preventDefault()
        setError(null)

        if (!invoiceData.location_id) {
            setError('Choose which workshop this invoice is being inwarded to.')
            return
        }
        if (locationChanged && !window.confirm(
            `Move everything on this invoice from ${originalLocationName} to ${newLocationName}?`
        )) {
            return
        }

        const activeLines = lines || []
        if (activeLines.length === 0) {
            setError('At least one line item is required.')
            return
        }

        // Existing lines always have a part; new lines need part_id selected
        const newLines = activeLines.filter(l => !l.id)
        if (newLines.some(l => !l.part_id)) {
            setError('Select a part for all new line items.')
            return
        }
        if (activeLines.some(l => !l.quantity || !l.unit_price)) {
            setError('All line items must have a quantity and unit price.')
            return
        }
        // '0' is truthy, so the check above lets a zero quantity through
        if (activeLines.some(l => parseFloat(l.quantity) <= 0)) {
            setError('Quantity must be greater than zero.')
            return
        }
        if (activeLines.some(l => (parseFloat(l.discount_amount) || 0) > lineSubtotal(l) + 1e-9)) {
            setError('A line discount cannot exceed its item subtotal (qty × unit price).')
            return
        }

        try {
            await updateInvoice.mutateAsync({
                invoiceId: invoice.id,
                invoiceData: {
                    ...invoiceData,
                    invoice_file_url: invoiceFile?.url || null,
                },
                lineItems: activeLines,
                originalItems,
            })
            onClose()
        } catch (err) {
            setError(err.message)
        }
    }

    // ── Render ─────────────────────────────────────────────────────────────────
    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-5xl max-h-[90vh] flex flex-col">
                {/* Header */}
                <div className="flex items-center justify-between px-6 py-4 border-b">
                    <h2 className="text-lg font-semibold text-gray-900">Edit Purchase</h2>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                {itemsLoading || lines === null ? (
                    <div className="flex-1 flex items-center justify-center py-16 text-sm text-gray-400">
                        Loading invoice details…
                    </div>
                ) : (
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
                                            value={invoiceData.supplier_name}
                                            onChange={e => setInvoiceData(p => ({ ...p, supplier_name: e.target.value }))}
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
                                            value={invoiceData.invoice_number}
                                            onChange={e => setInvoiceData(p => ({ ...p, invoice_number: e.target.value }))}
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
                                            value={invoiceData.invoice_date}
                                            onChange={e => setInvoiceData(p => ({ ...p, invoice_date: e.target.value }))}
                                        />
                                    </div>
                                    <div>
                                        <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
                                        <input
                                            type="text"
                                            className="w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                            value={invoiceData.notes}
                                            onChange={e => setInvoiceData(p => ({ ...p, notes: e.target.value }))}
                                            placeholder="Optional"
                                        />
                                    </div>
                                    <div className="sm:col-span-2">
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Inward to Workshop <span className="text-red-500">*</span>
                                        </label>
                                        <CustomSelect
                                            value={invoiceData.location_id}
                                            onChange={v => setInvoiceData(p => ({ ...p, location_id: v }))}
                                            options={locations.map(l => ({
                                                value: l.id,
                                                label: l.address ? `${l.name} — ${l.address}` : l.name,
                                            }))}
                                            placeholder="Select workshop"
                                            compact
                                        />
                                        {locationChanged && (
                                            <p className="flex items-start gap-1.5 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2 mt-2">
                                                <ExclamationTriangleIcon className="w-4 h-4 flex-shrink-0 mt-px" />
                                                <span>
                                                    Saving will move everything this invoice inwarded from{' '}
                                                    <strong>{originalLocationName}</strong> to <strong>{newLocationName}</strong>.
                                                    If any of it has already been used, the move will be refused.
                                                </span>
                                            </p>
                                        )}
                                    </div>
                                </div>
                            </div>

                            {/* Invoice Document */}
                            <div>
                                <h3 className="text-sm font-semibold text-gray-700 mb-3">Invoice Document</h3>
                                <MultiFileAttach value={invoiceFile} onChange={setInvoiceFile} />
                            </div>

                            {/* Line Items */}
                            <div>
                                <h3 className="text-sm font-semibold text-gray-700 mb-3">Line Items</h3>
                                <div className="space-y-2">
                                    <div className={`${LINE_GRID} px-1 text-xs font-medium text-gray-500`}>
                                        <div>Part</div>
                                        <div>Qty</div>
                                        <div>Unit Price</div>
                                        <div>Disc %</div>
                                        <div>Discount</div>
                                        <div>GST</div>
                                        <div className="text-right">Line Total</div>
                                        <div></div>
                                    </div>

                                    {lines.map((line, i) => {
                                        const sub = lineSubtotal(line)
                                        const lineTotal = calcLineTotal(line)
                                        const isExisting = !!line.id
                                        const npf = !isExisting ? newPartForms[i] : null
                                        const selectedPart = !isExisting ? parts.find(p => p.id === line.part_id) : null
                                        const discountInvalid = (parseFloat(line.discount_amount) || 0) > sub + 1e-9

                                        return (
                                            <div key={line.id || `new-${i}`} className={`${LINE_GRID} items-start`}>
                                                {/* Part cell */}
                                                <div>
                                                    {isExisting ? (
                                                        /* Existing item — part is locked, shown as read-only */
                                                        <div className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-gray-50 text-gray-700 truncate">
                                                            {line.part_name}
                                                            {line.part_number && (
                                                                <span className="text-gray-400 font-mono text-xs ml-1">({line.part_number})</span>
                                                            )}
                                                            {line.part_unit && (
                                                                <span className="text-gray-400 text-xs ml-1">· {line.part_unit}</span>
                                                            )}
                                                        </div>
                                                    ) : npf ? (
                                                        /* Inline new-part form */
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
                                                        /* Part dropdown for new lines */
                                                        <SearchableSelect
                                                            value={line.part_id}
                                                            onChange={val => handlePartSelect(i, val)}
                                                            options={parts.map(p => ({
                                                                value: p.id,
                                                                label: `${p.name}${p.part_number ? ` (${p.part_number})` : ''} · ${p.unit}`,
                                                            }))}
                                                            placeholder="Select part…"
                                                            showAllOnFocus={true}
                                                            pinnedOption={{ value: NEW_PART_SENTINEL, label: '+ Create new part…' }}
                                                        />
                                                    )}
                                                </div>

                                                {/* Qty */}
                                                <div className="pt-1">
                                                    <div className="relative">
                                                        <input
                                                            type="number"
                                                            min="0"
                                                            step="any"
                                                            className={`w-full border rounded-lg px-2 py-2 text-sm focus:ring-2 focus:ring-blue-500 ${(isExisting ? line.part_unit : selectedPart?.unit) ? 'pr-7' : ''}`}
                                                            placeholder="0"
                                                            value={line.quantity}
                                                            onChange={e => setLineField(i, 'quantity', e.target.value)}
                                                        />
                                                        {(isExisting ? line.part_unit : selectedPart?.unit) && (
                                                            <span className="absolute right-1.5 top-1/2 -translate-y-1/2 text-[10px] text-gray-400 pointer-events-none">
                                                                {isExisting ? line.part_unit : selectedPart?.unit}
                                                            </span>
                                                        )}
                                                    </div>
                                                </div>

                                                {/* Unit Price */}
                                                <div className="pt-1">
                                                    <input
                                                        type="number"
                                                        min="0"
                                                        step="0.01"
                                                        className="no-spinner w-full border rounded-lg px-2 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                                        placeholder="0.00"
                                                        value={line.unit_price}
                                                        onChange={e => setLineField(i, 'unit_price', e.target.value)}
                                                    />
                                                </div>

                                                {/* Discount % */}
                                                <div className="pt-1">
                                                    <input
                                                        type="number"
                                                        min="0"
                                                        max="100"
                                                        step="0.01"
                                                        className="no-spinner w-full border rounded-lg px-2 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                                        placeholder="0"
                                                        value={line.discount_pct}
                                                        onChange={e => setLineField(i, 'discount_pct', e.target.value)}
                                                    />
                                                </div>

                                                {/* Discount amount */}
                                                <div className="pt-1">
                                                    <input
                                                        type="number"
                                                        min="0"
                                                        step="0.01"
                                                        className={`no-spinner w-full border rounded-lg px-2 py-2 text-sm focus:ring-2 ${discountInvalid ? 'border-red-400 focus:ring-red-500' : 'focus:ring-blue-500'}`}
                                                        placeholder="0.00"
                                                        value={line.discount_amount}
                                                        onChange={e => setLineField(i, 'discount_amount', e.target.value)}
                                                    />
                                                </div>

                                                {/* GST */}
                                                <div className="pt-1">
                                                    <select
                                                        className="w-full border rounded-lg px-1 py-2 text-sm focus:ring-2 focus:ring-blue-500 bg-white"
                                                        value={line.gst_rate}
                                                        onChange={e => updateLine(i, 'gst_rate', Number(e.target.value))}
                                                    >
                                                        {GST_RATES.map(r => (
                                                            <option key={r.value} value={r.value}>{r.label}</option>
                                                        ))}
                                                    </select>
                                                </div>

                                                {/* Line Total */}
                                                <div className="text-sm text-gray-700 text-right pr-1 pt-3">
                                                    {lineTotal > 0 ? lineTotal.toFixed(2) : '—'}
                                                </div>

                                                {/* Remove */}
                                                <div className="flex justify-center pt-3">
                                                    <button
                                                        type="button"
                                                        onClick={() => removeLine(i)}
                                                        className="text-gray-400 hover:text-red-500"
                                                        title="Remove line"
                                                    >
                                                        <TrashIcon className="w-4 h-4" />
                                                    </button>
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
                            <div className="flex items-center gap-6">
                                <div className="flex items-center gap-2">
                                    <label className="text-sm font-medium text-gray-600">Total discount</label>
                                    <span className="text-sm text-gray-400">₹</span>
                                    <input
                                        type="number"
                                        min="0"
                                        step="0.01"
                                        className="no-spinner w-28 border rounded-lg px-2 py-1.5 text-sm text-right focus:ring-2 focus:ring-blue-500"
                                        placeholder="0.00"
                                        value={totalDiscount > 0 ? totalDiscount : ''}
                                        onChange={e => handleTotalDiscountChange(e.target.value)}
                                    />
                                </div>
                                <div className="text-sm font-semibold text-gray-700">
                                    Invoice Total: <span className="text-gray-900">{invoiceTotal.toFixed(2)}</span>
                                </div>
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
                                    disabled={updateInvoice.isPending}
                                    className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                                >
                                    {updateInvoice.isPending ? 'Saving…' : 'Save Changes'}
                                </button>
                            </div>
                        </div>
                    </form>
                )}
            </div>
        </div>
    )
}
