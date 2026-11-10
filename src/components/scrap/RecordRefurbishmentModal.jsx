import { useMemo, useRef, useState } from 'react'
import { PlusIcon, TrashIcon, XMarkIcon } from '@heroicons/react/24/outline'
import CustomSelect from '../shared/CustomSelect'
import SearchableSelect from '../shared/SearchableSelect'
import MultiFileAttach from '../shared/MultiFileAttach'
import NewPartInlineForm from '../inventory/NewPartInlineForm'
import QuickAddSupplierModal from '../suppliers/QuickAddSupplierModal'
import InvoiceDetailsFields from '../outsource-invoices/InvoiceDetailsFields'
import { EMPTY_INVOICE_FORM, invoiceFormToRow, validateInvoiceForm } from '../outsource-invoices/invoiceForm'
import { useParts } from '../../hooks/useInventory'
import { useApprovedSuppliers } from '../../hooks/useSuppliers'
import { useWorkshopLocations } from '../../hooks/useWorkshopLocations'
import { useScrapInventory, useRecordRefurbishment, scrapSourceLabel } from '../../hooks/useScrap'
import { lineTotal, invoiceTotal } from '../../lib/invoiceDiscount'
import { todayLocal } from '../../utils/datetime'
import {
    approvedAmountError,
    refurbishedName,
    refurbishmentLinesError,
    toRefurbishmentLine,
} from '../../utils/refurbishment'

const NOT_FOUND_SENTINEL = '__NOT_FOUND__'
const NEW_PART_SENTINEL = '__NEW__'
const QUICK_ADD_SENTINEL = '__QUICK_ADD__'
const GST_OPTIONS = [
    { label: 'None', value: '0' },
    { label: '5%', value: '5' },
    { label: '12%', value: '12' },
    { label: '18%', value: '18' },
    { label: '28%', value: '28' },
]
const LINE_GRID = 'grid gap-2 grid-cols-[minmax(0,5fr)_minmax(0,1.5fr)_minmax(0,2fr)_minmax(0,1.5fr)_minmax(0,1.5fr)_1.25rem]'

const fmt = n => {
    const v = Number(n ?? 0)
    return Number.isInteger(v) ? String(v) : v.toFixed(2)
}

const emptyLine = key => ({
    key,
    notFound: false,
    scrap_id: '',
    original_part_id: '',
    creatingPart: false,
    quantity: '',
    unit_price: '',
    gst_rate: '0',
    comment: '',
})

