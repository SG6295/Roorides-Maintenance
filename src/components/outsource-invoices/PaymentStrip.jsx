import { useInvoicePayments } from '../../hooks/useOutsourceInvoices'
import { invoiceSettlement } from '../../utils/settlement'
import RecordPaymentForm from './RecordPaymentForm'
import PaymentList from './PaymentList'
import { fmtPaise } from './format'

/**
 * The strip under an expanded invoice row (MAIN-98): its payments as a small table,
 * and — for finance and super_admin — Cancel on each active payment and a line for
 * entering the next one. Anyone can open it to see where an invoice stands.
 */
export default function PaymentStrip({ invoice, canManage }) {
    const { data: payments = [], isLoading } = useInvoicePayments(invoice.id)
    const { balance } = invoiceSettlement(invoice, payments)

    return (
        <div className="rounded-lg border border-blue-200 border-l-4 border-l-blue-500 bg-blue-50 px-4 py-3 space-y-3">
            <div>
                <h4 className="text-xs font-semibold text-gray-800 uppercase tracking-wide mb-1.5">
                    Payments — Invoice #{invoice.invoice_no || '—'}
                </h4>
                {isLoading
                    ? <p className="text-xs text-gray-600">Loading payments…</p>
                    : (
                        <div className="overflow-x-auto">
                            <PaymentList payments={payments} invoiceId={invoice.id} canManage={canManage} />
                        </div>
                    )}
            </div>

            {!isLoading && canManage && balance > 0 && (
                <div className="pt-3 border-t border-blue-200">
                    <h4 className="text-xs font-semibold text-gray-800 uppercase tracking-wide mb-1.5">Record a payment</h4>
                    {/* Remounted after each payment so the next entry starts from the new balance. */}
                    <RecordPaymentForm
                        key={payments.length}
                        invoiceId={invoice.id}
                        balancePaise={balance}
                    />
                </div>
            )}

            {!isLoading && balance <= 0 && payments.some(p => p.status !== 'Cancelled') && (
                <p className={`text-xs font-medium ${balance < 0 ? 'text-red-700' : 'text-green-800'}`}>
                    {balance < 0 ? `Overpaid by ${fmtPaise(-balance)}` : 'Fully settled'}
                </p>
            )}
        </div>
    )
}
