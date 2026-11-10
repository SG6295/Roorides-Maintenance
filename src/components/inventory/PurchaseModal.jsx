import { useState } from 'react'
import { useAuth } from '../../hooks/useAuth'
import { useParts, useRecordPurchase } from '../../hooks/useInventory'
import { useWorkshopLocations } from '../../hooks/useWorkshopLocations'
import { PlusIcon, TrashIcon, XMarkIcon } from '@heroicons/react/24/outline'
import CustomSelect from '../shared/CustomSelect'
import SearchableSelect from '../shared/SearchableSelect'
import MultiFileAttach from '../shared/MultiFileAttach'
import NewPartInlineForm from './NewPartInlineForm'
import SupplierPicker from '../suppliers/SupplierPicker'
import InvoiceDetailsFields from '../outsource-invoices/InvoiceDetailsFields'
import { EMPTY_INVOICE_FORM, invoiceFormToRow, validateInvoiceForm } from '../outsource-invoices/invoiceForm'
import { approvedAmountError } from '../../utils/refurbishment'
import { todayLocal } from '../../utils/datetime'
import {
    lineSubtotal,
    lineDiscount,
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
const emptyLine = () => ({ part_id: '', quantity: '', unit_price: '', gst_rate: 0, discount_amount: '', discount_pct: '', discount_mode: 'amount' })

export default function PurchaseModal({ onClose }) {
    const { userProfile } = useAuth()
    const { data: parts = [] } = useParts()
    const { data: locations = [] } = useWorkshopLocations()
    const recordPurchase = useRecordPurchase()
    const todayStr = todayLocal()

    // keyed by line index: true while that line is showing the new-part form
    const [newPartForms, setNewPartForms] = useState({})

    const [invoice, setInvoice] = useState({
        supplier_id: '',
        notes: '',
        location_id: '',
    })
    // The finance details, as on a job card or refurbishment (MAIN-129); the date and
    // number are the purchase invoice's own.
    const [invoiceForm, setInvoiceForm] = useState(EMPTY_INVOICE_FORM)
    const [showErrors, setShowErrors] = useState(false)
    const [lines, setLines] = useState([emptyLine()])
    const [error, setError] = useState(null)

    // Invoice file attachment — { name, url } once uploaded
    const [invoiceFile, setInvoiceFile] = useState(null)

    const invoiceTotal = calcInvoiceTotal(lines)
    const totalDiscount = calcTotalDiscount(lines)
    const invoiceErrors = validateInvoiceForm(invoiceForm, todayStr)
    const amountProblem = approvedAmountError(lines, invoiceForm.approvedAmount)

    // With a single workshop there is nothing to choose, so pick it for them.
    const locationId = invoice.location_id || (locations.length === 1 ? locations[0].id : '')

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

    function handlePartSelect(index, value) {
        if (value === NEW_PART_SENTINEL) {
            setNewPartForms(prev => ({ ...prev, [index]: true }))
            updateLine(index, 'part_id', '')
        } else {
            setNewPartForms(prev => { const n = { ...prev }; delete n[index]; return n })
            updateLine(index, 'part_id', value)
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
        setShowErrors(true)

        if (!invoice.supplier_id) {
            setError('Choose the supplier, or add them.')
            return
        }
        if (!locationId) {
            setError('Choose which workshop this invoice is being inwarded to.')
            return
        }

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
        // '0' is truthy, so the check above lets a zero quantity through
        if (validLines.some(l => parseFloat(l.quantity) <= 0)) {
            setError('Quantity must be greater than zero.')
            return
        }
        if (validLines.some(l => (parseFloat(l.discount_amount) || 0) > lineSubtotal(l) + 1e-9)) {
            setError('A line discount cannot exceed its item subtotal (qty × unit price).')
            return
        }
        if (Object.keys(invoiceErrors).length > 0) {
            setError('Check the invoice details.')
            return
        }
        if (amountProblem) {
            setError(amountProblem)
            return
        }

        const { invoice_no, date_of_activity, ...finance } = invoiceFormToRow(invoiceForm)
        try {
            await recordPurchase.mutateAsync({
                invoice: {
                    ...invoice,
                    invoice_number: invoice_no,
                    invoice_date: date_of_activity,
                    location_id: locationId,
                    total_amount: invoiceTotal,
                    created_by: userProfile.id,
                    ...(invoiceFile?.url ? { invoice_file_url: invoiceFile.url } : {}),
                },
                finance,
                lineItems: validLines.map(l => ({
                    part_id: l.part_id,
                    quantity: parseFloat(l.quantity),
                    unit_price: parseFloat(l.unit_price),
                    gst_rate: parseFloat(l.gst_rate) || 0,
                    discount_amount: lineDiscount(l),
                })),
            })
            onClose()
        } catch (err) {
            setError(err.message)
        }
    }

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-5xl max-h-[90vh] flex flex-col">
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
                                        Supplier <span className="text-red-500">*</span>
                                    </label>
                                    <SupplierPicker
                                        value={invoice.supplier_id}
                                        onChange={id => setInvoice(p => ({ ...p, supplier_id: id }))}
                                        error={showErrors && !invoice.supplier_id ? { message: 'Required' } : null}
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
                                <div className="sm:col-span-2">
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Inward to Workshop <span className="text-red-500">*</span>
                                    </label>
                                    <CustomSelect
                                        value={locationId}
                                        onChange={v => setInvoice(p => ({ ...p, location_id: v }))}
                                        options={locations.map(l => ({
                                            value: l.id,
                                            label: l.address ? `${l.name} — ${l.address}` : l.name,
                                        }))}
                                        placeholder="Select workshop"
                                        compact
                                    />
                                    <p className="text-xs text-gray-400 mt-1">
                                        Every line on this invoice is received into this workshop's stock.
                                    </p>
                                </div>
                            </div>
                        </div>

                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">Invoice Details for Finance</h3>
                            <InvoiceDetailsFields
                                form={invoiceForm}
                                setForm={setInvoiceForm}
                                errors={invoiceErrors}
                                showErrors={showErrors}
                                todayStr={todayStr}
                                dateLabel="Invoice Date"
                            />
                            <p className="text-xs text-gray-400 mt-2">
                                Goes to finance in Outsource Invoices as soon as it is saved. The lines must add up to the Approved Amount.
                            </p>
                        </div>

                        {/* Invoice File Attachment */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">Invoice Document</h3>
                            <MultiFileAttach value={invoiceFile} onChange={setInvoiceFile} />
                            {!invoiceFile?.url && (
                                <p className="text-xs text-amber-700 mt-1">
                                    Without the file, finance sees this invoice as New (invoice pending) and cannot accept it until the file is uploaded from Edit Purchase.
                                </p>
                            )}
                        </div>

                        {/* Line Items */}
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">Line Items</h3>
                            <div className="space-y-2">
                                {/* Column headers */}
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
                                    const npf = newPartForms[i]
                                    const selectedPart = parts.find(p => p.id === line.part_id)
                                    const discountInvalid = (parseFloat(line.discount_amount) || 0) > sub + 1e-9
                                    return (
                                        <div key={i} className={`${LINE_GRID} items-start`}>
                                            <div>
                                                {npf ? (
                                                    /* ── Inline new-part form ── */
                                                    <NewPartInlineForm
                                                        onCreated={part => {
                                                            updateLine(i, 'part_id', part.id)
                                                            cancelNewPart(i)
                                                        }}
                                                        onCancel={() => cancelNewPart(i)}
                                                    />
                                                ) : (
                                                    /* ── Part dropdown ── */
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
                                            <div className="pt-1">
                                                <div className="relative">
                                                    <input
                                                        type="number"
                                                        min="0"
                                                        step="any"
                                                        className={`w-full border rounded-lg px-2 py-2 text-sm focus:ring-2 focus:ring-blue-500 ${selectedPart ? 'pr-7' : ''}`}
                                                        placeholder="0"
                                                        value={line.quantity}
                                                        onChange={e => setLineField(i, 'quantity', e.target.value)}
                                                    />
                                                    {selectedPart && (
                                                        <span className="absolute right-1.5 top-1/2 -translate-y-1/2 text-[10px] text-gray-400 pointer-events-none">
                                                            {selectedPart.unit}
                                                        </span>
                                                    )}
                                                </div>
                                            </div>
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
                                            <div className="text-sm text-gray-700 text-right pr-1 pt-3">
                                                {lineTotal > 0 ? lineTotal.toFixed(2) : '—'}
                                            </div>
                                            <div className="flex justify-center pt-3">
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
                            <div className="text-sm">
                                <span className="font-semibold text-gray-700">
                                    Invoice Total: <span className="text-gray-900">{invoiceTotal.toFixed(2)}</span>
                                </span>
                                {amountProblem && (
                                    <p className="text-xs text-red-600 mt-0.5">{amountProblem}</p>
                                )}
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
