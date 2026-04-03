import { useState, useRef } from 'react'
import * as XLSX from 'xlsx'
import { useAuth } from '../../hooks/useAuth'
import { useParts, useRecordPurchase } from '../../hooks/useInventory'
import { useQueryClient } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase'
import {
    XMarkIcon,
    ArrowDownTrayIcon,
    ArrowUpTrayIcon,
    ExclamationTriangleIcon,
    CheckCircleIcon,
} from '@heroicons/react/24/outline'

// ─── Template ────────────────────────────────────────────────────────────────
const TEMPLATE_COLUMNS = [
    'invoice_number',
    'invoice_date',
    'supplier_name',
    'part_number',
    'part_name',
    'unit',
    'quantity',
    'unit_price',
    'notes',
]

const TEMPLATE_EXAMPLE = [
    ['INV-001', '2024-01-15', 'AutoParts Ltd', 'OIL-5W40', 'Engine Oil 5W40', 'L', 20, 85.00, 'Bulk purchase'],
    ['INV-001', '2024-01-15', 'AutoParts Ltd', 'FLT-OIL-01', 'Oil Filter', 'pcs', 10, 45.00, ''],
    ['INV-002', '2024-01-16', 'Brake Masters', 'BRK-PAD-R', 'Rear Brake Pads', 'set', 5, 320.00, ''],
]

function downloadTemplate() {
    const wb = XLSX.utils.book_new()
    const ws = XLSX.utils.aoa_to_sheet([TEMPLATE_COLUMNS, ...TEMPLATE_EXAMPLE])
    // Column widths
    ws['!cols'] = [16, 14, 20, 16, 24, 8, 10, 12, 24].map(w => ({ wch: w }))
    XLSX.utils.book_append_sheet(wb, ws, 'Inventory Upload')
    XLSX.writeFile(wb, 'nvs_inventory_upload_template.xlsx')
}

// ─── Parse file ───────────────────────────────────────────────────────────────
function parseFile(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader()
        reader.onload = (e) => {
            try {
                const wb = XLSX.read(e.target.result, { type: 'array', cellDates: true })
                const ws = wb.Sheets[wb.SheetNames[0]]
                const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' })
                resolve(rows)
            } catch (err) {
                reject(new Error('Could not parse file. Ensure it is a valid .xlsx or .csv file.'))
            }
        }
        reader.onerror = () => reject(new Error('Failed to read file.'))
        reader.readAsArrayBuffer(file)
    })
}

function rowsToRecords(rows) {
    if (rows.length < 2) return []
    const header = rows[0].map(h => String(h).trim().toLowerCase().replace(/\s+/g, '_'))
    return rows.slice(1).filter(r => r.some(c => c !== '')).map((row, idx) => {
        const rec = {}
        header.forEach((h, i) => { rec[h] = row[i] ?? '' })
        rec._rowIndex = idx + 2 // 1-based, skipping header
        return rec
    })
}

// ─── Validate & enrich ────────────────────────────────────────────────────────
function validateRecords(records, partsMap) {
    return records.map(rec => {
        const warnings = []
        const errors = []

        if (!rec.invoice_number) errors.push('Missing invoice_number')
        if (!rec.invoice_date) errors.push('Missing invoice_date')
        if (!rec.supplier_name) errors.push('Missing supplier_name')
        if (!rec.part_name && !rec.part_number) errors.push('Missing part_name or part_number')

        const qty = parseFloat(rec.quantity)
        if (!rec.quantity || isNaN(qty) || qty <= 0) errors.push('Invalid quantity')

        const price = parseFloat(rec.unit_price)
        if (rec.unit_price === '' || isNaN(price) || price < 0) errors.push('Invalid unit_price')

        // Normalise date
        let dateStr = ''
        if (rec.invoice_date instanceof Date) {
            dateStr = rec.invoice_date.toISOString().slice(0, 10)
        } else if (typeof rec.invoice_date === 'number') {
            // Excel serial date
            const d = XLSX.SSF.parse_date_code(rec.invoice_date)
            dateStr = `${d.y}-${String(d.m).padStart(2, '0')}-${String(d.d).padStart(2, '0')}`
        } else {
            dateStr = String(rec.invoice_date).trim()
        }

        // Match part
        const partKey = String(rec.part_number || '').trim().toLowerCase()
        const partNameKey = String(rec.part_name || '').trim().toLowerCase()
        let matchedPart = null

        if (partKey) {
            matchedPart = partsMap.byNumber[partKey] || null
        }
        if (!matchedPart && partNameKey) {
            matchedPart = partsMap.byName[partNameKey] || null
        }

        if (!matchedPart) {
            warnings.push('Part not found in catalog — will be created')
        }

        return {
            ...rec,
            _dateStr: dateStr,
            _matchedPart: matchedPart,
            _warnings: warnings,
            _errors: errors,
            _qty: isNaN(qty) ? null : qty,
            _price: isNaN(price) ? null : price,
        }
    })
}

