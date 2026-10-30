import InvoiceHistory from './InvoiceHistory'
import { workTypeSummary, vehicleCountLabel } from '../../constants/batchWorkTypes'
import { formatBatchNumber } from '../../utils/batchNumber'

/**
 * The invoice's "who changed what" history, and nothing else (MAIN-98). Details,
 * amounts and payments are in the table and its expanded row.
 */
export default function HistoryDrawer({ invoice, onClose }) {
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
                            History — Invoice #{invoice.invoice_no || invoice.id.slice(0, 8)}
                        </h2>
                        <p className="text-xs text-gray-500">
                            {invoice.batch_service
                                // A multi-vehicle invoice (MAIN-99) has a batch in place of a job card.
                                ? `${formatBatchNumber(invoice.batch_service.batch_number)} · ${workTypeSummary(invoice.batch_service.vehicles)} · ${vehicleCountLabel(invoice.batch_service.vehicles)} · ${invoice.batch_service.supplier?.entity_name || '—'}`
                                : `Job card #${invoice.job_card?.job_card_number} · ${invoice.job_card?.vehicle_number || '—'} · ${invoice.job_card?.supplier?.entity_name || '—'}`}
                        </p>
                    </div>
                    <button
                        onClick={onClose}
                        className="text-gray-400 hover:text-gray-600 text-2xl leading-none"
                    >
                        &times;
                    </button>
                </div>
                <div className="px-5 py-4">
                    <InvoiceHistory invoiceId={invoice.id} />
                </div>
            </div>
        </div>
    )
}
