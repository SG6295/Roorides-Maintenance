import { useState } from 'react'
import { formatDate } from '../../utils/datetime'
import * as XLSX from 'xlsx'
import { ChevronDownIcon, ChevronUpIcon, ArrowDownTrayIcon, MagnifyingGlassIcon } from '@heroicons/react/24/outline'
import { TicketListSkeleton } from '../shared/LoadingSkeleton'
import { useScrapWriteoffs, useScrapWriteoffItems } from '../../hooks/useScrap'
import { useDebouncedValue } from '../../hooks/useDebouncedValue'

const REASON_LABEL = {
    lost:                   'Lost',
    damaged_unsaleable:     'Damaged / Unsaleable',
    hazmat_disposal:        'Hazmat Disposal',
    stocktake_adjustment:   'Stocktake Adjustment',
    donated:                'Donated',
    other:                  'Other',
}

function WriteoffRow({ writeoff }) {
    const [expanded, setExpanded] = useState(false)
    const { data: items = [], isLoading } = useScrapWriteoffItems(expanded ? writeoff.id : null)

    return (
        <>
            <tr
                className="hover:bg-gray-50 cursor-pointer"
                onClick={() => setExpanded(e => !e)}
            >
                <td className="px-4 py-3 text-gray-700 text-sm">
                    {formatDate(writeoff.writeoff_date)}
                </td>
                <td className="px-4 py-3 text-gray-700 text-sm">
                    {REASON_LABEL[writeoff.reason] || writeoff.reason}
                </td>
                <td className="px-4 py-3 text-gray-600 text-sm max-w-xs truncate">
                    {writeoff.description}
                </td>
                <td className="px-4 py-3 text-center text-gray-500 text-sm">{writeoff.item_count}</td>
                <td className="px-4 py-3 text-gray-400 text-xs">
                    {formatDate(writeoff.recorded_at)}
                    {writeoff.recorded_by_user?.name ? ` · ${writeoff.recorded_by_user.name}` : ''}
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
                    <td colSpan={6} className="px-6 py-4 bg-orange-50 border-b border-orange-100">
                        {isLoading ? (
                            <p className="text-sm text-gray-500">Loading items…</p>
                        ) : (
                            <div className="space-y-3">
                                {(writeoff.evidence_photos?.length > 0) && (
                                    <div className="flex flex-wrap gap-2">
                                        {writeoff.evidence_photos.map((url, i) => (
                                            <a
                                                key={i}
                                                href={url}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                className="text-xs text-orange-700 hover:underline border border-orange-200 bg-white px-2 py-1 rounded"
                                            >
                                                Evidence photo {i + 1}
                                            </a>
                                        ))}
                                    </div>
                                )}
                                {writeoff.notes && (
                                    <p className="text-xs text-gray-600">Notes: {writeoff.notes}</p>
                                )}
                                <table className="min-w-full text-xs bg-white rounded border border-gray-200">
                                    <thead>
                                        <tr className="bg-gray-50 text-gray-500 uppercase text-xs">
                                            <th className="px-3 py-2 text-left">Part</th>
                                            <th className="px-3 py-2 text-right">Qty</th>
                                            <th className="px-3 py-2 text-left">Unit</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-100">
                                        {items.map(item => (
                                            <tr key={item.id}>
                                                <td className="px-3 py-2 text-gray-800">{item.part_name_snapshot}</td>
                                                <td className="px-3 py-2 text-right text-gray-700">{item.quantity_snapshot}</td>
                                                <td className="px-3 py-2 text-gray-500">{item.unit_snapshot}</td>
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

export default function WriteoffHistoryTab() {
    const [filters, setFilters] = useState({ search: '', dateFrom: '', dateTo: '' })
    const search = useDebouncedValue(filters.search)
    const { data: writeoffs = [], isLoading } = useScrapWriteoffs({ ...filters, search })

    function exportToExcel() {
        const rows = writeoffs.map(w => ({
            'Write-off Date': w.writeoff_date,
            'Reason':         REASON_LABEL[w.reason] || w.reason,
            'Description':    w.description,
            'Items':          w.item_count,
            'Notes':          w.notes || '',
            'Recorded At':    w.recorded_at,
            'Recorded By':    w.recorded_by_user?.name || '',
        }))
        const ws = XLSX.utils.json_to_sheet(rows)
        const wb = XLSX.utils.book_new()
        XLSX.utils.book_append_sheet(wb, ws, 'Write-off History')
        XLSX.writeFile(wb, 'scrap-writeoff-history.xlsx')
    }

    return (
        <div className="space-y-4">
            <div className="bg-white p-4 rounded-lg shadow-sm">
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div className="relative">
                        <input
                            type="text"
                            placeholder="Search description or notes…"
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
                    disabled={writeoffs.length === 0}
                    className="flex items-center gap-2 px-3 py-1.5 text-sm text-gray-600 border rounded-lg bg-white hover:bg-gray-50 shadow-sm disabled:opacity-40"
                >
                    <ArrowDownTrayIcon className="w-4 h-4" />
                    Export
                </button>
            </div>

            {isLoading ? (
                <TicketListSkeleton />
            ) : writeoffs.length === 0 ? (
                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                    No write-off records found.
                </div>
            ) : (
                <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-100">
                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                            <tr>
                                <th className="px-4 py-3 text-left">Date</th>
                                <th className="px-4 py-3 text-left">Reason</th>
                                <th className="px-4 py-3 text-left">Description</th>
                                <th className="px-4 py-3 text-center">Items</th>
                                <th className="px-4 py-3 text-left">Recorded</th>
                                <th className="px-4 py-3 w-8"></th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100">
                            {writeoffs.map(w => <WriteoffRow key={w.id} writeoff={w} />)}
                        </tbody>
                    </table>
                    <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                        {writeoffs.length} record{writeoffs.length !== 1 ? 's' : ''}
                    </div>
                </div>
            )}
        </div>
    )
}
