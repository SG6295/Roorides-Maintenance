import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { todayLocal } from '../utils/datetime'
import { useAuth } from '../hooks/useAuth'
import { useOutsourceInvoices, useOutsourceInvoiceSummary } from '../hooks/useOutsourceInvoices'
import Navigation from '../components/shared/Navigation'
import InvoiceDrawer from '../components/outsource-invoices/InvoiceDrawer'
import {
    fmtPaise,
    fmtDate,
    MAINTENANCE_STATUS_COLORS,
    financeStatusColor,
} from '../components/outsource-invoices/format'
import { invoiceSettlement } from '../utils/settlement'
import {
    PAID_BY_OPTIONS,
    MAINTENANCE_PAYMENT_STATUSES,
    FINANCE_PAYMENT_STATUSES,
} from '../constants/outsourceInvoices'

export default function OutsourceInvoices() {
    const [searchParams, setSearchParams] = useSearchParams()
    const { userProfile } = useAuth()
    const [openedInvoice, setOpenedInvoice] = useState(null)

    // ── Parse URL params ──────────────────────────────────────────────────────
    const search   = searchParams.get('q')    || ''
    const psFilter = searchParams.getAll('ps')
    const fsFilter = searchParams.getAll('fs')
    const pbFilter = searchParams.getAll('pb')
    const dateFrom = searchParams.get('from') || ''
    const dateTo   = searchParams.get('to')   || ''
    const page     = Math.max(0, parseInt(searchParams.get('p') ?? '0', 10) || 0)

    // Local, not UTC: toISOString() would still say yesterday until 05:30 IST, which caps
    // the date pickers a day short and mis-flags invoices as overdue.
    const todayStr = todayLocal()

    // Server-side filters shared by both hooks (no page, no search)
    const serverFilters = {
        maintenancePaymentStatus: psFilter,
        financePaymentStatus:     fsFilter,
        paidBy:                   pbFilter,
        dateFrom,
        dateTo,
    }

    // When search is active, disable pagination so we can do client-side matching
    // across all records that pass the server-side filters.
    const { data: pageResult, isLoading } = useOutsourceInvoices({
        ...serverFilters,
        page: search ? null : page,
    })
    const { invoices: rawInvoices = [], totalCount = null } = pageResult ?? {}

    // Summary tiles via RPC — same server-side filters, ignores pagination
    const { data: summary } = useOutsourceInvoiceSummary(serverFilters)

    // ── Client-side enrich + search filter ───────────────────────────────────
    const invoices = rawInvoices
        .map(inv => {
            const active = (inv.payments ?? []).filter(p => p.status !== 'Cancelled')
            const lastPaidOn = active.reduce((latest, p) => (p.paid_on > latest ? p.paid_on : latest), '')
            return { ...inv, settlement: invoiceSettlement(inv, inv.payments), lastPaidOn }
        })
        .filter(inv => {
            if (!search) return true
            const q = search.toLowerCase()
            return (
                inv.invoice_no?.toLowerCase().includes(q) ||
                String(inv.job_card?.job_card_number ?? '').toLowerCase().includes(q) ||
                inv.job_card?.vehicle_number?.toLowerCase().includes(q)
            )
        })

    // Re-read from the list so the drawer shows fresh values after a save refetches it.
    // Falls back to the row as opened, in case the save moved it out of the current
    // Finance Status filter — the drawer stays open rather than vanishing on Save.
    const selectedInvoice = openedInvoice
        ? invoices.find(inv => inv.id === openedInvoice.id) ?? openedInvoice
        : null

    // ── Pagination derived values ─────────────────────────────────────────────
    const PAGE_SIZE   = 50
    const totalPages  = totalCount !== null ? Math.ceil(totalCount / PAGE_SIZE) : null
    const showingFrom = totalCount !== null ? page * PAGE_SIZE + 1 : null
    const showingTo   = totalCount !== null ? Math.min((page + 1) * PAGE_SIZE, totalCount) : null

    // ── Filter helpers ────────────────────────────────────────────────────────
    // All setters reset page to 0 atomically in the same URL update.
    const setSearch = (val) => {
        setSearchParams(prev => {
            const next = new URLSearchParams(prev)
            next.delete('p')
            if (val) next.set('q', val)
            else next.delete('q')
            return next
        })
    }

    const toggleMulti = (key, val) => {
        setSearchParams(prev => {
            const next = new URLSearchParams(prev)
            const current = next.getAll(key)
            next.delete(key)
            next.delete('p')
            if (current.includes(val)) {
                current.filter(v => v !== val).forEach(v => next.append(key, v))
            } else {
                [...current, val].forEach(v => next.append(key, v))
            }
            return next
        })
    }

    const setDate = (key, val) => {
        setSearchParams(prev => {
            const next = new URLSearchParams(prev)
            next.delete('p')
            if (val) next.set(key, val)
            else next.delete(key)
            return next
        })
    }

    const setPage = (newPage) => {
        setSearchParams(prev => {
            const next = new URLSearchParams(prev)
            if (newPage === 0) next.delete('p')
            else next.set('p', String(newPage))
            return next
        })
    }

    const clearFilters = () => setSearchParams({})
    const hasFilters   = !!(search || psFilter.length || fsFilter.length || pbFilter.length || dateFrom || dateTo)

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Outsource Invoices' }]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6 space-y-5">

                <h1 className="text-2xl font-bold text-gray-900">Outsource Invoices</h1>

                {/* ── Summary tiles (from RPC) ──────────────────────────────── */}
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-4">
                        <p className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">
                            Total Unpaid Payable
                        </p>
                        <p className="text-2xl font-bold text-gray-900">
                            {summary
                                ? `₹${summary.totalUnpaidPayable.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
                                : '—'}
                        </p>
                    </div>
                    <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-4">
                        <p className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">Overdue</p>
                        <p className={`text-2xl font-bold ${summary?.overdueCount > 0 ? 'text-red-600' : 'text-gray-900'}`}>
                            {summary?.overdueCount ?? '—'}
                        </p>
                    </div>
                    <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-4">
                        <p className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">
                            Pending Approval (Hold)
                        </p>
                        <p className={`text-2xl font-bold ${summary?.pendingApprovalCount > 0 ? 'text-amber-600' : 'text-gray-900'}`}>
                            {summary?.pendingApprovalCount ?? '—'}
                        </p>
                    </div>
                </div>

                {/* ── Filters ──────────────────────────────────────────────── */}
                <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-4 space-y-4">
                    <div className="flex flex-col sm:flex-row gap-3">
                        <input
                            type="text"
                            value={search}
                            onChange={e => setSearch(e.target.value)}
                            placeholder="Search invoice no, job card #, vehicle reg…"
                            className="flex-1 text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                        {hasFilters && (
                            <button
                                onClick={clearFilters}
                                className="text-sm px-3 py-2 text-gray-600 border border-gray-300 rounded-lg hover:bg-gray-50 whitespace-nowrap"
                            >
                                Clear filters
                            </button>
                        )}
                    </div>

                    <div className="flex flex-wrap gap-6">
                        <div>
                            <p className="text-xs font-medium text-gray-500 mb-1.5">Maintenance Status</p>
                            <div className="flex flex-wrap gap-1.5">
                                {MAINTENANCE_PAYMENT_STATUSES.map(s => (
                                    <button
                                        key={s}
                                        onClick={() => toggleMulti('ps', s)}
                                        className={`px-3 py-1 text-xs rounded-full border transition-colors ${
                                            psFilter.includes(s)
                                                ? 'bg-blue-600 text-white border-blue-600'
                                                : 'bg-white text-gray-600 border-gray-300 hover:border-gray-400'
                                        }`}
                                    >
                                        {s}
                                    </button>
                                ))}
                            </div>
                        </div>

                        <div>
                            <p className="text-xs font-medium text-gray-500 mb-1.5">Finance Status</p>
                            <div className="flex flex-wrap gap-1.5">
                                {FINANCE_PAYMENT_STATUSES.map(s => (
                                    <button
                                        key={s}
                                        onClick={() => toggleMulti('fs', s)}
                                        className={`px-3 py-1 text-xs rounded-full border transition-colors ${
                                            fsFilter.includes(s)
                                                ? 'bg-blue-600 text-white border-blue-600'
                                                : 'bg-white text-gray-600 border-gray-300 hover:border-gray-400'
                                        }`}
                                    >
                                        {s}
                                    </button>
                                ))}
                            </div>
                        </div>

                        <div>
                            <p className="text-xs font-medium text-gray-500 mb-1.5">Paid By</p>
                            <div className="flex flex-wrap gap-1.5">
                                {PAID_BY_OPTIONS.map(pb => (
                                    <button
                                        key={pb}
                                        onClick={() => toggleMulti('pb', pb)}
                                        className={`px-3 py-1 text-xs rounded-full border transition-colors ${
                                            pbFilter.includes(pb)
                                                ? 'bg-blue-600 text-white border-blue-600'
                                                : 'bg-white text-gray-600 border-gray-300 hover:border-gray-400'
                                        }`}
                                    >
                                        {pb}
                                    </button>
                                ))}
                            </div>
                        </div>

                        <div>
                            <p className="text-xs font-medium text-gray-500 mb-1.5">Activity Date</p>
                            <div className="flex items-center gap-2">
                                <input
                                    type="date"
                                    value={dateFrom}
                                    max={dateTo || todayStr}
                                    onChange={e => setDate('from', e.target.value)}
                                    className="text-sm border border-gray-300 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                />
                                <span className="text-xs text-gray-400">to</span>
                                <input
                                    type="date"
                                    value={dateTo}
                                    min={dateFrom || undefined}
                                    max={todayStr}
                                    onChange={e => setDate('to', e.target.value)}
                                    className="text-sm border border-gray-300 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                />
                            </div>
                        </div>
                    </div>
                </div>

                {/* ── Table ────────────────────────────────────────────────── */}
                <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-x-auto">
                    {isLoading ? (
                        <div className="p-8 text-center text-sm text-gray-500">Loading…</div>
                    ) : invoices.length === 0 ? (
                        <div className="p-8 text-center text-sm text-gray-400">No invoices found.</div>
                    ) : (
                        <table className="min-w-full divide-y divide-gray-200 text-sm">
                            <thead className="bg-gray-50">
                                <tr>
                                    {[
                                        'Job Card', 'Vehicle', 'Supplier', 'Invoice No',
                                        'Activity Date', 'Paid By',
                                        'Payable', 'Paid', 'TDS',
                                        'Maintenance Status', 'Finance Status', 'Last Paid On', 'Pay By', '',
                                    ].map(h => (
                                        <th
                                            key={h}
                                            className="px-3 py-3 text-left text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap"
                                        >
                                            {h}
                                        </th>
                                    ))}
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100">
                                {invoices.map(inv => {
                                    const isOverdue = !!(
                                        inv.payby_date &&
                                        inv.payby_date < todayStr &&
                                        inv.finance_payment_status !== 'Paid'
                                    )
                                    return (
                                        <tr
                                            key={inv.id}
                                            className="hover:bg-gray-50 cursor-pointer"
                                            onClick={() => setOpenedInvoice(inv)}
                                        >
                                            <td className="px-3 py-3 whitespace-nowrap">
                                                <Link
                                                    to={`/job-cards/${inv.job_card?.job_card_number}`}
                                                    onClick={e => e.stopPropagation()}
                                                    className="text-blue-600 hover:underline font-medium"
                                                >
                                                    #{inv.job_card?.job_card_number}
                                                </Link>
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap text-gray-700">
                                                {inv.job_card?.vehicle_number || '—'}
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap text-gray-700">
                                                {inv.job_card?.supplier?.entity_name || '—'}
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap font-mono text-gray-900">
                                                {inv.invoice_no || '—'}
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap text-gray-700">
                                                {fmtDate(inv.date_of_activity)}
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap text-gray-700">
                                                {inv.paid_by || '—'}
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap text-right font-medium text-gray-900">
                                                {fmtPaise(inv.settlement.payable)}
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap text-right text-gray-900">
                                                {fmtPaise(inv.settlement.paid)}
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap text-right text-gray-900">
                                                {fmtPaise(inv.settlement.tds)}
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap">
                                                <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${MAINTENANCE_STATUS_COLORS[inv.maintenance_payment_status] ?? 'bg-gray-100 text-gray-600'}`}>
                                                    {inv.maintenance_payment_status || '—'}
                                                </span>
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap">
                                                <span
                                                    title={inv.finance_remark || undefined}
                                                    className={`px-2 py-0.5 rounded-full text-xs font-medium ${financeStatusColor(inv.finance_payment_status)}`}
                                                >
                                                    {inv.finance_payment_status}
                                                </span>
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap text-gray-700">
                                                {fmtDate(inv.lastPaidOn)}
                                            </td>
                                            <td className={`px-3 py-3 whitespace-nowrap font-medium ${isOverdue ? 'text-red-600' : 'text-gray-700'}`}>
                                                {fmtDate(inv.payby_date)}
                                                {isOverdue && (
                                                    <span className="ml-1 text-xs" title="Overdue">⚠</span>
                                                )}
                                            </td>
                                            <td className="px-3 py-3 whitespace-nowrap">
                                                <button
                                                    onClick={e => { e.stopPropagation(); setOpenedInvoice(inv) }}
                                                    className="text-xs px-2.5 py-1 text-blue-600 border border-blue-200 rounded-lg hover:bg-blue-50 transition-colors"
                                                >
                                                    View
                                                </button>
                                            </td>
                                        </tr>
                                    )
                                })}
                            </tbody>
                        </table>
                    )}
                </div>

                {/* ── Pagination / count ───────────────────────────────────── */}
                {!isLoading && (
                    search ? (
                        <p className="text-xs text-gray-500 text-right">
                            {invoices.length} result{invoices.length !== 1 ? 's' : ''} — search active, showing all matches
                        </p>
                    ) : totalPages !== null && totalPages > 1 ? (
                        <div className="flex items-center justify-between">
                            <p className="text-xs text-gray-500">
                                Showing {showingFrom}–{showingTo} of {totalCount} invoices
                            </p>
                            <div className="flex items-center gap-2">
                                <button
                                    onClick={() => setPage(page - 1)}
                                    disabled={page === 0}
                                    className="px-3 py-1.5 text-sm border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                                >
                                    ← Prev
                                </button>
                                <span className="text-sm text-gray-600 tabular-nums">
                                    Page {page + 1} of {totalPages}
                                </span>
                                <button
                                    onClick={() => setPage(page + 1)}
                                    disabled={page >= totalPages - 1}
                                    className="px-3 py-1.5 text-sm border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                                >
                                    Next →
                                </button>
                            </div>
                        </div>
                    ) : totalCount !== null ? (
                        <p className="text-xs text-gray-500 text-right">
                            {totalCount} invoice{totalCount !== 1 ? 's' : ''}
                        </p>
                    ) : null
                )}
            </div>

            {/* ── Invoice drawer: statuses, payments, details ─────────────── */}
            {selectedInvoice && (
                <InvoiceDrawer
                    invoice={selectedInvoice}
                    role={userProfile?.role}
                    onClose={() => setOpenedInvoice(null)}
                    onInvoiceSaved={saved => setOpenedInvoice(prev => ({ ...prev, ...saved }))}
                />
            )}
        </div>
    )
}
