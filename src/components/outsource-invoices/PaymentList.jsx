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
        <li className="py-3 text-sm">
            <div className="flex items-start justify-between gap-3">
                <div className={isCancelled ? 'line-through text-gray-400' : 'text-gray-900'}>
                    <p className="font-medium">
                        {fmtDate(payment.paid_on)} · {fmtMoney(payment.amount_paid)}
                        {Number(payment.tds_amount) > 0 && <> + TDS {fmtMoney(payment.tds_amount)}</>}
                        {Number(payment.round_off) > 0 && <> + round-off {fmtMoney(payment.round_off)}</>}
                    </p>
                    <p className={`text-xs ${isCancelled ? '' : 'text-gray-600'}`}>
                        {payment.ledger} · {payment.payment_method}
                        {payment.bank && <> · {payment.bank}</>}
                        {payment.utr && <> · UTR {payment.utr}</>}
                    </p>
                </div>
                {canManage && !isCancelled && !cancelling && (
                    <button
                        type="button"
                        onClick={() => setCancelling(true)}
                        className="shrink-0 text-xs px-2 py-1 text-red-600 border border-red-200 rounded-lg hover:bg-red-50"
                    >
                        Cancel payment
                    </button>
                )}
            </div>
            <p className="text-xs text-gray-500 mt-0.5">Recorded by {payment.recorded_by_name || '—'}</p>
            {isCancelled && (
                <p className="text-xs text-red-700 mt-0.5">
                    Cancelled {fmtDate(payment.cancelled_at)} by {payment.cancelled_by_name || '—'}: {payment.cancel_reason}
                </p>
            )}

            {cancelling && (
                <div className="mt-2 space-y-2 rounded-lg border border-red-100 bg-red-50/40 p-3">
                    <label className="block text-xs font-medium text-gray-700">
                        Why is this payment being cancelled?
                    </label>
                    <textarea
                        rows={2}
                        value={reason}
                        onChange={e => setReason(e.target.value)}
                        placeholder="e.g. UTR failed, refund received 28 Oct"
                        className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-red-400"
                    />
                    {cancel.error && <p className="text-xs text-red-600">{cancel.error.message}</p>}
                    <div className="flex justify-end gap-2">
                        <button
                            type="button"
                            onClick={() => { setCancelling(false); setReason('') }}
                            className="text-xs px-3 py-1.5 text-gray-600 border border-gray-300 rounded-lg hover:bg-white"
                        >
                            Keep payment
                        </button>
                        <button
                            type="button"
                            onClick={confirm}
                            disabled={!reason.trim() || cancel.isPending}
                            className="text-xs px-3 py-1.5 bg-red-600 text-white rounded-lg hover:bg-red-700 disabled:opacity-50"
                        >
                            {cancel.isPending ? 'Cancelling…' : 'Cancel payment'}
                        </button>
                    </div>
                </div>
            )}
        </li>
    )
}

export default function PaymentList({ payments, invoiceId, canManage }) {
    if (payments.length === 0) {
        return <p className="text-sm text-gray-400 italic">No payments recorded yet.</p>
    }
    return (
        <ul className="divide-y divide-gray-100">
            {payments.map(p => (
                <PaymentRow key={p.id} payment={p} invoiceId={invoiceId} canManage={canManage} />
            ))}
        </ul>
    )
}
