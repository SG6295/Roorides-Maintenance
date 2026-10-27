import { useState } from 'react'
import { useCancelInvoicePayment } from '../../hooks/useOutsourceInvoices'
import { fmtMoney, fmtDate } from './format'

/**
 * One payment row. Cancelled payments stay visible, struck through, with who
 * cancelled them, when and why (MAIN-95).
 */
function PaymentRow({ payment, invoiceId, canManage }) {
    const [cancelling, setCancelling] = useState(false)
    const [reason, setReason] = useState('')
    const cancel = useCancelInvoicePayment()
    const isCancelled = payment.status === 'Cancelled'

    const confirm = () =>
        cancel.mutate(
            { paymentId: payment.id, invoiceId, reason: reason.trim() },
            { onSuccess: () => setCancelling(false) },
        )

    return (
        <li className="py-1.5 text-xs">
            <div className="flex items-center justify-between gap-3">
                <p className={isCancelled ? 'line-through text-gray-400' : 'text-gray-800'}>
                    <span className="font-medium">{fmtDate(payment.paid_on)} · {fmtMoney(payment.amount_paid)}</span>
                    {Number(payment.tds_amount) > 0 && <> + TDS {fmtMoney(payment.tds_amount)}</>}
                    {Number(payment.round_off) > 0 && <> + round-off {fmtMoney(payment.round_off)}</>}
                    <span className="text-gray-500">
                        {' · '}{payment.ledger} · {payment.payment_method}
                        {payment.bank && <> · {payment.bank}</>}
                        {payment.utr && <> · UTR {payment.utr}</>}
                        {' · by '}{payment.recorded_by_name || '—'}
                    </span>
                </p>
                {canManage && !isCancelled && !cancelling && (
                    <button
                        type="button"
                        onClick={() => setCancelling(true)}
                        className="shrink-0 px-2 py-0.5 text-red-600 border border-red-200 rounded-md hover:bg-red-50"
                    >
                        Cancel
                    </button>
                )}
            </div>
            {isCancelled && (
                <p className="text-red-700">
                    Cancelled {fmtDate(payment.cancelled_at)} by {payment.cancelled_by_name || '—'}: {payment.cancel_reason}
                </p>
            )}

            {cancelling && (
                <div className="mt-1.5 flex flex-wrap items-center gap-2">
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
                        className="px-2.5 py-1 text-gray-600 border border-gray-300 rounded-md hover:bg-white"
                    >
                        Keep
                    </button>
                    {cancel.error && <span className="w-full text-red-600">{cancel.error.message}</span>}
                </div>
            )}
        </li>
    )
}

export default function PaymentList({ payments, invoiceId, canManage }) {
    if (payments.length === 0) {
        return <p className="text-xs text-gray-400 italic">No payments recorded yet.</p>
    }
    return (
        <ul className="divide-y divide-gray-100">
            {payments.map(p => (
                <PaymentRow key={p.id} payment={p} invoiceId={invoiceId} canManage={canManage} />
            ))}
        </ul>
    )
}
