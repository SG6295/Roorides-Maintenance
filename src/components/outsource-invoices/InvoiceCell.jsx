import { Link } from 'react-router-dom'
import FinanceStatusCell from './FinanceStatusCell'
import RemarkCell from './RemarkCell'
import InvoiceFileLink from './InvoiceFileLink'
import { fmtMoney, fmtPaise, fmtDate, MAINTENANCE_STATUS_COLORS } from './format'
import { workTypeSummary, vehicleCountLabel } from '../../constants/batchWorkTypes'
import { formatBatchNumber, batchPath } from '../../utils/batchNumber'
import { purchaseInvoicePath } from '../../utils/purchaseInvoice'

/**
 * One cell of the Outsource Invoices list (MAIN-98), by column key — the column
 * list itself is in columns.js. `invoice` is a row from enrichInvoice().
 */
export default function InvoiceCell({ columnKey, invoice: inv, canEdit }) {
    // A multi-vehicle invoice (MAIN-99) has a batch in place of a job card, and a
    // purchase or refurbishment (MAIN-123, MAIN-129) its purchase invoice.
    const batch = inv.batch_service
    const purchase = inv.purchase_invoice
    const owner = batch ?? purchase ?? inv.job_card

    switch (columnKey) {
        case 'job_card':
            if (purchase) {
                return (
                    <Link to={purchaseInvoicePath(purchase.id)} className="text-blue-600 hover:underline font-medium">
                        {inv.refurbishment ? 'Refurbishment' : 'Purchase'}
                    </Link>
                )
            }
            return batch ? (
                <span className="inline-flex items-center gap-1.5">
                    <Link to={batchPath(batch.batch_number)} className="text-blue-600 hover:underline font-medium" title={workTypeSummary(batch.vehicles)}>
                        {formatBatchNumber(batch.batch_number)}
                    </Link>
                    {inv.cancelled && (
                        <span className="px-1.5 py-0.5 rounded text-xs font-semibold bg-red-100 text-red-700" title={batch.cancel_reason}>
                            Cancelled
                        </span>
                    )}
                </span>
            ) : (
                <Link to={`/job-cards/${inv.job_card?.job_card_number}`} className="text-blue-600 hover:underline font-medium">
                    #{inv.job_card?.job_card_number}
                </Link>
            )
        case 'vehicle':
            if (purchase) return '—'
            return batch
                ? vehicleCountLabel(batch.vehicles)
                : inv.job_card?.vehicle_number || '—'
        case 'supplier':      return owner?.supplier?.entity_name || '—'
        case 'invoice_no':    return <span className="font-mono">{inv.invoice_no || '—'}</span>
        case 'invoice_link':  return <InvoiceFileLink url={purchase ? purchase.invoice_file_url : owner?.invoice_url} />
        case 'activity_date': return fmtDate(inv.date_of_activity)
        // A batch or refurbishment is complete when it is saved.
        case 'completed':     return fmtDate(batch || purchase ? inv.created_at : inv.job_card?.completed_at)
        case 'submitted':     return fmtDate(inv.submitted_on)
        case 'paid_by':       return inv.paid_by || '—'
        case 'invoice_value': return fmtMoney(inv.invoice_value)
        case 'discount':      return fmtPaise(inv.discount)
        case 'approved':      return fmtMoney(inv.approved_amount)
        case 'advance':       return fmtMoney(inv.advance_amount)
        case 'payable':       return <span className="font-medium">{fmtPaise(inv.payable)}</span>
        case 'maintenance_status':
            return (
                <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${MAINTENANCE_STATUS_COLORS[inv.maintenance_payment_status] ?? 'bg-gray-100 text-gray-600'}`}>
                    {inv.maintenance_payment_status || '—'}
                </span>
            )
        case 'finance_status': return <FinanceStatusCell invoice={inv} canEdit={canEdit} />
        case 'finance_remark': return <RemarkCell invoice={inv} canEdit={canEdit} />
        case 'pay_by':         return fmtDate(inv.payby_date)
        default:
            return null
    }
}
