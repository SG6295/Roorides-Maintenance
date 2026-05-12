import { useState } from 'react'
import { format, parseISO } from 'date-fns'
import * as XLSX from 'xlsx'
import { ChevronDownIcon, ChevronUpIcon, ArrowDownTrayIcon, MagnifyingGlassIcon } from '@heroicons/react/24/outline'
import { TicketListSkeleton } from '../shared/LoadingSkeleton'
import { useScrapDisposals, useScrapDisposalItems } from '../../hooks/useScrap'

const PAYMENT_LABEL = {
    cash:          'Cash',
    upi:           'UPI',
    bank_transfer: 'Bank Transfer',
    cheque:        'Cheque',
    other:         'Other',
}

function DisposalRow({ disposal }) {
    const [expanded, setExpanded] = useState(false)
    const { data: items = [], isLoading } = useScrapDisposalItems(expanded ? disposal.id : null)

    return (
        <>
            <tr
                className="hover:bg-gray-50 cursor-pointer"
                onClick={() => setExpanded(e => !e)}
            >
                <td className="px-4 py-3 text-gray-700 text-sm">
                    {disposal.disposal_date ? format(parseISO(disposal.disposal_date), 'dd MMM yyyy') : '—'}
                </td>
                <td className="px-4 py-3 font-medium text-gray-900 text-sm">{disposal.buyer_name}</td>
                <td className="px-4 py-3 text-gray-500 text-sm">
                    {PAYMENT_LABEL[disposal.payment_mode] || disposal.payment_mode}
                </td>
                <td className="px-4 py-3 text-right font-semibold text-gray-900 text-sm">
                    ₹{Number(disposal.total_value).toFixed(2)}
                </td>
                <td className="px-4 py-3 text-center text-gray-500 text-sm">{disposal.item_count}</td>
                <td className="px-4 py-3 text-gray-400 text-xs">
                    {disposal.recorded_at ? format(parseISO(disposal.recorded_at), 'dd MMM yyyy') : '—'}
                    {disposal.recorded_by_user?.name ? ` · ${disposal.recorded_by_user.name}` : ''}
                </td>
                <td className="px-4 py-3 text-gray-400">
                    {expanded
                        ? <ChevronUpIcon className="w-4 h-4" />
                        : <ChevronDownIcon className="w-4 h-4" />
                    }
                </td>
            </tr>
            {expanded && (
                <tr>
                    <td colSpan={7} className="px-6 py-4 bg-blue-50 border-b border-blue-100">
                        {isLoading ? (
                            <p className="text-sm text-gray-500">Loading items…</p>
                        ) : (
                            <div className="space-y-3">
                                {(disposal.receipt_photos?.length > 0) && (
                                    <div className="flex flex-wrap gap-2">
                                        {disposal.receipt_photos.map((url, i) => (
                                            <a
                                                key={i}
                                                href={url}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                className="text-xs text-blue-600 hover:underline border border-blue-200 bg-white px-2 py-1 rounded"
                                            >
                                                Receipt photo {i + 1}
                                            </a>
                                        ))}
                                    </div>
                                )}
                                {disposal.payment_reference && (
                                    <p className="text-xs text-gray-600">
                                        Payment ref: <span className="font-mono">{disposal.payment_reference}</span>
                                    </p>
                                )}
                                {disposal.buyer_contact && (
                                    <p className="text-xs text-gray-600">Contact: {disposal.buyer_contact}</p>
                                )}
                                {disposal.notes && (
                                    <p className="text-xs text-gray-600">Notes: {disposal.notes}</p>
                                )}
                                <table className="min-w-full text-xs bg-white rounded border border-gray-200">
                                    <thead>
                                        <tr className="bg-gray-50 text-gray-500 uppercase text-xs">
                                            <th className="px-3 py-2 text-left">Part</th>
                                            <th className="px-3 py-2 text-right">Qty</th>
                                            <th className="px-3 py-2 text-left">Unit</th>
                                            <th className="px-3 py-2 text-right">Value</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-100">
                                        {items.map(item => (
                                            <tr key={item.id}>
                                                <td className="px-3 py-2 text-gray-800">{item.part_name_snapshot}</td>
                                                <td className="px-3 py-2 text-right text-gray-700">{item.quantity_snapshot}</td>
                                                <td className="px-3 py-2 text-gray-500">{item.unit_snapshot}</td>
                                                <td className="px-3 py-2 text-right font-medium text-gray-900">
                                                    ₹{Number(item.value_allocated).toFixed(2)}
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        )}
                    </td>
                </tr>
            )}
        </>
    )
}

export default function SaleHistoryTab() {
    const [filters, setFilters] = useState({ search: '', dateFrom: '', dateTo: '' })
    const { data: disposals = [], isLoading } = useScrapDisposals(filters)

    function exportToExcel() {
        const rows = disposals.map(d => ({
            'Disposal Date':  d.disposal_date,
            'Buyer':          d.buyer_name,
            'Contact':        d.buyer_contact || '',
            'Payment Mode':   PAYMENT_LABEL[d.payment_mode] || d.payment_mode,
            'Payment Ref':    d.payment_reference || '',
            'Total Value':    d.total_value,
            'Items':          d.item_count,
            'Notes':          d.notes || '',
            'Recorded At':    d.recorded_at,
            'Recorded By':    d.recorded_by_user?.name || '',
        }))
        const ws = XLSX.utils.json_to_sheet(rows)
        const wb = XLSX.utils.book_new()
        XLSX.utils.book_append_sheet(wb, ws, 'Sale History')
        XLSX.writeFile(wb, 'scrap-sale-history.xlsx')
    }

    return (
        <div className="space-y-4">
            <div className="bg-white p-4 rounded-lg shadow-sm">
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div className="relative">
                        <input
                            type="text"
                            placeholder="Search buyer or notes…"
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

            <div className="flex justify-end">
                <button
                    onClick={exportToExcel}
                    disabled={disposals.length === 0}
                    className="flex items-center gap-2 px-3 py-1.5 text-sm text-gray-600 border rounded-lg bg-white hover:bg-gray-50 shadow-sm disabled:opacity-40"
                >
                    <ArrowDownTrayIcon className="w-4 h-4" />
                    Export
                </button>
            </div>

            {isLoading ? (
                <TicketListSkeleton />
            ) : disposals.length === 0 ? (
                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                    No disposal records found.
                </div>
            ) : (
                <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-100">
                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                            <tr>
                                <th className="px-4 py-3 text-left">Date</th>
                                <th className="px-4 py-3 text-left">Buyer</th>
                                <th className="px-4 py-3 text-left">Payment</th>
                                <th className="px-4 py-3 text-right">Total Value</th>
                                <th className="px-4 py-3 text-center">Items</th>
                                <th className="px-4 py-3 text-left">Recorded</th>
                                <th className="px-4 py-3 w-8"></th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100">
                            {disposals.map(d => <DisposalRow key={d.id} disposal={d} />)}
                        </tbody>
                    </table>
                    <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                        {disposals.length} record{disposals.length !== 1 ? 's' : ''}
                    </div>
                </div>
            )}
        </div>
    )
}