// ─── Component ────────────────────────────────────────────────────────────────
const STEPS = { UPLOAD: 'upload', VALIDATE: 'validate', DONE: 'done' }

export default function BulkUploadModal({ onClose }) {
    const { userProfile } = useAuth()
    const { data: parts = [] } = useParts()
    const queryClient = useQueryClient()

    const [step, setStep] = useState(STEPS.UPLOAD)
    const [dragging, setDragging] = useState(false)
    const [parseError, setParseError] = useState(null)
    const [records, setRecords] = useState([]) // validated records
    const [editedRecords, setEditedRecords] = useState([]) // user-edited copy
    const [importing, setImporting] = useState(false)
    const [importError, setImportError] = useState(null)
    const [importedCount, setImportedCount] = useState(0)
    const fileRef = useRef()

    // Build lookup maps from parts
    const partsMap = {
        byNumber: Object.fromEntries(
            parts.filter(p => p.part_number).map(p => [p.part_number.toLowerCase(), p])
        ),
        byName: Object.fromEntries(parts.map(p => [p.name.toLowerCase(), p])),
    }

    async function processFile(file) {
        setParseError(null)
        try {
            const rows = await parseFile(file)
            const recs = rowsToRecords(rows)
            if (recs.length === 0) {
                setParseError('No data rows found. Ensure the file has at least one row below the header.')
                return
            }
            const validated = validateRecords(recs, partsMap)
            setRecords(validated)
            setEditedRecords(validated.map(r => ({ ...r })))
            setStep(STEPS.VALIDATE)
        } catch (err) {
            setParseError(err.message)
        }
    }

    function handleFileInput(e) {
        const file = e.target.files?.[0]
        if (file) processFile(file)
    }

    function handleDrop(e) {
        e.preventDefault()
        setDragging(false)
        const file = e.dataTransfer.files?.[0]
        if (file) processFile(file)
    }

    function updateRecord(rowIndex, field, value) {
        setEditedRecords(prev =>
            prev.map(r => {
                if (r._rowIndex !== rowIndex) return r
                const updated = { ...r, [field]: value }
                // Re-validate this row with updated data
                const revalidated = validateRecords([updated], partsMap)[0]
                return revalidated
            })
        )
    }

    const hasErrors = editedRecords.some(r => r._errors.length > 0)
    const hasWarnings = editedRecords.some(r => r._warnings.length > 0)

    async function handleImport() {
        if (hasErrors) return
        setImporting(true)
        setImportError(null)

        try {
            // Group rows by invoice_number + invoice_date + supplier_name
            const invoiceGroups = {}
            for (const rec of editedRecords) {
                const key = `${rec.invoice_number}||${rec._dateStr}||${rec.supplier_name}`
                if (!invoiceGroups[key]) {
                    invoiceGroups[key] = {
                        invoice_number: String(rec.invoice_number).trim(),
                        invoice_date: rec._dateStr,
                        supplier_name: String(rec.supplier_name).trim(),
                        notes: String(rec.notes || '').trim(),
                        created_by: userProfile.id,
                        lines: [],
                    }
                }
                invoiceGroups[key].lines.push(rec)
            }

            let totalItems = 0

            for (const group of Object.values(invoiceGroups)) {
                // For each line, resolve or create the part
                const lineItems = []
                for (const rec of group.lines) {
                    let part = rec._matchedPart
                    if (!part) {
                        // Create new part
                        const { data: newPart, error } = await supabase
                            .from('parts')
                            .insert([{
                                name: String(rec.part_name).trim(),
                                part_number: rec.part_number ? String(rec.part_number).trim() : null,
                                unit: rec.unit ? String(rec.unit).trim() : 'pcs',
                                quantity_in_stock: 0,
                            }])
                            .select()
                            .single()
                        if (error) throw new Error(`Failed to create part "${rec.part_name}": ${error.message}`)
                        part = newPart
                    }
                    lineItems.push({
                        part_id: part.id,
                        quantity: rec._qty,
                        unit_price: rec._price,
                    })
                }

                // Insert invoice header
                const { data: inv, error: invErr } = await supabase
                    .from('purchase_invoices')
                    .insert([{
                        invoice_number: group.invoice_number,
                        invoice_date: group.invoice_date,
                        supplier_name: group.supplier_name,
                        notes: group.notes || null,
                        total_amount: lineItems.reduce((s, l) => s + l.quantity * l.unit_price, 0),
                        created_by: group.created_by,
                    }])
                    .select()
                    .single()
                if (invErr) throw new Error(`Failed to insert invoice ${group.invoice_number}: ${invErr.message}`)

                // Insert line items
                const { error: itemsErr } = await supabase
                    .from('purchase_invoice_items')
                    .insert(lineItems.map(l => ({ ...l, invoice_id: inv.id })))
                if (itemsErr) throw new Error(`Failed to insert items for ${group.invoice_number}: ${itemsErr.message}`)

                totalItems += lineItems.length
            }

            queryClient.invalidateQueries({ queryKey: ['parts'] })
            queryClient.invalidateQueries({ queryKey: ['purchase_invoices'] })
            setImportedCount(totalItems)
            setStep(STEPS.DONE)
        } catch (err) {
            setImportError(err.message)
        } finally {
            setImporting(false)
        }
    }

    // ── RENDER ────────────────────────────────────────────────────────────────
    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-5xl max-h-[90vh] flex flex-col">

                {/* Header */}
                <div className="flex items-center justify-between px-6 py-4 border-b">
                    <div>
                        <h2 className="text-lg font-semibold text-gray-900">Bulk Upload Inventory</h2>
                        <p className="text-xs text-gray-500 mt-0.5">
                            {step === STEPS.UPLOAD && 'Upload an .xlsx or .csv file'}
                            {step === STEPS.VALIDATE && `${editedRecords.length} rows — review warnings before importing`}
                            {step === STEPS.DONE && 'Import complete'}
                        </p>
                    </div>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                <div className="flex-1 overflow-y-auto px-6 py-5">

                    {/* ── STEP: UPLOAD ── */}
                    {step === STEPS.UPLOAD && (
                        <div className="space-y-6">
                            {/* Download template */}
                            <div className="flex items-center justify-between bg-blue-50 border border-blue-100 rounded-lg px-4 py-3">
                                <div>
                                    <p className="text-sm font-medium text-blue-800">Download the template first</p>
                                    <p className="text-xs text-blue-600 mt-0.5">
                                        Fill in your data using the exact column headers. Multiple rows with the same invoice_number will be grouped as one invoice.
                                    </p>
                                </div>
                                <button
                                    onClick={downloadTemplate}
                                    className="flex items-center gap-2 px-3 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 whitespace-nowrap ml-4"
                                >
                                    <ArrowDownTrayIcon className="w-4 h-4" />
                                    Download Template
                                </button>
                            </div>

                            {/* Drop zone */}
                            <div
                                className={`border-2 border-dashed rounded-xl p-12 text-center cursor-pointer transition-colors ${
                                    dragging ? 'border-blue-500 bg-blue-50' : 'border-gray-300 hover:border-blue-400'
                                }`}
                                onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
                                onDragLeave={() => setDragging(false)}
                                onDrop={handleDrop}
                                onClick={() => fileRef.current?.click()}
                            >
                                <ArrowUpTrayIcon className="w-10 h-10 text-gray-400 mx-auto mb-3" />
                                <p className="text-sm font-medium text-gray-700">Drop your file here or click to browse</p>
                                <p className="text-xs text-gray-500 mt-1">Supports .xlsx and .csv</p>
                                <input
                                    ref={fileRef}
                                    type="file"
                                    accept=".xlsx,.xls,.csv"
                                    className="hidden"
                                    onChange={handleFileInput}
                                />
                            </div>

                            {parseError && (
                                <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{parseError}</p>
                            )}

                            {/* Column reference */}
                            <div>
                                <p className="text-xs font-medium text-gray-500 mb-2">Expected columns:</p>
                                <div className="flex flex-wrap gap-2">
                                    {TEMPLATE_COLUMNS.map(col => (
                                        <span key={col} className="text-xs bg-gray-100 text-gray-700 px-2 py-1 rounded font-mono">
                                            {col}
                                        </span>
                                    ))}
                                </div>
                            </div>
                        </div>
                    )}

                    {/* ── STEP: VALIDATE ── */}
                    {step === STEPS.VALIDATE && (
                        <div className="space-y-4">
                            {/* Summary badges */}
                            <div className="flex gap-3 flex-wrap">
                                <span className="text-xs px-2 py-1 bg-gray-100 rounded-full text-gray-600">
                                    {editedRecords.length} rows
                                </span>
                                {hasErrors && (
                                    <span className="text-xs px-2 py-1 bg-red-100 rounded-full text-red-700 flex items-center gap-1">
                                        <ExclamationTriangleIcon className="w-3 h-3" />
                                        {editedRecords.filter(r => r._errors.length > 0).length} rows with errors (must fix)
                                    </span>
                                )}
                                {hasWarnings && (
                                    <span className="text-xs px-2 py-1 bg-yellow-100 rounded-full text-yellow-700 flex items-center gap-1">
                                        <ExclamationTriangleIcon className="w-3 h-3" />
                                        {editedRecords.filter(r => r._warnings.length > 0).length} rows with warnings (new parts will be created)
                                    </span>
                                )}
                                {!hasErrors && !hasWarnings && (
                                    <span className="text-xs px-2 py-1 bg-green-100 rounded-full text-green-700 flex items-center gap-1">
                                        <CheckCircleIcon className="w-3 h-3" />
                                        All rows valid
                                    </span>
                                )}
                            </div>

                            {/* Table */}
                            <div className="overflow-x-auto border rounded-lg">
                                <table className="min-w-full text-xs">
                                    <thead className="bg-gray-50 text-gray-600 text-left">
                                        <tr>
                                            <th className="px-3 py-2 font-medium w-6">#</th>
                                            <th className="px-3 py-2 font-medium">Invoice #</th>
                                            <th className="px-3 py-2 font-medium">Date</th>
                                            <th className="px-3 py-2 font-medium">Supplier</th>
                                            <th className="px-3 py-2 font-medium">Part No.</th>
                                            <th className="px-3 py-2 font-medium">Part Name</th>
                                            <th className="px-3 py-2 font-medium">Unit</th>
                                            <th className="px-3 py-2 font-medium">Qty</th>
                                            <th className="px-3 py-2 font-medium">Unit Price</th>
                                            <th className="px-3 py-2 font-medium min-w-48">Status</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-100">
                                        {editedRecords.map((rec) => {
                                            const hasErr = rec._errors.length > 0
                                            const hasWarn = rec._warnings.length > 0
                                            const rowClass = hasErr
                                                ? 'bg-red-50'
                                                : hasWarn
                                                ? 'bg-yellow-50'
                                                : ''

                                            return (
                                                <tr key={rec._rowIndex} className={rowClass}>
                                                    <td className="px-3 py-1.5 text-gray-400">{rec._rowIndex}</td>
                                                    {/* Editable cells */}
                                                    {[
                                                        'invoice_number',
                                                        '_dateStr',
                                                        'supplier_name',
                                                        'part_number',
                                                        'part_name',
                                                        'unit',
                                                    ].map(field => (
                                                        <td key={field} className="px-1 py-1">
                                                            <input
                                                                type="text"
                                                                className={`w-full px-2 py-1 rounded border text-xs focus:outline-none focus:ring-1 focus:ring-blue-400 ${
                                                                    hasErr ? 'border-red-300 bg-red-50' : 'border-gray-200'
                                                                }`}
                                                                value={field === '_dateStr' ? rec._dateStr : (rec[field] ?? '')}
                                                                onChange={e => updateRecord(
                                                                    rec._rowIndex,
                                                                    field === '_dateStr' ? 'invoice_date' : field,
                                                                    e.target.value
                                                                )}
                                                            />
                                                        </td>
                                                    ))}
                                                    <td className="px-1 py-1">
                                                        <input
                                                            type="number"
                                                            min="0.01"
                                                            step="0.01"
                                                            className={`w-20 px-2 py-1 rounded border text-xs focus:outline-none focus:ring-1 focus:ring-blue-400 ${
                                                                hasErr ? 'border-red-300 bg-red-50' : 'border-gray-200'
                                                            }`}
                                                            value={rec.quantity ?? ''}
                                                            onChange={e => updateRecord(rec._rowIndex, 'quantity', e.target.value)}
                                                        />
                                                    </td>
                                                    <td className="px-1 py-1">
                                                        <input
                                                            type="number"
                                                            min="0"
                                                            step="0.01"
                                                            className={`w-24 px-2 py-1 rounded border text-xs focus:outline-none focus:ring-1 focus:ring-blue-400 ${
                                                                hasErr ? 'border-red-300 bg-red-50' : 'border-gray-200'
                                                            }`}
                                                            value={rec.unit_price ?? ''}
                                                            onChange={e => updateRecord(rec._rowIndex, 'unit_price', e.target.value)}
                                                        />
                                                    </td>
                                                    <td className="px-3 py-1.5">
                                                        {hasErr ? (
                                                            <div className="text-red-600 space-y-0.5">
                                                                {rec._errors.map((e, i) => (
                                                                    <div key={i} className="flex items-start gap-1">
                                                                        <ExclamationTriangleIcon className="w-3 h-3 mt-0.5 shrink-0" />
                                                                        {e}
                                                                    </div>
                                                                ))}
                                                            </div>
                                                        ) : hasWarn ? (
                                                            <div className="text-yellow-700 space-y-0.5">
                                                                {rec._warnings.map((w, i) => (
                                                                    <div key={i} className="flex items-start gap-1">
                                                                        <ExclamationTriangleIcon className="w-3 h-3 mt-0.5 shrink-0" />
                                                                        {w}
                                                                    </div>
                                                                ))}
                                                            </div>
                                                        ) : (
                                                            <span className="text-green-600 flex items-center gap-1">
                                                                <CheckCircleIcon className="w-3 h-3" /> OK
                                                                {rec._matchedPart && (
                                                                    <span className="text-gray-400 ml-1">({rec._matchedPart.name})</span>
                                                                )}
                                                            </span>
                                                        )}
                                                    </td>
                                                </tr>
                                            )
                                        })}
                                    </tbody>
                                </table>
                            </div>

                            {importError && (
                                <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{importError}</p>
                            )}
                        </div>
                    )}

                    {/* ── STEP: DONE ── */}
                    {step === STEPS.DONE && (
                        <div className="flex flex-col items-center justify-center py-16 text-center">
                            <CheckCircleIcon className="w-14 h-14 text-green-500 mb-4" />
                            <h3 className="text-lg font-semibold text-gray-900">Import Successful</h3>
                            <p className="text-sm text-gray-500 mt-1">
                                {importedCount} line item{importedCount !== 1 ? 's' : ''} recorded and inventory updated.
                            </p>
                        </div>
                    )}
                </div>

                {/* Footer */}
                <div className="px-6 py-4 border-t bg-gray-50 rounded-b-xl flex justify-between items-center">
                    <div>
                        {step === STEPS.VALIDATE && (
                            <button
                                type="button"
                                onClick={() => setStep(STEPS.UPLOAD)}
                                className="text-sm text-gray-600 hover:text-gray-900"
                            >
                                ← Back
                            </button>
                        )}
                    </div>
                    <div className="flex gap-3">
                        <button
                            type="button"
                            onClick={onClose}
                            className="px-4 py-2 text-sm text-gray-700 border rounded-lg hover:bg-gray-100"
                        >
                            {step === STEPS.DONE ? 'Close' : 'Cancel'}
                        </button>
                        {step === STEPS.VALIDATE && (
                            <button
                                type="button"
                                onClick={handleImport}
                                disabled={hasErrors || importing}
                                className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                            >
                                {importing ? 'Importing…' : `Import ${editedRecords.length} rows`}
                            </button>
                        )}
                    </div>
                </div>
            </div>
        </div>
    )
}
