import { Fragment, useState } from 'react'
import { useCancelInvoicePayment } from '../../hooks/useOutsourceInvoices'
import { fmtMoney, fmtDate } from './format'

const HEADINGS = ['Paid on', 'Paid', 'TDS', 'Round-off', 'Ledger', 'Method', 'Bank', 'UTR', 'By', '']

/**
 * One payment row. Cancelled payments stay visible — readable, marked with a
 * Cancelled badge, the reason on the line beneath — and count for nothing (MAIN-95).
 * Cancel sits in the row's last cell, beside the payment it cancels (MAIN-98).
 */
function PaymentRow({ payment, invoiceId, canManage }) {
    const [cancelling, setCancelling] = useState(false)
    const [reason, setReason] = useState('')
    const cancel = useCancelInvoicePayment()
    const isCancelled = payment.status === 'Cancelled'
    const tone = isCancelled ? 'text-gray-600' : 'text-gray-900'

    const confirm = () =>
        cancel.mutate(
            { paymentId: payment.id, invoiceId, reason: reason.trim() },
            { onSuccess: () => setCancelling(false) },
        )

    return (
        <Fragment>
            <tr className={tone}>
                <td className="py-1.5 pr-4 whitespace-nowrap font-medium">{fmtDate(payment.paid_on)}</td>
                <td className="py-1.5 pr-4 whitespace-nowrap text-right tabular-nums">{fmtMoney(payment.amount_paid)}</td>
                <td className="py-1.5 pr-4 whitespace-nowrap text-right tabular-nums">{fmtMoney(payment.tds_amount)}</td>
                <td className="py-1.5 pr-4 whitespace-nowrap text-right tabular-nums">
                    {Number(payment.round_off) > 0 ? fmtMoney(payment.round_off) : '—'}
                </td>
                <td className="py-1.5 pr-4 whitespace-nowrap">{payment.ledger}</td>
                <td className="py-1.5 pr-4 whitespace-nowrap">{payment.payment_method}</td>
                <td className="py-1.5 pr-4 whitespace-nowrap">{payment.bank || '—'}</td>
                <td className="py-1.5 pr-4 whitespace-nowrap font-mono">{payment.utr || '—'}</td>
                <td className="py-1.5 pr-4 whitespace-nowrap">{payment.recorded_by_name || '—'}</td>
                <td className="py-1.5 whitespace-nowrap text-right">
                    {isCancelled ? (
                        <span className="px-2 py-0.5 rounded-full text-[11px] font-semibold uppercase tracking-wide bg-red-100 text-red-700">
                            Cancelled
                        </span>
                    ) : canManage && !cancelling ? (
                        <button
                            type="button"
                            onClick={() => setCancelling(true)}
                            className="px-2 py-0.5 text-red-700 border border-red-300 rounded-md bg-white hover:bg-red-50"
                        >
                            Cancel
                        </button>
                    ) : null}
                </td>
            </tr>

            {isCancelled && (
                <tr>
                    <td colSpan={HEADINGS.length} className="pb-2 text-red-700">
                        ↳ {payment.cancel_reason} — cancelled {fmtDate(payment.cancelled_at)} by {payment.cancelled_by_name || '—'}
                    </td>
                </tr>
            )}

            {cancelling && (
                <tr>
                    <td colSpan={HEADINGS.length} className="pb-2">
                        <div className="flex flex-wrap items-center gap-2">
                            <input
                                autoFocus
                                value={reason}
                                onChange={e => setReason(e.target.value)}
                                placeholder="Why? e.g. UTR failed, refund received 28 Oct"
                                aria-label="Reason for cancelling"
                                className="flex-1 min-w-[16rem] border border-gray-300 rounded-md px-2 py-1 bg-white focus:outline-none focus:ring-2 focus:ring-red-400"
                            />
                            <button
                                type="button"
                                onClick={confirm}
                                disabled={!reason.trim() || cancel.isPending}
                                className="px-2.5 py-1 bg-red-600 text-white rounded-md hover:bg-red-700 disabled:opacity-50"
                            >
                                {cancel.isPending ? 'Cancelling…' : 'Cancel payment'}
                            </button>
                            <button
                                type="button"
                                onClick={() => { setCancelling(false); setReason('') }}
                                className="px-2.5 py-1 text-gray-700 border border-gray-300 rounded-md bg-white hover:bg-gray-50"
                            >
                                Keep
                            </button>
                            {cancel.error && <span className="w-full text-red-700">{cancel.error.message}</span>}
                        </div>
                    </td>
                </tr>
            )}
        </Fragment>
    )
}

export default function PaymentList({ payments, invoiceId, canManage }) {
    if (payments.length === 0) {
        return <p className="text-xs text-gray-600 italic">No payments recorded yet.</p>
    }
    return (
        <table className="text-xs">
            <thead>
                <tr className="text-left text-gray-600">
                    {HEADINGS.map((h, i) => (
                        <th
                            key={h || i}
                            className={`pb-1 pr-4 font-semibold uppercase tracking-wide text-[11px] ${['Paid', 'TDS', 'Round-off'].includes(h) ? 'text-right' : ''}`}
                        >
                            {h}
                        </th>
                    ))}
                </tr>
            </thead>
            <tbody>
                {payments.map(p => (
                    <PaymentRow key={p.id} payment={p} invoiceId={invoiceId} canManage={canManage} />
                ))}
            </tbody>
        </table>
    )
}
