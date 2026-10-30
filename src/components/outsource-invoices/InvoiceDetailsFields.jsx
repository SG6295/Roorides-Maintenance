import { formatDate } from '../../utils/datetime'
import CustomSelect from '../shared/CustomSelect'
import { PAID_BY_OPTIONS, MAINTENANCE_PAYMENT_STATUSES } from '../../constants/outsourceInvoices'

/**
 * The outsource invoice's details, editable and read-only — shared by the job card and
 * the multi-vehicle invoice page (MAIN-99). The form's values and rules are in
 * invoiceForm.js.
 */

const rupees = v => `₹${Number(v).toLocaleString('en-IN', { minimumFractionDigits: 2 })}`

/** The saved invoice, read-only — after closure, or for anyone who may not edit it. */
export function InvoiceDetailsReadOnly({ invoice }) {
    return (
        <div className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
            {[
                ['Date of Activity', invoice?.date_of_activity
                    ? formatDate(invoice.date_of_activity)
                    : '—'],
                ['Invoice No', invoice?.invoice_no || '—'],
                ['Paid By', invoice?.paid_by || '—'],
                ['Payment status reported by maintenance', invoice?.maintenance_payment_status || '—'],
                ['Payment status reported by finance', invoice?.finance_payment_status || '—'],
                ['Invoice Value', invoice?.invoice_value != null
                    ? rupees(invoice.invoice_value)
                    : '—'],
                ['Approved Amount', invoice?.approved_amount != null
                    ? rupees(invoice.approved_amount)
                    : '—'],
                ['Advance Amount', invoice?.advance_amount != null
                    ? rupees(invoice.advance_amount)
                    : '—'],
                ['Payable Amount', (invoice?.approved_amount != null && invoice?.advance_amount != null)
                    ? rupees(invoice.approved_amount - invoice.advance_amount)
                    : '—'],
                ['Pay By Date', invoice?.payby_date
                    ? formatDate(invoice.payby_date)
                    : '—'],
            ].map(([label, value]) => (
                <div key={label}>
                    <p className="text-xs text-gray-500 mb-0.5">{label}</p>
                    <p className="font-medium text-gray-900">{value}</p>
                </div>
            ))}
        </div>
    )
}

/**
 * The editable invoice fields. `errors` comes from validateInvoiceForm and is shown
 * only once `showErrors` is set; `children` render below the fields. `optional` drops the
 * required marks — on a job card the invoice may come later, but once started it is
 * checked in full.
 */
export default function InvoiceDetailsFields({ form, setForm, errors, showErrors, todayStr, optional = false, children }) {
    const req = optional ? null : <span className="text-red-500">*</span>
    const payableAmount = (() => {
        const aa = parseFloat(form.approvedAmount)
        const adv = parseFloat(form.advanceAmount)
        return !isNaN(aa) && !isNaN(adv) ? aa - adv : null
    })()

    return (
        <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        Date of Activity {req}
                    </label>
                    <input
                        type="date"
                        value={form.dateOfActivity}
                        max={todayStr}
                        onChange={e => setForm(f => ({ ...f, dateOfActivity: e.target.value }))}
                        className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showErrors && errors.dateOfActivity ? 'border-red-400' : 'border-gray-300'}`}
                    />
                    {showErrors && errors.dateOfActivity && (
                        <p className="text-xs text-red-600 mt-0.5">{errors.dateOfActivity}</p>
                    )}
                </div>
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        Invoice No {req}
                    </label>
                    <input
                        type="text"
                        value={form.invoiceNo}
                        maxLength={50}
                        onChange={e => setForm(f => ({ ...f, invoiceNo: e.target.value }))}
                        placeholder="e.g. INV-2024-001"
                        className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showErrors && errors.invoiceNo ? 'border-red-400' : 'border-gray-300'}`}
                    />
                    {showErrors && errors.invoiceNo && (
                        <p className="text-xs text-red-600 mt-0.5">{errors.invoiceNo}</p>
                    )}
                </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        Paid By {req}
                    </label>
                    <CustomSelect
                        value={form.paidBy}
                        onChange={paidBy => setForm(f => ({ ...f, paidBy }))}
                        options={PAID_BY_OPTIONS}
                        placeholder="Select…"
                        error={showErrors && errors.paidBy}
                    />
                    {showErrors && errors.paidBy && (
                        <p className="text-xs text-red-600 mt-0.5">{errors.paidBy}</p>
                    )}
                </div>
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        Payment status reported by maintenance {req}
                    </label>
                    <CustomSelect
                        value={form.maintenancePaymentStatus}
                        onChange={maintenancePaymentStatus => setForm(f => ({ ...f, maintenancePaymentStatus }))}
                        options={MAINTENANCE_PAYMENT_STATUSES}
                        placeholder="Select…"
                        error={showErrors && errors.maintenancePaymentStatus}
                    />
                    {showErrors && errors.maintenancePaymentStatus && (
                        <p className="text-xs text-red-600 mt-0.5">{errors.maintenancePaymentStatus}</p>
                    )}
                </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        Invoice Value (₹) {req}
                    </label>
                    <input
                        type="number"
                        min="0.01"
                        step="0.01"
                        value={form.invoiceValue}
                        onChange={e => setForm(f => ({ ...f, invoiceValue: e.target.value }))}
                        placeholder="0.00"
                        className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showErrors && errors.invoiceValue ? 'border-red-400' : 'border-gray-300'}`}
                    />
                    {showErrors && errors.invoiceValue && (
                        <p className="text-xs text-red-600 mt-0.5">{errors.invoiceValue}</p>
                    )}
                </div>
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        Approved Amount (₹) {req}
                    </label>
                    <input
                        type="number"
                        min="0"
                        step="0.01"
                        value={form.approvedAmount}
                        onChange={e => setForm(f => ({ ...f, approvedAmount: e.target.value }))}
                        placeholder="0.00"
                        className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showErrors && errors.approvedAmount ? 'border-red-400' : 'border-gray-300'}`}
                    />
                    {showErrors && errors.approvedAmount && (
                        <p className="text-xs text-red-600 mt-0.5">{errors.approvedAmount}</p>
                    )}
                </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        Advance Amount (₹) {req}
                    </label>
                    <input
                        type="number"
                        min="0"
                        step="0.01"
                        value={form.advanceAmount}
                        onChange={e => setForm(f => ({ ...f, advanceAmount: e.target.value }))}
                        placeholder="0.00"
                        className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showErrors && errors.advanceAmount ? 'border-red-400' : 'border-gray-300'}`}
                    />
                    {showErrors && errors.advanceAmount && (
                        <p className="text-xs text-red-600 mt-0.5">{errors.advanceAmount}</p>
                    )}
                </div>
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        Payable Amount (₹)
                    </label>
                    <div className="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 bg-gray-50 font-medium text-gray-900 min-h-[38px]">
                        {payableAmount !== null
                            ? `₹${payableAmount.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
                            : <span className="text-gray-400 font-normal">Auto-computed</span>
                        }
                    </div>
                </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        Pay By Date {req}
                    </label>
                    <input
                        type="date"
                        value={form.paybyDate}
                        min={form.dateOfActivity || undefined}
                        onChange={e => setForm(f => ({ ...f, paybyDate: e.target.value }))}
                        className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showErrors && errors.paybyDate ? 'border-red-400' : 'border-gray-300'}`}
                    />
                    {showErrors && errors.paybyDate && (
                        <p className="text-xs text-red-600 mt-0.5">{errors.paybyDate}</p>
                    )}
                </div>
            </div>

            {children}
        </div>
    )
}
