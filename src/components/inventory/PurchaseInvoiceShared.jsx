import { XMarkIcon } from '@heroicons/react/24/outline'
import MultiFileAttach from '../shared/MultiFileAttach'
import InvoiceFileLink from '../outsource-invoices/InvoiceFileLink'
import SupplierPicker from '../suppliers/SupplierPicker'
import InvoiceDetailsFields, { InvoiceDetailsReadOnly } from '../outsource-invoices/InvoiceDetailsFields'
import { financeStatusColor } from '../outsource-invoices/format'

/**
 * The pieces the purchase and refurbishment forms share (MAIN-130), driven by
 * usePurchaseInvoiceForm: the modal with its finance badge and save, and the supplier,
 * notes, finance details and file. Each form supplies its own workshop and lines.
 */

/** The modal: title and finance badge, the form body, and a footer with Save for execs. */
export function PurchaseInvoiceModal({ title, form, loading, error, onClose, onSubmit, footer, children }) {
    const { finance, isFinanceRole, saving } = form
    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-5xl max-h-[90vh] flex flex-col">
                <div className="flex items-center justify-between px-6 py-4 border-b">
                    <div className="flex items-center gap-3">
                        <h2 className="text-lg font-semibold text-gray-900">{title}</h2>
                        {finance && (
                            <span
                                title={finance.finance_remark || undefined}
                                className={`px-2 py-0.5 rounded-full text-xs font-medium ${financeStatusColor(finance.finance_payment_status)}`}
                            >
                                Finance: {finance.finance_payment_status}
                            </span>
                        )}
                    </div>
                    <button onClick={onClose} className="text-gray-400 hover:text-gray-600">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                {loading ? (
                    <div className="flex-1 flex items-center justify-center py-16 text-sm text-gray-400">
                        Loading invoice details…
                    </div>
                ) : (
                    <form onSubmit={onSubmit} className="flex flex-col flex-1 overflow-hidden">
                        <div className="overflow-y-auto flex-1 px-6 py-4 space-y-6">
                            {children}
                            {error && (
                                <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{error}</p>
                            )}
                        </div>

                        <div className="px-6 py-4 border-t flex items-center justify-between bg-gray-50 rounded-b-xl">
                            <div className="flex items-center gap-6">{footer}</div>
                            <div className="flex gap-3">
                                <button
                                    type="button"
                                    onClick={onClose}
                                    className="px-4 py-2 text-sm text-gray-700 border rounded-lg hover:bg-gray-100"
                                >
                                    {isFinanceRole ? 'Close' : 'Cancel'}
                                </button>
                                {!isFinanceRole && (
                                    <button
                                        type="submit"
                                        disabled={saving}
                                        className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                                    >
                                        {saving ? 'Saving…' : 'Save Changes'}
                                    </button>
                                )}
                            </div>
                        </div>
                    </form>
                )}
            </div>
        </div>
    )
}

/** The invoice total, and what is wrong with it against the Approved Amount. */
export function InvoiceTotal({ total, amountProblem }) {
    return (
        <div className="text-sm">
            <span className="font-semibold text-gray-700">
                Invoice Total: <span className="text-gray-900">{total.toFixed(2)}</span>
            </span>
            {amountProblem && (
                <p className="text-xs text-red-600 mt-0.5">{amountProblem}</p>
            )}
        </div>
    )
}

/**
 * Supplier, notes and the form's workshop; then the invoice details for finance and the
 * invoice file. `workshop` is the form's own workshop control.
 */
export function PurchaseInvoiceFields({ form, workshop }) {
    const {
        invoice, finance, isFinanceRole, accepted, frozen, todayStr,
        header, setHeader, invoiceForm, setInvoiceForm, invoiceErrors, showErrors,
        invoiceFile, setInvoiceFile, filePending,
    } = form
    const inputClass = locked =>
        `w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 ${locked ? 'bg-gray-50 text-gray-500 cursor-not-allowed' : ''}`

    return (
        <>
            <div>
                <h3 className="text-sm font-semibold text-gray-700 mb-3">Invoice Details</h3>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1">
                            Supplier {invoice.supplier_id && <span className="text-red-500">*</span>}
                        </label>
                        <SupplierPicker
                            value={header.supplier_id}
                            onChange={id => setHeader(p => ({ ...p, supplier_id: id }))}
                            current={invoice.supplier_id ? { id: invoice.supplier_id, name: invoice.supplier_name } : null}
                            disabled={frozen}
                        />
                        {/* Recorded before suppliers came from the list (MAIN-128): the typed
                            name stays as it is unless a supplier is chosen. */}
                        {!invoice.supplier_id && !header.supplier_id && (
                            <p className="text-xs text-gray-500 mt-1">
                                Recorded as "{invoice.supplier_name}", not linked to a supplier. You can leave it or choose one.
                            </p>
                        )}
                    </div>
                    {/* With a finance invoice, the number and date are in its details. */}
                    {!finance && <>
                        <div>
                            <label className="block text-xs font-medium text-gray-600 mb-1">
                                Invoice Number <span className="text-red-500">*</span>
                            </label>
                            <input
                                required
                                type="text"
                                className={inputClass(frozen)}
                                disabled={frozen}
                                value={header.invoice_number}
                                onChange={e => setHeader(p => ({ ...p, invoice_number: e.target.value }))}
                            />
                        </div>
                        <div>
                            <label className="block text-xs font-medium text-gray-600 mb-1">
                                Invoice Date <span className="text-red-500">*</span>
                            </label>
                            <input
                                required
                                type="date"
                                className={inputClass(frozen)}
                                disabled={frozen}
                                value={header.invoice_date}
                                onChange={e => setHeader(p => ({ ...p, invoice_date: e.target.value }))}
                            />
                        </div>
                    </>}
                    <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1">Notes</label>
                        <input
                            type="text"
                            className={inputClass(isFinanceRole)}
                            disabled={isFinanceRole}
                            value={header.notes}
                            onChange={e => setHeader(p => ({ ...p, notes: e.target.value }))}
                            placeholder="Optional"
                        />
                    </div>
                    <div className="sm:col-span-2">{workshop}</div>
                </div>
            </div>

            {finance && (
                <div>
                    <h3 className="text-sm font-semibold text-gray-700 mb-3">Invoice Details for Finance</h3>
                    {frozen ? (
                        <InvoiceDetailsReadOnly invoice={finance} />
                    ) : (
                        <InvoiceDetailsFields
                            form={invoiceForm}
                            setForm={setInvoiceForm}
                            errors={invoiceErrors}
                            showErrors={showErrors}
                            todayStr={todayStr}
                            dateLabel="Invoice Date"
                        />
                    )}
                    {accepted && !isFinanceRole && (
                        <p className="text-xs text-gray-500 mt-2">
                            Finance has accepted this invoice, so only its notes can be changed. Finance moving it back to Hold lifts this.
                        </p>
                    )}
                </div>
            )}

            <div>
                <h3 className="text-sm font-semibold text-gray-700 mb-3">Invoice Document</h3>
                {frozen
                    ? <InvoiceFileLink url={invoiceFile?.url} />
                    : <MultiFileAttach value={invoiceFile} onChange={setInvoiceFile} />}
                {filePending && !frozen && (
                    <p className="text-xs text-amber-700 mt-1">
                        Finance sees this invoice as New (invoice pending) and cannot accept it until the file is uploaded here.
                    </p>
                )}
            </div>
        </>
    )
}
