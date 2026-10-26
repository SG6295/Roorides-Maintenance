import { useState } from 'react'
import CustomSelect from '../shared/CustomSelect'
import { useInvoicePayments, useUpdateFinancePaymentStatus } from '../../hooks/useOutsourceInvoices'
import { invoiceSettlement, toPaise } from '../../utils/settlement'
import {
    MANUAL_FINANCE_PAYMENT_STATUSES,
    PAYMENT_DERIVED_STATUSES,
} from '../../constants/outsourceInvoices'
import RecordPaymentForm from './RecordPaymentForm'
import PaymentList from './PaymentList'
import InvoiceHistory from './InvoiceHistory'
import {
    fmtMoney,
    fmtPaise,
    fmtDate,
    MAINTENANCE_STATUS_COLORS,
    financeStatusColor,
    FINANCE_ROLES,
} from './format'

function InvoiceFileLink({ url }) {
    const [copied, setCopied] = useState(false)

    if (!url) return <span className="text-gray-400 italic">No invoice file</span>

    const copy = async () => {
        try {
            await navigator.clipboard.writeText(url)
            setCopied(true)
            setTimeout(() => setCopied(false), 2000)
        } catch {
            // Clipboard access can be refused (permissions, insecure context); the
            // View link still works, so there is nothing to recover.
        }
    }

    return (
        <div className="flex items-center gap-2 shrink-0">
            <a
                href={url}
                target="_blank"
                rel="noopener noreferrer"
                className="text-blue-600 hover:underline font-medium"
            >
                View invoice →
            </a>
            <button
                type="button"
                onClick={copy}
                className="text-xs px-2 py-1 text-gray-600 border border-gray-300 rounded-lg hover:bg-white transition-colors"
            >
                {copied ? 'Copied ✓' : 'Copy link'}
            </button>
        </div>
    )
}

function FinanceStatusForm({ invoice, onSaved }) {
    const [status, setStatus] = useState(invoice.finance_payment_status)
    const [remark, setRemark] = useState(invoice.finance_remark ?? '')
    const update = useUpdateFinancePaymentStatus()

    // Partly Paid and Paid come only from payments. When the invoice is in one of
    // them it is listed so the dropdown can show it, but choosing it changes nothing.
    const options = PAYMENT_DERIVED_STATUSES.includes(invoice.finance_payment_status)
        ? [invoice.finance_payment_status, ...MANUAL_FINANCE_PAYMENT_STATUSES]
        : MANUAL_FINANCE_PAYMENT_STATUSES

    const dirty =
        status !== invoice.finance_payment_status ||
        (remark.trim() || null) !== (invoice.finance_remark ?? null)

    const save = () =>
        update.mutate(
            { id: invoice.id, financePaymentStatus: status, financeRemark: remark },
            { onSuccess: onSaved },
        )

    return (
        <div className="space-y-3 rounded-lg border border-blue-100 bg-blue-50/40 p-4">
            <CustomSelect
                label="Payment status reported by finance"
                value={status}
                onChange={setStatus}
                options={options}
            />
            <p className="text-xs text-gray-500 -mt-1">
                Partly Paid and Paid are set automatically by the payments below.
            </p>
            <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Finance remark</label>
                <textarea
                    rows={2}
                    value={remark}
                    onChange={e => setRemark(e.target.value)}
                    placeholder="Optional"
                    className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
            </div>
            {update.error && (
                <p className="text-sm text-red-600">{update.error.message}</p>
            )}
            <div className="flex items-center justify-end gap-3">
                {update.isSuccess && !dirty && (
                    <span className="text-xs text-green-700">Saved ✓</span>
                )}
                <button
                    type="button"
                    onClick={save}
                    disabled={!dirty || update.isPending}
                    className="px-4 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                    {update.isPending ? 'Saving…' : 'Save'}
                </button>
            </div>
        </div>
    )
}

function SummaryRow({ label, value, strong, tone }) {
    return (
        <div className="flex justify-between py-1">
            <span className="text-gray-500">{label}</span>
            <span className={`${strong ? 'font-semibold' : 'font-medium'} ${tone ?? 'text-gray-900'}`}>{value}</span>
        </div>
    )
}

/**
 * Where the money stands (MAIN-95): what was billed, what was approved, what has
 * been settled and what is left. Discount is Invoice value − Approved amount.
 */
function PaymentSummary({ invoice, settlement }) {
    const discount = toPaise(invoice.invoice_value ?? 0) - toPaise(invoice.approved_amount ?? 0)
    const { payable, paid, tds, roundOff, balance } = settlement

    return (
        <div className="text-sm divide-y divide-gray-100">
            <div className="pb-2">
                <SummaryRow label="Invoice value" value={fmtMoney(invoice.invoice_value)} />
                <SummaryRow label="Discount" value={fmtPaise(discount)} />
                <SummaryRow label="Approved amount" value={fmtMoney(invoice.approved_amount)} />
                <SummaryRow label="Advance" value={fmtMoney(invoice.advance_amount)} />
                <SummaryRow label="Payable" value={fmtPaise(payable)} strong />
            </div>
            <div className="pt-2">
                <SummaryRow label="Paid" value={fmtPaise(paid)} />
                <SummaryRow label="TDS" value={fmtPaise(tds)} />
                {roundOff > 0 && <SummaryRow label="Round-off" value={fmtPaise(roundOff)} />}
                {balance < 0 ? (
                    <SummaryRow label="Overpaid by" value={fmtPaise(-balance)} strong tone="text-red-600" />
                ) : (
                    <SummaryRow label="Balance" value={fmtPaise(balance)} strong />
                )}
            </div>
        </div>
    )
}

