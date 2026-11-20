import { useState } from 'react'
import { createPortal } from 'react-dom'
import { Link } from 'react-router-dom'
import { XMarkIcon } from '@heroicons/react/24/outline'
import InvoiceDetailsFields from './InvoiceDetailsFields'
import DocumentUpload from '../suppliers/DocumentUpload'
import SupplierPicker from '../suppliers/SupplierPicker'
import { validateInvoiceForm } from './invoiceForm'
import {
    resubmissionStart,
    resubmissionChanges,
    resubmissionProblem,
    resubmissionPayload,
    rejectionEntry,
} from './resubmission'
import { fmtDateTime } from './format'
import { useOutsourceInvoiceHistory, useResubmitOutsourceInvoice } from '../../hooks/useOutsourceInvoices'
import { useApprovedSuppliers } from '../../hooks/useSuppliers'
import { formatBatchNumber, batchPath } from '../../utils/batchNumber'
import { formatPurchaseNumber, purchaseInvoicePath } from '../../utils/purchaseInvoice'
import { todayLocal } from '../../utils/datetime'

/**
 * Corrects and resubmits a rejected invoice (MAIN-120), from the Invoices list
 * or the job card page: the file, the supplier and the invoice fields, with an optional
 * note to finance. `invoice` is a row in the list's shape (get_outsource_invoice_rows).
 *
 * A multi-vehicle invoice's or purchase's lines change only on its own page, which
 * resubmits in the same save; when the Approved Amount no longer matches them the popup
 * says so and links there. Rendered in a portal, as the list's cells are no-wrap.
 */
