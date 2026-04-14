import { useState } from 'react'
import { format, parseISO } from 'date-fns'
import { Link } from 'react-router-dom'
import Navigation from '../components/shared/Navigation'
import { TicketListSkeleton } from '../components/shared/LoadingSkeleton'
import PurchaseModal from '../components/inventory/PurchaseModal'
import BulkUploadModal from '../components/inventory/BulkUploadModal'
import EditPartModal from '../components/inventory/EditPartModal'
import { useParts, usePurchaseInvoices, usePurchaseInvoiceItems, usePartConsumption } from '../hooks/useInventory'
import {
    MagnifyingGlassIcon,
    PlusIcon,
    ArrowUpTrayIcon,
    ChevronDownIcon,
    ChevronUpIcon,
    PencilSquareIcon,
} from '@heroicons/react/24/outline'

// ── Parts Tab ─────────────────────────────────────────────────────────────────
function PartsTable() {
    const [filters, setFilters] = useState({ search: '', stockStatus: '' })
    const { data: parts = [], isLoading } = useParts(filters)
    const [editingPart, setEditingPart] = useState(null)

    function stockBadge(qty) {
        if (qty <= 0) return <span className="px-2 py-0.5 text-xs rounded-full bg-red-100 text-red-700">Out of stock</span>
        if (qty <= 5) return <span className="px-2 py-0.5 text-xs rounded-full bg-yellow-100 text-yellow-700">Low ({qty})</span>
        return <span className="px-2 py-0.5 text-xs rounded-full bg-green-100 text-green-700">{qty}</span>
    }

    return (
        <div className="space-y-4">
            {/* Filters */}
            <div className="bg-white p-4 rounded-lg shadow-sm">
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div className="relative sm:col-span-2">
                        <input
                            type="text"
                            placeholder="Search by part name or part number…"
                            className="w-full pl-10 pr-4 py-2 border rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                            value={filters.search}
                            onChange={e => setFilters(p => ({ ...p, search: e.target.value }))}
                        />
                        <MagnifyingGlassIcon className="w-4 h-4 text-gray-400 absolute left-3 top-2.5" />
                    </div>
                    <select
                        className="border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                        value={filters.stockStatus}
                        onChange={e => setFilters(p => ({ ...p, stockStatus: e.target.value }))}
                    >
                        <option value="">All Stock Levels</option>
                        <option value="low">Low / Out (≤ 5)</option>
                        <option value="out">Out of Stock (0)</option>
                    </select>
                </div>
            </div>

            {isLoading ? (
                <TicketListSkeleton />
            ) : parts.length === 0 ? (
                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                    No parts found. Record a purchase to add inventory.
                </div>
            ) : (
                <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-100 text-sm">
                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                            <tr>
                                <th className="px-4 py-3 text-left">Part Name</th>
                                <th className="px-4 py-3 text-left">Part Number</th>
                                <th className="px-4 py-3 text-left">Unit</th>
                                <th className="px-4 py-3 text-right">In Stock</th>
                                <th className="px-4 py-3 w-10"></th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-50">
                            {parts.map(part => (
                                <tr key={part.id} className="hover:bg-gray-50 group">
                                    <td className="px-4 py-3 font-medium text-gray-900">{part.name}</td>
                                    <td className="px-4 py-3 text-gray-500 font-mono text-xs">{part.part_number || '—'}</td>
                                    <td className="px-4 py-3 text-gray-500">{part.unit}</td>
                                    <td className="px-4 py-3 text-right">{stockBadge(part.quantity_in_stock)}</td>
                                    <td className="px-4 py-3 text-center">
                                        <button
                                            onClick={() => setEditingPart(part)}
                                            className="opacity-0 group-hover:opacity-100 text-gray-400 hover:text-blue-600 transition-opacity"
                                            title="Edit part"
                                        >
                                            <PencilSquareIcon className="w-4 h-4" />
                                        </button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                    <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                        {parts.length} part{parts.length !== 1 ? 's' : ''}
                    </div>
                </div>
            )}

            {editingPart && (
                <EditPartModal
                    part={editingPart}
                    onClose={() => setEditingPart(null)}
                />
            )}
        </div>
    )
}

// ── Invoice row (expandable) ───────────────────────────────────────────────────
function InvoiceRow({ invoice }) {
    const [expanded, setExpanded] = useState(false)
    const { data: items, isLoading } = usePurchaseInvoiceItems(expanded ? invoice.id : null)

    const invoiceTotal = typeof invoice.total_amount === 'number'
        ? invoice.total_amount.toFixed(2)
        : '—'

    return (
        <>
            <tr
                className="hover:bg-gray-50 cursor-pointer"
                onClick={() => setExpanded(p => !p)}
            >
                <td className="px-4 py-3 font-mono text-xs text-gray-700">{invoice.invoice_number}</td>
                <td className="px-4 py-3 text-gray-700">
                    {invoice.invoice_date
                        ? format(parseISO(invoice.invoice_date), 'dd MMM yyyy')
                        : '—'}
                </td>
                <td className="px-4 py-3 text-gray-700">{invoice.supplier_name}</td>
                <td className="px-4 py-3 text-right text-gray-900 font-medium">{invoiceTotal}</td>
                <td className="px-4 py-3 text-center text-gray-500">{invoice.item_count}</td>
                <td className="px-4 py-3 text-gray-400 text-xs">
                    {invoice.created_by_user?.name || '—'}
                </td>
                <td className="px-4 py-3 text-center text-gray-400">
                    {expanded
                        ? <ChevronUpIcon className="w-4 h-4 mx-auto" />
                        : <ChevronDownIcon className="w-4 h-4 mx-auto" />}
                </td>
            </tr>
            {expanded && (
                <tr>
                    <td colSpan={7} className="bg-gray-50 px-6 py-3">
                        {isLoading ? (
                            <p className="text-xs text-gray-400">Loading…</p>
                        ) : (
                            <table className="w-full text-xs">
                                <thead>
                                    <tr className="text-gray-500">
                                        <th className="text-left pb-1 font-medium">Part</th>
                                        <th className="text-left pb-1 font-medium">Part No.</th>
                                        <th className="text-right pb-1 font-medium">Qty</th>
                                        <th className="text-right pb-1 font-medium">Unit</th>
                                        <th className="text-right pb-1 font-medium">Unit Price</th>
                                        <th className="text-right pb-1 font-medium">Line Total</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-200">
                                    {items?.map(item => (
                                        <tr key={item.id}>
                                            <td className="py-1.5 pr-4 text-gray-700">{item.part?.name}</td>
                                            <td className="py-1.5 pr-4 text-gray-400 font-mono">{item.part?.part_number || '—'}</td>
                                            <td className="py-1.5 text-right text-gray-700">{item.quantity}</td>
                                            <td className="py-1.5 text-right text-gray-500">{item.part?.unit}</td>
                                            <td className="py-1.5 text-right text-gray-700">{Number(item.unit_price).toFixed(2)}</td>
                                            <td className="py-1.5 text-right font-medium text-gray-900">{Number(item.line_total).toFixed(2)}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        )}
                        {invoice.notes && (
                            <p className="text-xs text-gray-500 mt-2 italic">Note: {invoice.notes}</p>
                        )}
                        {invoice.invoice_file_url && (
                            <a
                                href={invoice.invoice_file_url}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="inline-flex items-center gap-1.5 mt-2 text-xs text-blue-600 hover:underline"
                            >
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13" /></svg>
                                View Invoice Document
                            </a>
                        )}
                    </td>
                </tr>
            )}
        </>
    )
}

// ── Purchase History Tab ───────────────────────────────────────────────────────
function PurchaseHistory() {
    const [filters, setFilters] = useState({ search: '', dateFrom: '', dateTo: '' })
    const { data: invoices = [], isLoading } = usePurchaseInvoices(filters)

    return (
        <div className="space-y-4">
            <div className="bg-white p-4 rounded-lg shadow-sm">
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
                    <div className="relative sm:col-span-2">
                        <input
                            type="text"
                            placeholder="Search invoice # or supplier…"
                            className="w-full pl-10 pr-4 py-2 border rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                            value={filters.search}
                            onChange={e => setFilters(p => ({ ...p, search: e.target.value }))}
                        />
                        <MagnifyingGlassIcon className="w-4 h-4 text-gray-400 absolute left-3 top-2.5" />
                    </div>
                    <input
                        type="date"
                        className="border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                        value={filters.dateFrom}
                        onChange={e => setFilters(p => ({ ...p, dateFrom: e.target.value }))}
                    />
                    <input
                        type="date"
                        className="border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                        value={filters.dateTo}
                        onChange={e => setFilters(p => ({ ...p, dateTo: e.target.value }))}
                    />
                </div>
            </div>

            {isLoading ? (
                <TicketListSkeleton />
            ) : invoices.length === 0 ? (
                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                    No purchase records found.
                </div>
            ) : (
                <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-100 text-sm">
                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                            <tr>
                                <th className="px-4 py-3 text-left">Invoice #</th>
                                <th className="px-4 py-3 text-left">Date</th>
                                <th className="px-4 py-3 text-left">Supplier</th>
                                <th className="px-4 py-3 text-right">Total</th>
                                <th className="px-4 py-3 text-center">Items</th>
                                <th className="px-4 py-3 text-left">Recorded by</th>
                                <th className="px-4 py-3 w-8"></th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-50">
                            {invoices.map(inv => (
                                <InvoiceRow key={inv.id} invoice={inv} />
                            ))}
                        </tbody>
                    </table>
                    <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                        {invoices.length} invoice{invoices.length !== 1 ? 's' : ''}
                    </div>
                </div>
            )}
        </div>
    )
}

// ── Consumption History Tab ────────────────────────────────────────────────────
const JC_STATUS_BADGE = {
    Completed: 'bg-green-100 text-green-700',
    Open: 'bg-blue-100 text-blue-700',
    'In Progress': 'bg-yellow-100 text-yellow-700',
}

function ConsumptionHistory() {
    const [filters, setFilters] = useState({ search: '', dateFrom: '', dateTo: '' })
    const { data: rows = [], isLoading } = usePartConsumption(filters)

    return (
        <div className="space-y-4">
            <div className="bg-white p-4 rounded-lg shadow-sm">
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
                    <div className="relative sm:col-span-2">
                        <input
                            type="text"
                            placeholder="Search part, vehicle or mechanic…"
                            className="w-full pl-10 pr-4 py-2 border rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                            value={filters.search}
                            onChange={e => setFilters(p => ({ ...p, search: e.target.value }))}
                        />
                        <MagnifyingGlassIcon className="w-4 h-4 text-gray-400 absolute left-3 top-2.5" />
                    </div>
                    <input
                        type="date"
                        className="border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                        value={filters.dateFrom}
                        onChange={e => setFilters(p => ({ ...p, dateFrom: e.target.value }))}
                    />
                    <input
                        type="date"
                        className="border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                        value={filters.dateTo}
                        onChange={e => setFilters(p => ({ ...p, dateTo: e.target.value }))}
                    />
                </div>
            </div>

            {isLoading ? (
                <TicketListSkeleton />
            ) : rows.length === 0 ? (
                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                    No consumption records found.
                </div>
            ) : (
                <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-100 text-sm">
                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                            <tr>
                                <th className="px-4 py-3 text-left">Date Used</th>
                                <th className="px-4 py-3 text-left">Part</th>
                                <th className="px-4 py-3 text-left">Part No.</th>
                                <th className="px-4 py-3 text-right">Qty Used</th>
                                <th className="px-4 py-3 text-left">Job Card</th>
                                <th className="px-4 py-3 text-left">Vehicle</th>
                                <th className="px-4 py-3 text-left">Mechanic</th>
                                <th className="px-4 py-3 text-left">JC Status</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-50">
                            {rows.map(row => (
                                <tr key={row.id} className="hover:bg-gray-50">
                                    <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">
                                        {row.added_at
                                            ? format(parseISO(row.added_at), 'dd MMM yyyy, HH:mm')
                                            : '—'}
                                    </td>
                                    <td className="px-4 py-3 font-medium text-gray-900">{row.part_name}</td>
                                    <td className="px-4 py-3 text-gray-400 font-mono text-xs">{row.part_number || '—'}</td>
                                    <td className="px-4 py-3 text-right text-gray-700">
                                        {row.quantity_used} <span className="text-gray-400 text-xs">{row.unit}</span>
                                    </td>
                                    <td className="px-4 py-3 font-mono text-xs">
                                        {row.job_card_number ? (
                                            <Link
                                                to={`/job-cards/${row.job_card_number}`}
                                                className="text-blue-600 hover:text-blue-800 hover:underline"
                                            >
                                                JC-{row.job_card_number}
                                            </Link>
                                        ) : '—'}
                                    </td>
                                    <td className="px-4 py-3">
                                        {row.vehicle_number ? (
                                            <Link
                                                to={`/vehicles/${encodeURIComponent(row.vehicle_number)}`}
                                                className="text-blue-600 hover:text-blue-800 hover:underline text-sm"
                                            >
                                                {row.vehicle_number}
                                            </Link>
                                        ) : '—'}
                                    </td>
                                    <td className="px-4 py-3">
                                        {row.mechanic_id ? (
                                            <Link
                                                to={`/mechanics/${row.mechanic_id}`}
                                                className="text-blue-600 hover:text-blue-800 hover:underline text-sm"
                                            >
                                                {row.mechanic_name}
                                            </Link>
                                        ) : (row.mechanic_name || '—')}
                                    </td>
                                    <td className="px-4 py-3">
                                        {row.job_card_status ? (
                                            <span className={`px-2 py-0.5 text-xs rounded-full ${JC_STATUS_BADGE[row.job_card_status] || 'bg-gray-100 text-gray-600'}`}>
                                                {row.job_card_status}
                                            </span>
                                        ) : '—'}
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                    <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                        {rows.length} record{rows.length !== 1 ? 's' : ''}
                    </div>
                </div>
            )}
        </div>
    )
}

// ── Main Page ─────────────────────────────────────────────────────────────────
export default function Inventory() {
    const [tab, setTab] = useState('parts')
    const [showPurchaseModal, setShowPurchaseModal] = useState(false)
    const [showBulkModal, setShowBulkModal] = useState(false)

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Inventory' }]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8">
                {/* Header row */}
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
                    <h1 className="text-2xl font-bold text-gray-900">Inventory</h1>
                    <div className="flex gap-3">
                        <button
                            onClick={() => setShowBulkModal(true)}
                            className="flex items-center gap-2 px-4 py-2 text-sm border rounded-lg bg-white text-gray-700 hover:bg-gray-50 shadow-sm"
                        >
                            <ArrowUpTrayIcon className="w-4 h-4" />
                            Bulk Upload
                        </button>
                        <button
                            onClick={() => setShowPurchaseModal(true)}
                            className="flex items-center gap-2 px-4 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 shadow-sm"
                        >
                            <PlusIcon className="w-4 h-4" />
                            Record Purchase
                        </button>
                    </div>
                </div>

                {/* Tabs */}
                <div className="flex gap-1 bg-white border rounded-lg p-1 mb-6 w-fit shadow-sm">
                    {[
                        { key: 'parts', label: 'Parts Catalog' },
                        { key: 'history', label: 'Purchase History' },
                        { key: 'consumption', label: 'Consumption History' },
                    ].map(t => (
                        <button
                            key={t.key}
                            onClick={() => setTab(t.key)}
                            className={`px-4 py-1.5 text-sm rounded-md transition-colors ${
                                tab === t.key
                                    ? 'bg-blue-600 text-white font-medium'
                                    : 'text-gray-600 hover:text-gray-900'
                            }`}
                        >
                            {t.label}
                        </button>
                    ))}
                </div>

                {tab === 'parts' && <PartsTable />}
                {tab === 'history' && <PurchaseHistory />}
                {tab === 'consumption' && <ConsumptionHistory />}
            </div>

            {showPurchaseModal && (
                <PurchaseModal onClose={() => setShowPurchaseModal(false)} />
            )}
            {showBulkModal && (
                <BulkUploadModal onClose={() => setShowBulkModal(false)} />
            )}
        </div>
    )
}
