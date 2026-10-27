import { useInvoicePayments } from '../../hooks/useOutsourceInvoices'
import { invoiceSettlement } from '../../utils/settlement'
import RecordPaymentForm from './RecordPaymentForm'
import PaymentList from './PaymentList'
import { fmtPaise } from './format'

/**
 * The strip under an expanded invoice row (MAIN-98): its payments, one per line,
 * and — for finance and super_admin — Cancel on each active payment and a line for
 * entering the next one. Anyone can open it to see where an invoice stands.
 */
export default function PaymentStrip({ invoice, canManage }) {
    const { data: payments = [], isLoading } = useInvoicePayments(invoice.id)
    const { balance } = invoiceSettlement(invoice, payments)

    if (isLoading) return <p className="text-xs text-gray-400">Loading payments…</p>

    return (
        <div className="space-y-3">
            <PaymentList payments={payments} invoiceId={invoice.id} canManage={canManage} />
            {canManage && balance > 0 && (
                // Remounted after each payment so the next entry starts from the new balance.
                <div className="pt-2 border-t border-gray-200">
                    <RecordPaymentForm
                        key={payments.length}
                        invoiceId={invoice.id}
                        balancePaise={balance}
                    />
                </div>
            )}
            {balance <= 0 && payments.some(p => p.status !== 'Cancelled') && (
                <p className={`text-xs ${balance < 0 ? 'text-red-600 font-medium' : 'text-green-700'}`}>
                    {balance < 0 ? `Overpaid by ${fmtPaise(-balance)}` : 'Fully settled'}
                </p>
            )}
        </div>
    )
}
