import { useState } from 'react'
import { createPortal } from 'react-dom'
import { XMarkIcon } from '@heroicons/react/24/outline'

/**
 * Asks for the reason before finance rejects an outsource invoice (MAIN-118). Reject is
 * final until the invoice is resubmitted (MAIN-120), so the dialog says so. The reason
 * is saved as the finance remark in the same write as the status, and the database
 * refuses a Reject without a new one.
 *
 * Rendered in a portal: the status cell sits in a no-wrap, sideways-scrolling table.
 */
export default function RejectInvoiceModal({ invoice, onConfirm, onCancel, isSaving, error }) {
    const [reason, setReason] = useState('')
    const trimmed = reason.trim()
    const sameAsRemark = trimmed !== '' && trimmed === (invoice.finance_remark ?? '').trim()
    const canConfirm = trimmed !== '' && !sameAsRemark && !isSaving

    return createPortal(
        <div className="fixed inset-0 z-50 overflow-y-auto whitespace-normal">
            <div className="fixed inset-0 bg-black bg-opacity-50" onClick={onCancel} />

            <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
                <div role="dialog" aria-labelledby="reject-invoice-title" className="relative bg-white rounded-t-2xl sm:rounded-2xl shadow-xl w-full max-w-md">
                    <div className="flex items-center justify-between p-5 border-b">
                        <h3 id="reject-invoice-title" className="text-lg font-semibold text-gray-900">
                            Reject invoice {invoice.invoice_no}
                        </h3>
                        <button type="button" onClick={onCancel} aria-label="Close" className="text-gray-500 hover:text-gray-600 p-1">
                            <XMarkIcon className="w-6 h-6" />
                        </button>
                    </div>

                    <div className="p-5 space-y-4">
                        <p className="text-sm text-red-800 bg-red-50 border border-red-200 rounded-lg p-3">
                            Reject is final. Nobody can change this invoice's status afterwards — it can
                            only come back by being resubmitted.
                        </p>
                        <div>
                            <label htmlFor="reject-invoice-reason" className="block text-sm font-medium text-gray-700 mb-1">
                                Reason <span className="text-red-500">*</span>
                            </label>
                            <textarea
                                id="reject-invoice-reason"
                                autoFocus
                                rows={3}
                                value={reason}
                                onChange={e => setReason(e.target.value)}
                                className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-red-500"
                            />
                            <p className="text-xs text-gray-500 mt-1">Saved as the finance remark.</p>
                            {sameAsRemark && (
                                <p className="text-xs text-red-600 mt-1">That is the current remark — give the reason for rejecting.</p>
                            )}
                        </div>
                        {error && <p className="text-sm text-red-600">{error.message}</p>}
                    </div>

                    <div className="flex justify-end gap-3 p-5 border-t">
                        <button
                            type="button"
                            onClick={onCancel}
                            className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50"
                        >
                            Cancel
                        </button>
                        <button
                            type="button"
                            onClick={() => onConfirm(trimmed)}
                            disabled={!canConfirm}
                            className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-lg hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {isSaving ? 'Rejecting…' : 'Reject invoice'}
                        </button>
                    </div>
                </div>
            </div>
        </div>,
        document.body,
    )
}
