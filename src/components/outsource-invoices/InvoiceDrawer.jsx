import { useState } from 'react'
import { useInvoicePayments } from '../../hooks/useOutsourceInvoices'
import { invoiceSettlement, toPaise } from '../../utils/settlement'
import PaymentList from './PaymentList'
import InvoiceHistory from './InvoiceHistory'
import {
    fmtMoney,
    fmtPaise,
    fmtDate,
    MAINTENANCE_STATUS_COLORS,
    financeStatusColor,
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

function Amount({ label, value, strong, tone }) {
    return (
        <div className="flex justify-between gap-2">
            <dt className="text-gray-500">{label}</dt>
            <dd className={`${strong ? 'font-semibold' : 'font-medium'} ${tone ?? 'text-gray-900'} tabular-nums`}>{value}</dd>
        </div>
    )
}

function Section({ title, children }) {
    return (
        <section className="space-y-2">
            <h3 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">{title}</h3>
            {children}
        </section>
    )
}

/**
 * Read-only view of one outsource invoice (MAIN-98): details, amounts, payments
 * (including cancelled ones) and history. Every edit happens in the table.
 */
export default function InvoiceDrawer({ invoice, onClose }) {
    const { data: payments = [], isLoading: paymentsLoading } = useInvoicePayments(invoice.id)
    const { payable, paid, tds, roundOff, balance } = invoiceSettlement(invoice, payments)
    const discount = toPaise(invoice.invoice_value ?? 0) - toPaise(invoice.approved_amount ?? 0)

    return (
        <div className="fixed inset-0 z-40 flex" onClick={onClose}>
            <div className="flex-1 bg-black/30" />
            <div
                className="w-full max-w-lg bg-white shadow-2xl overflow-y-auto"
                onClick={e => e.stopPropagation()}
            >
                <div className="sticky top-0 z-10 bg-white border-b border-gray-200 px-5 py-3 flex items-center justify-between">
                    <div>
                        <h2 className="text-base font-semibold text-gray-900">
                            Invoice #{invoice.invoice_no || invoice.id.slice(0, 8)}
                        </h2>
                        <p className="text-xs text-gray-500">
                            Job card #{invoice.job_card?.job_card_number} · {invoice.job_card?.vehicle_number || '—'} · {invoice.job_card?.supplier?.entity_name || '—'}
                        </p>
                    </div>
                    <button
                        onClick={onClose}
                        className="text-gray-400 hover:text-gray-600 text-2xl leading-none"
                    >
                        &times;
                    </button>
                </div>

                <div className="px-5 py-4 space-y-5 text-sm">
                    {/* Invoice file — what finance reads for Tally entry */}
                    <div className="flex items-center justify-between gap-3 rounded-lg bg-gray-50 border border-gray-200 px-3 py-2">
                        <div>
                            <p className="text-xs text-gray-500">Invoice submitted</p>
                            <p className="font-medium text-gray-900">{fmtDate(invoice.created_at)}</p>
                        </div>
                        <InvoiceFileLink url={invoice.job_card?.invoice_url} />
                    </div>

                    <Section title="Status">
                        <div className="grid grid-cols-2 gap-3">
                            <div>
                                <p className="text-xs text-gray-500 mb-1">Reported by maintenance</p>
                                <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${MAINTENANCE_STATUS_COLORS[invoice.maintenance_payment_status] ?? 'bg-gray-100 text-gray-600'}`}>
                                    {invoice.maintenance_payment_status || '—'}
                                </span>
                            </div>
                            <div>
                                <p className="text-xs text-gray-500 mb-1">Reported by finance</p>
                                <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${financeStatusColor(invoice.finance_payment_status)}`}>
                                    {invoice.finance_payment_status}
                                </span>
                            </div>
                        </div>
                        {invoice.finance_remark && (
                            <p className="text-gray-700 whitespace-pre-line">
                                <span className="text-xs text-gray-500">Finance remark: </span>{invoice.finance_remark}
                            </p>
                        )}
                    </Section>

                    <Section title="Amounts">
                        <dl className="grid grid-cols-2 gap-x-6 gap-y-1.5">
                            <Amount label="Invoice value" value={fmtMoney(invoice.invoice_value)} />
                            <Amount label="Paid" value={fmtPaise(paid)} />
                            <Amount label="Discount" value={fmtPaise(discount)} />
                            <Amount label="TDS" value={fmtPaise(tds)} />
                            <Amount label="Approved" value={fmtMoney(invoice.approved_amount)} />
                            <Amount label="Round-off" value={fmtPaise(roundOff)} />
                            <Amount label="Advance" value={fmtMoney(invoice.advance_amount)} />
                            {balance < 0
                                ? <Amount label="Overpaid" value={fmtPaise(-balance)} strong tone="text-red-600" />
                                : <Amount label="Balance" value={fmtPaise(balance)} strong />}
                            <Amount label="Payable" value={fmtPaise(payable)} strong />
                        </dl>
                    </Section>

                    <Section title="Payments">
                        {paymentsLoading
                            ? <p className="text-xs text-gray-400">Loading payments…</p>
                            : <PaymentList payments={payments} invoiceId={invoice.id} canManage={false} />}
                    </Section>

                    <Section title="Details">
                        <dl className="grid grid-cols-2 gap-x-6 gap-y-2">
                            {[
                                ['Activity date', fmtDate(invoice.date_of_activity)],
                                ['Job card completed', fmtDate(invoice.job_card?.completed_at)],
                                ['Paid By', invoice.paid_by || '—'],
                                ['Pay by', fmtDate(invoice.payby_date)],
                            ].map(([label, value]) => (
                                <div key={label}>
                                    <dt className="text-xs text-gray-500">{label}</dt>
                                    <dd className="font-medium text-gray-900">{value}</dd>
                                </div>
                            ))}
                        </dl>
                    </Section>

                    <details className="group border-t border-gray-100 pt-4">
                        <summary className="cursor-pointer list-none flex items-center justify-between text-xs font-semibold text-gray-500 uppercase tracking-wide">
                            History
                            <span className="text-gray-400 group-open:rotate-90 transition-transform">▸</span>
                        </summary>
                        <div className="mt-3">
                            <InvoiceHistory invoiceId={invoice.id} />
                        </div>
                    </details>
                </div>
            </div>
        </div>
    )
}
