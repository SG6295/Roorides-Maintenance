import { useState, useRef } from 'react'
import {
    XMarkIcon,
    ArrowUpTrayIcon,
    ExclamationTriangleIcon,
    CheckCircleIcon,
} from '@heroicons/react/24/outline'
import { parseCountSheet, validateCountSheet } from '../../../utils/auditSheet'
import { useSubmitStockAuditCounts } from '../../../hooks/useStockAudits'

const STEPS = { UPLOAD: 'upload', VALIDATE: 'validate' }

/**
 * Upload the filled count sheet.
 *
 * Everything is checked here before anything is sent, because the failure the user cares
 * about is "row 47 says 'twelve'", not "the request failed". The same rules are enforced
 * again in submit_stock_audit_counts() — this pass exists to point at the row.
 *
 * @param {object} props
 * @param {object} props.audit  the open audit
 * @param {Array}  props.items  its stock_audit_items
 * @param {Array}  props.parts  the parts catalogue, for resolving found rows
 * @param {Function} props.onClose
 */
export default function UploadCountSheetModal({ audit, items, parts, onClose }) {
    const submitCounts = useSubmitStockAuditCounts()

    const [step, setStep] = useState(STEPS.UPLOAD)
    const [dragging, setDragging] = useState(false)
    const [parseError, setParseError] = useState(null)
    const [result, setResult] = useState(null)
    const [submitError, setSubmitError] = useState(null)
    const fileRef = useRef()

    async function processFile(file) {
        setParseError(null)
        try {
            const rows = await parseCountSheet(file)
            setResult(validateCountSheet(rows, { audit, items, parts }))
            setStep(STEPS.VALIDATE)
        } catch (err) {
            setParseError(err.message)
        }
    }

    function handleDrop(e) {
        e.preventDefault()
        setDragging(false)
        const file = e.dataTransfer.files?.[0]
        if (file) processFile(file)
    }

    const rowErrors = result?.records.filter(r => r._errors.length > 0) ?? []
    const foundRows = result?.records.filter(r => r._isFound && r._errors.length === 0) ?? []
    const mismatches = result?.records.filter(r => r._errors.length === 0 && r._variance !== 0) ?? []
    const blocked = !result || result.fatal.length > 0 || rowErrors.length > 0

    async function handleSubmit() {
        if (blocked) return
        setSubmitError(null)
        try {
            await submitCounts.mutateAsync({ auditId: audit.id, counts: result.counts })
            onClose()
        } catch (err) {
            setSubmitError(err.message)
        }
    }

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-5xl max-h-[90vh] flex flex-col">

                <div className="flex items-center justify-between px-6 py-4 border-b flex-shrink-0">
                    <div>
                        <h2 className="text-lg font-semibold text-gray-900">Upload Count Sheet</h2>
                        <p className="text-xs text-gray-500 mt-0.5">
                            {step === STEPS.UPLOAD
                                ? `${audit.location?.name} — ${items.length} part${items.length === 1 ? '' : 's'} to count`
                                : `${result?.records.length ?? 0} rows read`}
                        </p>
                    </div>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                <div className="flex-1 overflow-y-auto px-6 py-5">

                    {step === STEPS.UPLOAD && (
                        <div className="space-y-5">
                            <div
                                className={`border-2 border-dashed rounded-xl p-12 text-center cursor-pointer transition-colors ${
                                    dragging ? 'border-blue-500 bg-blue-50' : 'border-gray-300 hover:border-blue-400'
                                }`}
                                onDragOver={e => { e.preventDefault(); setDragging(true) }}
                                onDragLeave={() => setDragging(false)}
                                onDrop={handleDrop}
                                onClick={() => fileRef.current?.click()}
                            >
                                <ArrowUpTrayIcon className="w-10 h-10 text-gray-400 mx-auto mb-3" />
                                <p className="text-sm font-medium text-gray-700">
                                    Drop the filled count sheet here, or click to browse
                                </p>
                                <p className="text-xs text-gray-500 mt-1">
                                    The .xlsx downloaded for this audit — .csv works too
                                </p>
                                <input
                                    ref={fileRef}
                                    type="file"
                                    accept=".xlsx,.xls,.csv"
                                    className="hidden"
                                    onChange={e => {
                                        const file = e.target.files?.[0]
                                        if (file) processFile(file)
                                    }}
                                />
                            </div>

                            {parseError && (
                                <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{parseError}</p>
                            )}

                            <div className="text-xs text-gray-500 space-y-1">
                                <p>Every printed row needs a number in <span className="font-mono">counted_qty</span> — a blank row is rejected rather than treated as zero.</p>
                                <p>Anything found on the shelf but not listed goes on the blank rows at the foot of the sheet: write the part number and the quantity.</p>
                            </div>
                        </div>
                    )}

                    {step === STEPS.VALIDATE && result && (
                        <div className="space-y-4">
                            <div className="flex gap-2 flex-wrap">
                                <span className="text-xs px-2 py-1 bg-gray-100 rounded-full text-gray-600">
                                    {result.records.length} rows
                                </span>
                                {rowErrors.length > 0 && (
                                    <span className="text-xs px-2 py-1 bg-red-100 rounded-full text-red-700 flex items-center gap-1">
                                        <ExclamationTriangleIcon className="w-3 h-3" />
                                        {rowErrors.length} to fix
                                    </span>
                                )}
                                {foundRows.length > 0 && (
                                    <span className="text-xs px-2 py-1 bg-blue-100 rounded-full text-blue-700">
                                        {foundRows.length} found on shelf
                                    </span>
                                )}
                                {!blocked && (
                                    <>
                                        <span className="text-xs px-2 py-1 bg-yellow-100 rounded-full text-yellow-700">
                                            {mismatches.length} mismatch{mismatches.length === 1 ? '' : 'es'}
                                        </span>
                                        <span className="text-xs px-2 py-1 bg-green-100 rounded-full text-green-700 flex items-center gap-1">
                                            <CheckCircleIcon className="w-3 h-3" />
                                            Ready to upload
                                        </span>
                                    </>
                                )}
                            </div>

                            {result.fatal.map((msg, i) => (
                                <p key={i} className="text-sm text-red-700 bg-red-50 border border-red-200 px-3 py-2 rounded-lg">
                                    {msg}
                                </p>
                            ))}

                            <div className="overflow-x-auto border rounded-lg max-h-[45vh]">
                                <table className="min-w-full text-xs">
                                    <thead className="bg-gray-50 text-gray-600 text-left sticky top-0">
                                        <tr>
                                            <th className="px-3 py-2 font-medium w-10">Row</th>
                                            <th className="px-3 py-2 font-medium">Part</th>
                                            <th className="px-3 py-2 font-medium text-right w-24">System</th>
                                            <th className="px-3 py-2 font-medium text-right w-24">Counted</th>
                                            <th className="px-3 py-2 font-medium text-right w-24">Difference</th>
                                            <th className="px-3 py-2 font-medium min-w-64">Status</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-100">
                                        {result.records.map(rec => {
                                            const hasErr = rec._errors.length > 0
                                            return (
                                                <tr key={rec._rowIndex} className={hasErr ? 'bg-red-50' : rec._isFound ? 'bg-blue-50' : ''}>
                                                    <td className="px-3 py-1.5 text-gray-400">{rec._rowIndex}</td>
                                                    <td className="px-3 py-1.5 text-gray-900">
                                                        {rec._partLabel}
                                                        {rec._isFound && !hasErr && (
                                                            <span className="ml-2 text-blue-600">found on shelf</span>
                                                        )}
                                                    </td>
                                                    <td className="px-3 py-1.5 text-right text-gray-500">
                                                        {hasErr ? '—' : rec._systemQty}
                                                    </td>
                                                    <td className="px-3 py-1.5 text-right text-gray-900">
                                                        {rec._countedQty ?? '—'}
                                                    </td>
                                                    <td className={`px-3 py-1.5 text-right font-medium ${
                                                        hasErr || rec._variance === null ? 'text-gray-400'
                                                            : rec._variance < 0 ? 'text-red-600'
                                                            : rec._variance > 0 ? 'text-green-700' : 'text-gray-400'
                                                    }`}>
                                                        {hasErr || rec._variance === null
                                                            ? '—'
                                                            : rec._variance > 0 ? `+${rec._variance}` : rec._variance}
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
                                                        ) : (
                                                            <span className="text-green-600 flex items-center gap-1">
                                                                <CheckCircleIcon className="w-3 h-3" /> OK
                                                            </span>
                                                        )}
                                                    </td>
                                                </tr>
                                            )
                                        })}
                                    </tbody>
                                </table>
                            </div>

                            {submitError && (
                                <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{submitError}</p>
                            )}
                        </div>
                    )}
                </div>

                <div className="px-6 py-4 border-t bg-gray-50 rounded-b-xl flex justify-between items-center flex-shrink-0">
                    <div>
                        {step === STEPS.VALIDATE && (
                            <button
                                type="button"
                                onClick={() => { setStep(STEPS.UPLOAD); setResult(null); setSubmitError(null) }}
                                className="text-sm text-gray-600 hover:text-gray-900"
                            >
                                ← Choose another file
                            </button>
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
                        {step === STEPS.VALIDATE && (
                            <button
                                type="button"
                                onClick={handleSubmit}
                                disabled={blocked || submitCounts.isPending}
                                className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                            >
                                {submitCounts.isPending ? 'Uploading…' : 'Upload counts'}
                            </button>
                        )}
                    </div>
                </div>
            </div>
        </div>
    )
}
