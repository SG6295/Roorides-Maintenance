import { createPortal } from 'react-dom'
import { XMarkIcon, ArrowRightIcon } from '@heroicons/react/24/outline'
import { companyLabel } from '../../constants/vehicleCompanies'
import { rupees } from '../../utils/jobCardValue'

/**
 * Confirms a spare transfer (MAIN-159). A job card uses its vehicle's company's stock;
 * what that company lacks can come from the other company only through a transfer, which
 * is posted to both company ledgers at first-in-first-out cost incl. GST. Nothing is
 * saved until Confirm transfer — and then only if the cost is still the one shown.
 */
export default function TransferSpareModal({ quote, onConfirm, onCancel, isSaving }) {
    const qty = n => `${Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 })} ${quote.unit || ''}`.trim()
    const total = quote.ownQuantity + quote.quantity

    return createPortal(
        <div className="fixed inset-0 z-50 overflow-y-auto">
            <div className="fixed inset-0 bg-black bg-opacity-50" onClick={isSaving ? undefined : onCancel} />

            <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
                <div role="dialog" aria-labelledby="transfer-spare-title" className="relative bg-white rounded-t-2xl sm:rounded-2xl shadow-xl w-full max-w-lg">
                    <div className="flex items-center justify-between p-5 border-b">
                        <h3 id="transfer-spare-title" className="text-lg font-semibold text-gray-900">Transfer spare</h3>
                        <button type="button" onClick={onCancel} disabled={isSaving} aria-label="Close" className="text-gray-500 hover:text-gray-600 p-1">
                            <XMarkIcon className="w-6 h-6" />
                        </button>
                    </div>

                    <div className="p-5 space-y-4 text-sm text-gray-700">
                        {quote.changed && (
                            <p className="rounded-lg bg-amber-50 border border-amber-200 text-amber-800 px-3 py-2">
                                The stock or its prices changed since you opened this, so the figures below are new. Check them and confirm again.
                            </p>
                        )}

                        <p>
                            <span className="font-medium text-gray-900">{quote.partName}</span> × {qty(total)} on {quote.vehicle}
                            {quote.jobCardNumber != null && <> (job card {quote.jobCardNumber})</>}.{' '}
                            {quote.ownQuantity > 0
                                ? <>{companyLabel(quote.toCompany)} has {qty(quote.ownQuantity)} at this workshop; the other {qty(quote.quantity)} must be transferred.</>
                                : <>{companyLabel(quote.toCompany)} has none at this workshop, so all {qty(quote.quantity)} must be transferred.</>}
                        </p>

                        <div className="flex items-center gap-3 rounded-lg border border-gray-200 bg-gray-50 px-4 py-3">
                            <div className="flex-1">
                                <p className="text-xs text-gray-500">From</p>
                                <p className="font-medium text-gray-900">{companyLabel(quote.fromCompany)}</p>
                            </div>
                            <ArrowRightIcon className="w-5 h-5 text-gray-400 shrink-0" />
                            <div className="flex-1">
                                <p className="text-xs text-gray-500">To</p>
                                <p className="font-medium text-gray-900">{companyLabel(quote.toCompany)}</p>
                            </div>
                        </div>

                        <table className="w-full text-sm">
                            <thead>
                                <tr className="text-xs text-gray-500">
                                    <th className="text-left font-medium pb-1">GST %</th>
                                    <th className="text-right font-medium pb-1">Before GST</th>
                                    <th className="text-right font-medium pb-1">GST</th>
                                    <th className="text-right font-medium pb-1">Incl. GST</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100 tabular-nums">
                                {quote.gstBreakdown.map(r => (
                                    <tr key={r.rate}>
                                        <td className="py-1">{r.rate}%</td>
                                        <td className="py-1 text-right">{rupees(r.beforeGst)}</td>
                                        <td className="py-1 text-right">{rupees(r.gst)}</td>
                                        <td className="py-1 text-right">{rupees(r.inclGst)}</td>
                                    </tr>
                                ))}
                            </tbody>
                            <tfoot>
                                <tr className="border-t border-gray-200 font-semibold text-gray-900 tabular-nums">
                                    <td className="pt-2">Transfer · {qty(quote.quantity)}</td>
                                    <td />
                                    <td className="pt-2 text-right">{rupees(quote.gst)}</td>
                                    <td className="pt-2 text-right">{rupees(quote.amount)}</td>
                                </tr>
                            </tfoot>
                        </table>

                        <p className="text-xs text-gray-500">
                            First-in-first-out cost of the stock held by {companyLabel(quote.fromCompany)}, incl. GST at the rate it was bought at.
                            It is posted to both company ledgers: the spending of {companyLabel(quote.toCompany)} goes up by it, and it owes it to {companyLabel(quote.fromCompany)}.
                            Removing the spare later reverses the transfer.
                        </p>
                    </div>

                    <div className="flex justify-end gap-3 p-5 border-t">
                        <button
                            type="button"
                            onClick={onCancel}
                            disabled={isSaving}
                            className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50"
                        >
                            Cancel
                        </button>
                        <button
                            type="button"
                            onClick={onConfirm}
                            disabled={isSaving}
                            className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {isSaving ? 'Adding…' : 'Confirm transfer'}
                        </button>
                    </div>
                </div>
            </div>
        </div>,
        document.body,
    )
}
