import { Link } from 'react-router-dom'
import { useJobCardBatchLines } from '../../hooks/useBatchServices'
import { workTypeLabel } from '../../constants/batchWorkTypes'
import { fmtMoney, fmtDate } from '../outsource-invoices/format'
import { formatBatchNumber, batchPath } from '../../utils/batchNumber'

/**
 * The multi-vehicle invoice lines linked to an outsourced job card (MAIN-112), shown
 * beside the card's own invoice. The same work can end up on both — the card needs its
 * own invoice to complete — so they sit side by side for the exec and finance to compare.
 *
 * Only exec, super_admin and finance can read multi-vehicle invoices; for anyone else
 * (`enabled` false) this renders nothing.
 */
export default function LinkedBatchInvoices({ jobCardId, enabled }) {
    const { data: lines = [] } = useJobCardBatchLines(jobCardId, { enabled })
    if (!enabled || lines.length === 0) return null

    return (
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
            <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-1">
                Multi-vehicle invoices
            </h2>
            <p className="text-xs text-gray-500 mb-3">
                Work on this job card that was also billed on a multi-vehicle invoice.
            </p>
            <ul className="divide-y divide-gray-100">
                {lines.map(line => (
                    <li key={line.id} className="py-2 flex flex-wrap items-center justify-between gap-2 text-sm">
                        <div className="text-gray-800">
                            <span className="font-medium">{formatBatchNumber(line.batch.batch_number)}</span>
                            <span className="text-gray-500"> · Invoice {line.batch.invoice?.invoice_no || '—'}</span>
                            <span className="text-gray-500">
                                {' · '}{workTypeLabel(line)}
                                {' · '}{line.quantity} × {fmtMoney(line.rate)} = {fmtMoney(line.amount)}
                                {line.batch.invoice?.date_of_activity && ` · ${fmtDate(line.batch.invoice.date_of_activity)}`}
                            </span>
                        </div>
                        <div className="flex items-center gap-3">
                            <a
                                href={line.batch.invoice_url}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="text-sm text-blue-600 hover:underline"
                            >
                                View invoice →
                            </a>
                            <Link to={batchPath(line.batch.batch_number)} className="text-sm text-blue-600 hover:underline">
                                Open {formatBatchNumber(line.batch.batch_number)}
                            </Link>
                        </div>
                    </li>
                ))}
            </ul>
        </div>
    )
}
