import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useRefurbishmentInvoiceLines } from '../../hooks/useScrap'
import { usePurchaseInvoiceForm } from '../../hooks/usePurchaseInvoiceForm'
import { refurbishmentSource } from '../../utils/refurbishment'
import { invoiceTotal as calcInvoiceTotal } from '../../lib/invoiceDiscount'
import { PurchaseInvoiceModal, PurchaseInvoiceFields, InvoiceTotal } from './PurchaseInvoiceShared'

const SOURCE_BADGE = {
    job_card: 'bg-blue-50 text-blue-700',
    audit: 'bg-violet-50 text-violet-700',
    not_in_scrap: 'bg-amber-100 text-amber-800',
    unknown: 'bg-gray-100 text-gray-500',
}

const fmtQty = n => String(Number(n))
const fmtMoney = n => Number(n ?? 0).toFixed(2)

/**
 * Edit a refurbishment invoice (MAIN-130). Its lines moved scrap into stock at its
 * workshop when it was recorded, so they and the workshop are shown, not edited — the
 * database refuses adding, changing or removing a line, and moving the workshop. What
 * every purchase invoice shares (PurchaseInvoiceShared) is edited as on a purchase.
 */
export default function EditRefurbishmentModal({ invoice, onClose }) {
    const form = usePurchaseInvoiceForm(invoice)
    const { data: lines, isLoading } = useRefurbishmentInvoiceLines(invoice.id)
    const [error, setError] = useState(null)

    const total = calcInvoiceTotal(lines || [])
    const amountProblem = form.amountError(lines || [])

    async function handleSubmit(e) {
        e.preventDefault()
        setError(null)
        form.revealErrors()

        const problem = form.sharedError(lines)
        if (problem) {
            setError(problem)
            return
        }

        try {
            // The lines go back exactly as they are; save_purchase_invoice keeps them.
            await form.save({ locationId: invoice.location_id, lines })
            onClose()
        } catch (err) {
            setError(err.message)
        }
    }

    const workshop = invoice.location
        ? (invoice.location.address ? `${invoice.location.name} — ${invoice.location.address}` : invoice.location.name)
        : '—'

    return (
        <PurchaseInvoiceModal
            title={form.isFinanceRole ? 'Refurbishment' : 'Edit Refurbishment'}
            form={form}
            loading={isLoading || !lines}
            error={error}
            onClose={onClose}
            onSubmit={handleSubmit}
            footer={<InvoiceTotal total={total} amountProblem={amountProblem} />}
        >
            <PurchaseInvoiceFields
                form={form}
                workshop={<>
                    <label className="block text-xs font-medium text-gray-600 mb-1">Inward to Workshop</label>
                    <p className="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-gray-50 text-gray-700">{workshop}</p>
                </>}
            />

            <div>
                <h3 className="text-sm font-semibold text-gray-700 mb-1">Refurbished Parts</h3>
                <p className="text-xs text-gray-500 mb-3">
                    These moved scrap into stock at this workshop when the refurbishment was recorded, so they cannot be changed.
                </p>
                <div className="overflow-x-auto border border-gray-200 rounded-lg">
                    <table className="min-w-full text-sm">
                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                            <tr>
                                <th className="px-3 py-2 text-left">Part</th>
                                <th className="px-3 py-2 text-left">Scrap source</th>
                                <th className="px-3 py-2 text-right">Qty</th>
                                <th className="px-3 py-2 text-right">Unit price</th>
                                <th className="px-3 py-2 text-right">GST</th>
                                <th className="px-3 py-2 text-right">Line total</th>
                                <th className="px-3 py-2 text-left">Comment</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100">
                            {(lines ?? []).map(line => {
                                const refurb = line.refurbishment
                                const source = refurbishmentSource(refurb)
                                return (
                                    <tr key={line.id} className="align-top">
                                        <td className="px-3 py-2">
                                            <div className="text-gray-500 text-xs">
                                                {refurb?.original?.name ?? '—'}
                                                {refurb?.original?.part_number && (
                                                    <span className="font-mono ml-1">({refurb.original.part_number})</span>
                                                )}
                                            </div>
                                            <div className="text-gray-900">→ {line.part?.name}</div>
                                        </td>
                                        <td className="px-3 py-2">
                                            <span className={`px-2 py-0.5 rounded-full text-xs whitespace-nowrap ${SOURCE_BADGE[source.kind]}`}>
                                                {source.kind === 'job_card' ? (
                                                    <Link to={`/job-cards/${source.jobCardNumber}`} className="hover:underline">
                                                        {source.label}
                                                    </Link>
                                                ) : source.label}
                                            </span>
                                        </td>
                                        <td className="px-3 py-2 text-right text-gray-700 whitespace-nowrap">
                                            {fmtQty(line.quantity)} {line.part?.unit}
                                        </td>
                                        <td className="px-3 py-2 text-right text-gray-700">{fmtMoney(line.unit_price)}</td>
                                        <td className="px-3 py-2 text-right text-gray-700">{Number(line.gst_rate) || 0}%</td>
                                        <td className="px-3 py-2 text-right text-gray-900 font-medium">{fmtMoney(line.line_total)}</td>
                                        <td className="px-3 py-2 text-gray-600 text-xs">{refurb?.comment || '—'}</td>
                                    </tr>
                                )
                            })}
                        </tbody>
                    </table>
                </div>
            </div>
        </PurchaseInvoiceModal>
    )
}
