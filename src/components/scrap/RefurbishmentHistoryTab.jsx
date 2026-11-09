import { useMemo, useState } from 'react'
import { MagnifyingGlassIcon } from '@heroicons/react/24/outline'
import { formatDate } from '../../utils/datetime'
import { TicketListSkeleton } from '../shared/LoadingSkeleton'
import { useRefurbishments, scrapSourceLabel } from '../../hooks/useScrap'

const rupees = n =>
    `₹${Number(n ?? 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

export default function RefurbishmentHistoryTab() {
    const [filters, setFilters] = useState({ search: '', dateFrom: '', dateTo: '' })
    const { data: rows = [], isLoading } = useRefurbishments({ dateFrom: filters.dateFrom, dateTo: filters.dateTo })

    const visible = useMemo(() => {
        const term = filters.search.trim().toLowerCase()
        if (!term) return rows
        return rows.filter(r =>
            [r.original?.name, r.refurbished?.name, r.line?.invoice?.invoice_number, r.line?.invoice?.supplier_name]
                .some(v => v?.toLowerCase().includes(term))
        )
    }, [rows, filters.search])

    return (
        <div className="space-y-4">
            <div className="bg-white p-4 rounded-lg shadow-sm">
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div className="relative">
                        <input
                            type="text"
                            placeholder="Search part, invoice or vendor…"
                            className="w-full pl-10 pr-4 py-2 border rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                            value={filters.search}
                            onChange={e => setFilters(p => ({ ...p, search: e.target.value }))}
                        />
                        <MagnifyingGlassIcon className="w-4 h-4 text-gray-400 absolute left-3 top-2.5" />
                    </div>
                    <div className="flex items-center gap-2 text-sm text-gray-600">
                        <span className="shrink-0 w-8">From</span>
                        <input
                            type="date"
                            className="border rounded-lg px-3 py-1.5 text-sm flex-1 focus:ring-2 focus:ring-blue-500"
                            value={filters.dateFrom}
                            onChange={e => setFilters(p => ({ ...p, dateFrom: e.target.value }))}
                        />
                    </div>
                    <div className="flex items-center gap-2 text-sm text-gray-600">
                        <span className="shrink-0 w-8">To</span>
                        <input
                            type="date"
                            className="border rounded-lg px-3 py-1.5 text-sm flex-1 focus:ring-2 focus:ring-blue-500"
                            value={filters.dateTo}
                            onChange={e => setFilters(p => ({ ...p, dateTo: e.target.value }))}
                        />
                    </div>
                </div>
            </div>

            {isLoading ? (
                <TicketListSkeleton />
            ) : visible.length === 0 ? (
                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                    No refurbishments found.
                </div>
            ) : (
                <div className="bg-white rounded-lg shadow-sm overflow-x-auto">
                    <table className="min-w-full divide-y divide-gray-100 text-sm">
                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                            <tr>
                                <th className="px-4 py-3 text-left">Refurbished Part</th>
                                <th className="px-4 py-3 text-right">Qty</th>
                                <th className="px-4 py-3 text-right">Cost</th>
                                <th className="px-4 py-3 text-left">Invoice</th>
                                <th className="px-4 py-3 text-left">Workshop</th>
                                <th className="px-4 py-3 text-left">Source</th>
                                <th className="px-4 py-3 text-left">Recorded</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-50">
                            {visible.map(r => {
                                const invoice = r.line?.invoice
                                return (
                                    <tr key={r.id} className="hover:bg-gray-50 align-top">
                                        <td className="px-4 py-3">
                                            <div className="font-medium text-gray-900">{r.refurbished?.name}</div>
                                            <div className="text-xs text-gray-400">from {r.original?.name}</div>
                                        </td>
                                        <td className="px-4 py-3 text-right text-gray-700">
                                            {Number(r.quantity)} {r.original?.unit}
                                        </td>
                                        <td className="px-4 py-3 text-right text-gray-700">{rupees(r.line?.line_total)}</td>
                                        <td className="px-4 py-3">
                                            {invoice?.invoice_file_url ? (
                                                <a
                                                    href={invoice.invoice_file_url}
                                                    target="_blank"
                                                    rel="noopener noreferrer"
                                                    className="text-blue-600 hover:underline"
                                                >
                                                    {invoice.invoice_number}
                                                </a>
                                            ) : (
                                                <span className="text-gray-700">{invoice?.invoice_number}</span>
                                            )}
                                            <div className="text-xs text-gray-400">
                                                {invoice?.supplier_name} · {formatDate(invoice?.invoice_date)}
                                            </div>
                                        </td>
                                        <td className="px-4 py-3 text-gray-700">{invoice?.location?.name || '—'}</td>
                                        <td className="px-4 py-3">
                                            {r.scrap_inventory_id ? (
                                                <span className="text-gray-500 font-mono text-xs">{scrapSourceLabel(r.scrap)}</span>
                                            ) : (
                                                <>
                                                    <span className="px-2 py-0.5 text-xs rounded-full bg-amber-100 text-amber-800 whitespace-nowrap">
                                                        Scrap source details missing
                                                    </span>
                                                    <div className="text-xs text-gray-500 mt-1">{r.comment}</div>
                                                </>
                                            )}
                                        </td>
                                        <td className="px-4 py-3 text-gray-400 text-xs">
                                            {formatDate(r.created_at)}
                                            {r.created_by_user?.name ? ` · ${r.created_by_user.name}` : ''}
                                        </td>
                                    </tr>
                                )
                            })}
                        </tbody>
                    </table>
                    <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                        {visible.length} line{visible.length !== 1 ? 's' : ''}
                    </div>
                </div>
            )}
        </div>
    )
}