export default function ResubmitInvoiceModal({ invoice, onClose }) {
    const resubmit = useResubmitOutsourceInvoice()
    const { data: history = [] } = useOutsourceInvoiceHistory(invoice.id)
    const { data: suppliers = [] } = useApprovedSuppliers()
    const todayStr = todayLocal()

    const [start] = useState(() => resubmissionStart(invoice))
    const [supplierId, setSupplierId] = useState(start.supplierId)
    const [fileUrl, setFileUrl] = useState(start.fileUrl)
    const [form, setForm] = useState(start.form)
    const [note, setNote] = useState('')
    const [showErrors, setShowErrors] = useState(false)

    const batch = invoice.batch_service
    const purchase = invoice.purchase_invoice
    const refurbishment = purchase?.kind === 'refurbishment'
    const owner = batch ?? purchase ?? invoice.job_card
    const currentSupplier = owner?.supplier ? { id: owner.supplier.id, name: owner.supplier.entity_name } : null
    const supplierName = id => suppliers.find(s => s.id === id)?.entity_name
        ?? (id === currentSupplier?.id ? currentSupplier.name : '')

    const current = { supplierId, fileUrl, form }
    const errors = validateInvoiceForm(form, todayStr)
    const changes = resubmissionChanges(start, current, supplierName)
    const problem = resubmissionProblem(invoice, start, current, {
        invalid: Object.keys(errors).length > 0,
        changes,
    })
    const rejection = rejectionEntry(history)

    const submit = () => {
        setShowErrors(true)
        if (problem) return
        resubmit.mutate(
            { id: invoice.id, resubmission: resubmissionPayload(current, note) },
            { onSuccess: onClose },
        )
    }

    return createPortal(
        <div className="fixed inset-0 z-50 overflow-y-auto whitespace-normal text-left">
            <div className="fixed inset-0 bg-black bg-opacity-50" onClick={onClose} />

            <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
                <div role="dialog" aria-labelledby="resubmit-invoice-title" className="relative bg-white rounded-t-2xl sm:rounded-2xl shadow-xl w-full max-w-2xl">
                    <div className="flex items-center justify-between p-5 border-b">
                        <h3 id="resubmit-invoice-title" className="text-lg font-semibold text-gray-900">
                            Resubmit invoice {invoice.invoice_no}
                        </h3>
                        <button type="button" onClick={onClose} aria-label="Close" className="text-gray-500 hover:text-gray-600 p-1">
                            <XMarkIcon className="w-6 h-6" />
                        </button>
                    </div>

                    <div className="p-5 space-y-5">
                        {/* ── Why it was rejected ── */}
                        <div className="text-sm bg-red-50 border border-red-200 rounded-lg p-3">
                            <p className="font-medium text-red-800">Rejected: {invoice.finance_remark || '—'}</p>
                            {rejection && (
                                <p className="text-xs text-red-700 mt-0.5">
                                    {rejection.performed_by_name || 'Someone'}, {fmtDateTime(rejection.performed_at)}
                                </p>
                            )}
                        </div>

                        {/* ── File ── */}
                        <div>
                            <p className="text-sm font-medium text-gray-700 mb-1.5">
                                Invoice file <span className="text-red-500">*</span>
                            </p>
                            <DocumentUpload label="" required value={fileUrl} onChange={url => setFileUrl(url || '')} />
                        </div>

                        {/* ── Supplier ── */}
                        <div>
                            <p className="text-sm font-medium text-gray-700 mb-1.5">
                                Supplier {start.supplierId && <span className="text-red-500">*</span>}
                            </p>
                            <SupplierPicker value={supplierId} onChange={setSupplierId} current={currentSupplier} />
                        </div>

                        {/* ── Invoice fields ── */}
                        <InvoiceDetailsFields
                            form={form}
                            setForm={setForm}
                            errors={errors}
                            showErrors={showErrors}
                            todayStr={todayStr}
                            dateLabel={purchase ? 'Invoice Date' : 'Date of Activity'}
                        />

                        {/* ── Note ── */}
                        <div>
                            <label htmlFor="resubmit-note" className="block text-sm font-medium text-gray-700 mb-1">
                                Note to finance <span className="text-gray-400 font-normal">(optional)</span>
                            </label>
                            <textarea
                                id="resubmit-note"
                                rows={2}
                                value={note}
                                onChange={e => setNote(e.target.value)}
                                className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                            />
                        </div>

                        {/* ── What has changed ── */}
                        <div>
                            <p className="text-sm font-medium text-gray-700 mb-1">Changes</p>
                            {changes.length === 0 ? (
                                <p className="text-sm text-gray-400 italic">Nothing changed yet.</p>
                            ) : (
                                <ul className="text-sm text-gray-700 list-disc pl-5 space-y-0.5">
                                    {changes.map(c => <li key={c}>{c}</li>)}
                                </ul>
                            )}
                        </div>

                        {problem && (showErrors || problem.linesMismatch) && (
                            <div className="text-sm text-amber-800 bg-amber-50 border border-amber-200 rounded-lg p-3">
                                <p>{problem.message}</p>
                                {problem.linesMismatch && (
                                    refurbishment ? (
                                        <p className="text-xs mt-1">A refurbishment's lines cannot change, so the Approved Amount must match them.</p>
                                    ) : batch ? (
                                        <Link to={batchPath(batch.batch_number)} className="text-xs text-blue-600 hover:underline mt-1 inline-block">
                                            Change the lines on {formatBatchNumber(batch.batch_number)} and resubmit from there →
                                        </Link>
                                    ) : (
                                        <Link to={purchaseInvoicePath(purchase.purchase_number)} className="text-xs text-blue-600 hover:underline mt-1 inline-block">
                                            Change the lines on {formatPurchaseNumber(purchase.purchase_number)} in Edit Purchase and resubmit from there →
                                        </Link>
                                    )
                                )}
                            </div>
                        )}
                        {resubmit.error && <p className="text-sm text-red-600">{resubmit.error.message}</p>}
                    </div>

                    <div className="flex justify-end gap-3 p-5 border-t">
                        <button
                            type="button"
                            onClick={onClose}
                            className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50"
                        >
                            Cancel
                        </button>
                        <button
                            type="button"
                            onClick={submit}
                            disabled={changes.length === 0 || resubmit.isPending}
                            className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {resubmit.isPending ? 'Resubmitting…' : 'Resubmit to finance'}
                        </button>
                    </div>
                </div>
            </div>
        </div>,
        document.body,
    )
}