export default function InvoiceDrawer({ invoice, role, onClose, onInvoiceSaved }) {
    const [recording, setRecording] = useState(false)
    const { data: payments = [], isLoading: paymentsLoading } = useInvoicePayments(invoice.id)
    const isFinance = FINANCE_ROLES.includes(role)
    const settlement = invoiceSettlement(invoice, payments)

    return (
        <div className="fixed inset-0 z-40 flex" onClick={onClose}>
            <div className="flex-1 bg-black/30" />
            <div
                className="w-full max-w-lg bg-white shadow-2xl overflow-y-auto"
                onClick={e => e.stopPropagation()}
            >
                <div className="sticky top-0 z-10 bg-white border-b border-gray-200 px-6 py-4 flex items-center justify-between">
                    <h2 className="text-lg font-semibold text-gray-900">
                        Invoice #{invoice.invoice_no || invoice.id.slice(0, 8)}
                    </h2>
                    <button
                        onClick={onClose}
                        className="text-gray-400 hover:text-gray-600 text-2xl leading-none"
                    >
                        &times;
                    </button>
                </div>
                <div className="p-6 space-y-5">
                    {/* Invoice file — what finance reads for Tally entry */}
                    <div className="flex items-center justify-between gap-3 rounded-lg bg-gray-50 border border-gray-200 px-4 py-3 text-sm">
                        <div>
                            <p className="text-xs text-gray-500 mb-0.5">Invoice submitted</p>
                            <p className="font-medium text-gray-900">{fmtDate(invoice.created_at)}</p>
                        </div>
                        <InvoiceFileLink url={invoice.job_card?.invoice_url} />
                    </div>

                    {/* Both statuses, each owned by one side */}
                    <div className="space-y-4">
                        <div>
                            <p className="text-xs text-gray-500 mb-1">Payment status reported by maintenance</p>
                            <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${MAINTENANCE_STATUS_COLORS[invoice.maintenance_payment_status] ?? 'bg-gray-100 text-gray-600'}`}>
                                {invoice.maintenance_payment_status || '—'}
                            </span>
                        </div>
                        {isFinance ? (
                            <FinanceStatusForm
                                key={`${invoice.id}-${invoice.finance_payment_status}`}
                                invoice={invoice}
                                onSaved={onInvoiceSaved}
                            />
                        ) : (
                            <div>
                                <p className="text-xs text-gray-500 mb-1">Payment status reported by finance</p>
                                <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${financeStatusColor(invoice.finance_payment_status)}`}>
                                    {invoice.finance_payment_status}
                                </span>
                                {invoice.finance_remark && (
                                    <p className="mt-1.5 text-sm text-gray-700 whitespace-pre-line">{invoice.finance_remark}</p>
                                )}
                            </div>
                        )}
                    </div>

                    {/* Amounts and payments */}
                    <div className="pt-4 border-t border-gray-100 space-y-3">
                        <h3 className="text-sm font-semibold text-gray-700 uppercase tracking-wide">Payments</h3>
                        <PaymentSummary invoice={invoice} settlement={settlement} />
                        {paymentsLoading ? (
                            <p className="text-sm text-gray-400">Loading payments…</p>
                        ) : (
                            <PaymentList payments={payments} invoiceId={invoice.id} canManage={isFinance} />
                        )}
                        {isFinance && (
                            recording ? (
                                <RecordPaymentForm
                                    invoiceId={invoice.id}
                                    balancePaise={Math.max(settlement.balance, 0)}
                                    onDone={() => setRecording(false)}
                                />
                            ) : settlement.balance > 0 ? (
                                <button
                                    type="button"
                                    onClick={() => setRecording(true)}
                                    className="w-full py-2 text-sm font-medium text-blue-700 border border-blue-200 rounded-lg hover:bg-blue-50"
                                >
                                    + Record payment
                                </button>
                            ) : null
                        )}
                    </div>

                    <div className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm pt-4 border-t border-gray-100">
                        {[
                            ['Job Card',      `#${invoice.job_card?.job_card_number}`],
                            ['Vehicle',        invoice.job_card?.vehicle_number || '—'],
                            ['Supplier',       invoice.job_card?.supplier?.entity_name || '—'],
                            ['Completed',      fmtDate(invoice.job_card?.completed_at)],
                            ['Activity Date',  fmtDate(invoice.date_of_activity)],
                            ['Invoice No',     invoice.invoice_no || '—'],
                            ['Paid By',        invoice.paid_by || '—'],
                            ['Pay By Date',    fmtDate(invoice.payby_date)],
                        ].map(([label, value]) => (
                            <div key={label}>
                                <p className="text-xs text-gray-500 mb-0.5">{label}</p>
                                <p className="font-medium text-gray-900">{value}</p>
                            </div>
                        ))}
                    </div>

                    <div className="pt-4 border-t border-gray-100 space-y-3">
                        <h3 className="text-sm font-semibold text-gray-700 uppercase tracking-wide">History</h3>
                        <InvoiceHistory invoiceId={invoice.id} />
                    </div>
                </div>
            </div>
        </div>
    )
}