export default function RecordRefurbishmentModal({ onClose }) {
    const { data: parts = [] } = useParts()
    const { data: suppliers = [] } = useApprovedSuppliers()
    const { data: locations = [] } = useWorkshopLocations()
    const record = useRecordRefurbishment()
    const todayStr = todayLocal()

    const nextKey = useRef(1)
    const [invoice, setInvoice] = useState({
        supplier_id: '',
        notes: '',
        location_id: '',
    })
    // The finance details, as on a job card or multi-vehicle invoice; the date and
    // number are the purchase invoice's own.
    const [invoiceForm, setInvoiceForm] = useState(EMPTY_INVOICE_FORM)
    const [showErrors, setShowErrors] = useState(false)
    // The name typed before choosing "+ Add supplier", or null while Quick Add is closed.
    const [quickAddName, setQuickAddName] = useState(null)
    const [invoiceFile, setInvoiceFile] = useState(null)
    const [lines, setLines] = useState([emptyLine(0)])
    const [error, setError] = useState(null)

    const invoiceErrors = validateInvoiceForm(invoiceForm, todayStr)
    const amountProblem = approvedAmountError(lines, invoiceForm.approvedAmount)

    // With a single workshop there is nothing to choose, so pick it for them.
    const locationId = invoice.location_id || (locations.length === 1 ? locations[0].id : '')

    const { data: scrapItems = [] } = useScrapInventory({ status: 'in_storage', location_id: locationId })
    const scrapById = useMemo(
        () => (locationId ? Object.fromEntries(scrapItems.map(s => [s.id, s])) : {}),
        [scrapItems, locationId]
    )

    const updateLine = (key, patch) => {
        setError(null)
        setLines(prev => prev.map(l => (l.key === key ? { ...l, ...patch } : l)))
    }

    function chooseWorkshop(id) {
        setInvoice(p => ({ ...p, location_id: id }))
        // Scrap items belong to one workshop, so earlier picks no longer apply.
        setLines(prev => prev.map(l => ({ ...l, scrap_id: '', quantity: l.notFound ? l.quantity : '' })))
    }

    function chooseScrap(line, value) {
        if (value === NOT_FOUND_SENTINEL) {
            updateLine(line.key, { notFound: true, scrap_id: '', quantity: '' })
        } else {
            updateLine(line.key, { scrap_id: value, quantity: '' })
        }
    }

    function choosePart(line, value) {
        if (value === NEW_PART_SENTINEL) {
            updateLine(line.key, { creatingPart: true, original_part_id: '' })
        } else {
            updateLine(line.key, { original_part_id: value })
        }
    }

    function chooseSupplier(value, typed) {
        if (value === QUICK_ADD_SENTINEL) {
            setQuickAddName(typed ?? '')
        } else {
            setInvoice(p => ({ ...p, supplier_id: value }))
        }
    }

    function addLine() {
        const key = nextKey.current++
        setLines(prev => [...prev, emptyLine(key)])
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
            setError('Choose which workshop these parts are being inwarded to.')
            return
        }
        if (!invoiceFile?.url) {
            setError('Attach the invoice file.')
            return
        }
        if (Object.keys(invoiceErrors).length > 0) {
            setError('Check the invoice details.')
            return
        }
        const problem = refurbishmentLinesError(lines, scrapById) || amountProblem
        if (problem) {
            setError(problem)
            return
        }

        const { invoice_no, date_of_activity, ...details } = invoiceFormToRow(invoiceForm)
        try {
            await record.mutateAsync({
                invoice: {
                    ...invoice,
                    ...details,
                    invoice_number: invoice_no,
                    invoice_date: date_of_activity,
                    location_id: locationId,
                    invoice_file_url: invoiceFile.url,
                },
                lines: lines.map(toRefurbishmentLine),
            })
            onClose()
        } catch (err) {
            setError(err.message)
        }
    }

    const partOptions = parts.map(p => ({
        value: p.id,
        label: `${p.name}${p.part_number ? ` (${p.part_number})` : ''} · ${p.unit}`,
    }))

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-5xl max-h-[90vh] flex flex-col">
                <div className="flex items-center justify-between px-6 py-4 border-b">
                    <h2 className="text-lg font-semibold text-gray-900">Record Refurbishment</h2>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                <form onSubmit={handleSubmit} className="flex flex-col flex-1 overflow-hidden">
                    <div className="overflow-y-auto flex-1 px-6 py-4 space-y-6">
                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">Refurbishment Invoice</h3>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                                <div>
                                    <label className="block text-xs font-medium text-gray-600 mb-1">
                                        Supplier <span className="text-red-500">*</span>
                                    </label>
                                    <SearchableSelect
                                        value={invoice.supplier_id}
                                        onChange={chooseSupplier}
                                        options={suppliers.map(sp => ({ value: sp.id, label: sp.entity_name }))}
                                        placeholder="Search suppliers…"
                                        showAllOnFocus={true}
                                        pinnedOption={{ value: QUICK_ADD_SENTINEL, label: '+ Add supplier…' }}
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
                                        Workshop <span className="text-red-500">*</span>
                                    </label>
                                    <CustomSelect
                                        value={locationId}
                                        onChange={chooseWorkshop}
                                        options={locations.map(l => ({
                                            value: l.id,
                                            label: l.address ? `${l.name} — ${l.address}` : l.name,
                                        }))}
                                        placeholder="Select workshop"
                                        compact
                                    />
                                    <p className="text-xs text-gray-400 mt-1">
                                        The scrap list shows this workshop's items, and the refurbished parts are received into its stock.
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
                                Goes to finance in Outsource Invoices as soon as it is saved. The parts must add up to the Approved Amount.
                            </p>
                        </div>

                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">
                                Invoice Document <span className="text-red-500">*</span>
                            </h3>
                            <MultiFileAttach value={invoiceFile} onChange={setInvoiceFile} />
                            {showErrors && !invoiceFile?.url && (
                                <p className="text-xs text-red-600 mt-1">Required</p>
                            )}
                        </div>

                        <div>
                            <h3 className="text-sm font-semibold text-gray-700 mb-3">Refurbished Parts</h3>
                            <div className="space-y-3">
                                <div className={`${LINE_GRID} px-1 text-xs font-medium text-gray-500`}>
                                    <div>Scrap item</div>
                                    <div>Qty</div>
                                    <div>Unit Price</div>
                                    <div>GST</div>
                                    <div className="text-right">Line Total</div>
                                    <div></div>
                                </div>

                                {lines.map(line => {
                                    const scrap = scrapById[line.scrap_id]
                                    const originalPart = parts.find(p => p.id === line.original_part_id)
                                    const unit = scrap?.unit_snapshot ?? originalPart?.unit
                                    const sourceName = scrap?.part_name_snapshot ?? originalPart?.name
                                    const available = scrap ? Number(scrap.quantity_snapshot) : null
                                    const quantity = Number(line.quantity)
                                    const tooMuch = available !== null && quantity > available
                                    const total = lineTotal(line)

                                    const takenElsewhere = new Set(
                                        lines.filter(l => l.key !== line.key).map(l => l.scrap_id).filter(Boolean)
                                    )
                                    const scrapOptions = scrapItems
                                        .filter(s => !takenElsewhere.has(s.id))
                                        .map(s => ({
                                            value: s.id,
                                            label: `${s.part_name_snapshot}${s.part_number_snapshot ? ` (${s.part_number_snapshot})` : ''} · ${fmt(s.quantity_snapshot)} ${s.unit_snapshot} · ${scrapSourceLabel(s)}`,
                                            searchText: s.source_vehicle_number,
                                        }))

                                    return (
                                        <div key={line.key} className="space-y-2">
                                            <div className={`${LINE_GRID} items-start`}>
                                                <div>
                                                    {line.notFound ? (
                                                        <div className="border border-amber-200 bg-amber-50 rounded-lg px-3 py-2 text-sm text-amber-800 flex items-center justify-between gap-2">
                                                            <span>Not in the scrap list</span>
                                                            <button
                                                                type="button"
                                                                onClick={() => updateLine(line.key, { notFound: false, original_part_id: '', creatingPart: false, comment: '', quantity: '' })}
                                                                className="text-xs text-blue-600 hover:text-blue-800 shrink-0"
                                                            >
                                                                Pick from list
                                                            </button>
                                                        </div>
                                                    ) : (
                                                        <SearchableSelect
                                                            value={line.scrap_id}
                                                            onChange={val => chooseScrap(line, val)}
                                                            options={scrapOptions}
                                                            placeholder={locationId ? 'Search scrap items…' : 'Choose a workshop first'}
                                                            showAllOnFocus={true}
                                                            disabled={!locationId}
                                                            pinnedOption={{ value: NOT_FOUND_SENTINEL, label: "Couldn't find it in the list" }}
                                                        />
                                                    )}
                                                </div>
                                                <div className="pt-1">
                                                    <div className="relative">
                                                        <input
                                                            type="number"
                                                            min="0"
                                                            step="any"
                                                            aria-label="Quantity"
                                                            className={`w-full border rounded-lg px-2 py-2 text-sm focus:ring-2 ${unit ? 'pr-7' : ''} ${tooMuch ? 'border-red-400 focus:ring-red-500' : 'focus:ring-blue-500'}`}
                                                            placeholder="0"
                                                            value={line.quantity}
                                                            onChange={e => updateLine(line.key, { quantity: e.target.value })}
                                                        />
                                                        {unit && (
                                                            <span className="absolute right-1.5 top-1/2 -translate-y-1/2 text-[10px] text-gray-400 pointer-events-none">
                                                                {unit}
                                                            </span>
                                                        )}
                                                    </div>
                                                </div>
                                                <div className="pt-1">
                                                    <input
                                                        type="number"
                                                        min="0"
                                                        step="0.01"
                                                        aria-label="Unit price"
                                                        className="no-spinner w-full border rounded-lg px-2 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                                                        placeholder="0.00"
                                                        value={line.unit_price}
                                                        onChange={e => updateLine(line.key, { unit_price: e.target.value })}
                                                    />
                                                </div>
                                                <div className="pt-1">
                                                    <CustomSelect
                                                        compact
                                                        value={line.gst_rate}
                                                        onChange={v => updateLine(line.key, { gst_rate: v })}
                                                        options={GST_OPTIONS}
                                                    />
                                                </div>
                                                <div className="text-sm text-gray-700 text-right pr-1 pt-3">
                                                    {total > 0 ? total.toFixed(2) : '—'}
                                                </div>
                                                <div className="flex justify-center pt-3">
                                                    {lines.length > 1 && (
                                                        <button
                                                            type="button"
                                                            onClick={() => setLines(prev => prev.filter(l => l.key !== line.key))}
                                                            aria-label="Remove line"
                                                            className="text-gray-400 hover:text-red-500"
                                                        >
                                                            <TrashIcon className="w-4 h-4" />
                                                        </button>
                                                    )}
                                                </div>
                                            </div>

                                            {line.notFound && (
                                                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                                                    <div>
                                                        {line.creatingPart ? (
                                                            <NewPartInlineForm
                                                                onCreated={part => updateLine(line.key, { creatingPart: false, original_part_id: part.id })}
                                                                onCancel={() => updateLine(line.key, { creatingPart: false })}
                                                            />
                                                        ) : (
                                                            <SearchableSelect
                                                                value={line.original_part_id}
                                                                onChange={val => choosePart(line, val)}
                                                                options={partOptions}
                                                                placeholder="Original part…"
                                                                showAllOnFocus={true}
                                                                pinnedOption={{ value: NEW_PART_SENTINEL, label: '+ Create new part…' }}
                                                            />
                                                        )}
                                                    </div>
                                                    <input
                                                        type="text"
                                                        aria-label="Comment"
                                                        placeholder="Comment (required)"
                                                        className="w-full border rounded-lg px-3 py-2 text-sm self-start focus:ring-2 focus:ring-blue-500"
                                                        value={line.comment}
                                                        onChange={e => updateLine(line.key, { comment: e.target.value })}
                                                    />
                                                </div>
                                            )}

                                            {sourceName && (
                                                <p className={`text-xs ${tooMuch ? 'text-red-600' : 'text-gray-400'}`}>
                                                    {tooMuch
                                                        ? `Only ${fmt(available)} ${unit} in scrap.`
                                                        : <>
                                                            Goes into stock as <span className="font-medium text-gray-600">{refurbishedName(sourceName)}</span>.
                                                            {available !== null && (quantity > 0
                                                                ? ` ${fmt(available - quantity)} ${unit} stays in scrap.`
                                                                : ` ${fmt(available)} ${unit} in scrap.`)}
                                                        </>}
                                                </p>
                                            )}
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
                                Add another part
                            </button>
                        </div>

                        {error && (
                            <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{error}</p>
                        )}
                    </div>

                    <div className="px-6 py-4 border-t flex items-center justify-between bg-gray-50 rounded-b-xl">
                        <div className="text-sm">
                            <span className="font-semibold text-gray-700">
                                Parts Total: <span className="text-gray-900">{invoiceTotal(lines).toFixed(2)}</span>
                            </span>
                            {amountProblem && (
                                <p className="text-xs text-red-600 mt-0.5">{amountProblem}</p>
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
                                disabled={record.isPending}
                                className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                            >
                                {record.isPending ? 'Saving…' : 'Record Refurbishment'}
                            </button>
                        </div>
                    </div>
                </form>
            </div>

            {quickAddName !== null && (
                <QuickAddSupplierModal
                    isOpen
                    initialName={quickAddName}
                    onClose={() => setQuickAddName(null)}
                    onSuccess={supplier => setInvoice(p => ({ ...p, supplier_id: supplier.id }))}
                />
            )}
        </div>
    )
}
