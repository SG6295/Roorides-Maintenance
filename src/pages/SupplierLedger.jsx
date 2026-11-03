import { useState } from 'react'
import { Link } from 'react-router-dom'
import Navigation from '../components/shared/Navigation'
import CreditDaysEditor from '../components/supplier-ledger/CreditDaysEditor'
import { useAuth } from '../hooks/useAuth'
import { useSupplierBalances } from '../hooks/useSupplierLedger'
import { LEDGER_WRITE_ROLES } from '../constants/supplierLedger'
import { upcomingRuns } from '../utils/paymentRuns'
import { exportSupplierBalances } from '../utils/supplierLedgerExport'
import { todayLocal, formatAs } from '../utils/datetime'
import { fmtMoney, fmtDate } from '../components/outsource-invoices/format'

const FILTERS = [
    { key: 'balance', label: 'With a balance', test: r => r.outstanding !== 0 },
    { key: 'overdue', label: 'Overdue', test: r => r.overdue > 0 },
    { key: 'all',     label: 'All',     test: () => true },
]

const money = v => (v ? fmtMoney(v) : '—')

/**
 * The supplier ledger (MAIN-119): what each supplier is owed for accepted invoices, less
 * advances and payments, split by Wednesday payment run. Finance and super_admin set
 * credit days here; exec reads.
 */
export default function SupplierLedger() {
    const { userProfile } = useAuth()
    const canWrite = LEDGER_WRITE_ROLES.includes(userProfile?.role)
    const { data: rows = [], isLoading, error } = useSupplierBalances()
    const [search, setSearch] = useState('')
    const [filter, setFilter] = useState('balance')

    const today = todayLocal()
    const { thisRun, nextRun } = upcomingRuns(today)
    const runLabel = iso => formatAs(iso, 'dd MMM')

    // Summed in paise so the totals add up exactly.
    const sum = key => rows.reduce((s, r) => s + Math.round(r[key] * 100), 0) / 100
    const totals = {
        outstanding: sum('outstanding'),
        overdue: sum('overdue'),
        thisWed: sum('due_this_wednesday'),
        nextWed: sum('due_next_wednesday'),
        awaiting: rows.reduce((s, r) => s + r.awaiting_acceptance, 0),
    }

    const test = FILTERS.find(f => f.key === filter).test
    const visible = rows
        .filter(test)
        .filter(r => !search || r.entity_name.toLowerCase().includes(search.toLowerCase()))

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Supplier ledger' }]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6 space-y-5">
                <div className="flex flex-wrap items-end justify-between gap-4">
                    <div>
                        <h1 className="text-2xl font-bold text-gray-900">Supplier ledger</h1>
                        <p className="text-sm text-gray-500 mt-1">
                            What each supplier is owed for accepted invoices, less advances and payments.
                            Payments go out every Wednesday.
                        </p>
                    </div>
                    <button
                        type="button"
                        onClick={() => exportSupplierBalances(visible, { thisRun, nextRun, today })}
                        disabled={visible.length === 0}
                        className="text-sm px-3 py-2 text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50"
                    >
                        Export to Excel
                    </button>
                </div>

                <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
                    <Tile label="Total outstanding" value={fmtMoney(totals.outstanding)} />
                    <Tile label="Overdue" value={fmtMoney(totals.overdue)} tone={totals.overdue > 0 ? 'text-red-700' : ''} note="Missed a past Wednesday run" />
                    <Tile label="Due this Wednesday" value={fmtMoney(totals.thisWed)} tone={totals.thisWed > 0 ? 'text-amber-700' : ''} note={`Run of ${fmtDate(thisRun)}`} highlight />
                    <Tile label="Due next Wednesday" value={fmtMoney(totals.nextWed)} note={`Run of ${fmtDate(nextRun)}`} />
                </div>

                <div className="flex flex-wrap items-center gap-3">
                    <input
                        type="text"
                        value={search}
                        onChange={e => setSearch(e.target.value)}
                        placeholder="Search supplier…"
                        aria-label="Search suppliers"
                        className="flex-1 min-w-[16rem] text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    />
                    <div className="flex gap-1.5">
                        {FILTERS.map(f => (
                            <button
                                key={f.key}
                                type="button"
                                onClick={() => setFilter(f.key)}
                                className={`px-3 py-1 text-xs rounded-full border transition-colors ${filter === f.key
                                    ? 'bg-blue-600 text-white border-blue-600'
                                    : 'bg-white text-gray-600 border-gray-300 hover:border-gray-400'}`}
                            >
                                {f.label}
                            </button>
                        ))}
                    </div>
                </div>

                <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-x-auto">
                    {isLoading ? (
                        <div className="p-8 text-center text-sm text-gray-500">Loading…</div>
                    ) : error ? (
                        <div className="p-8 text-center text-sm text-red-600">Could not load the ledger: {error.message}</div>
                    ) : visible.length === 0 ? (
                        <div className="p-8 text-center text-sm text-gray-400">No suppliers match.</div>
                    ) : (
                        <table className="min-w-full divide-y divide-gray-200 text-sm">
                            <thead className="bg-gray-50">
                                <tr>
                                    <Th>Supplier</Th>
                                    <Th>Credit days</Th>
                                    <Th right>Outstanding</Th>
                                    <Th right>Overdue</Th>
                                    <Th right className="bg-amber-50">Wed {runLabel(thisRun)}</Th>
                                    <Th right>Wed {runLabel(nextRun)}</Th>
                                    <Th right>Later</Th>
                                    <Th>Last payment</Th>
                                    <Th>Last reconciled</Th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100">
                                {visible.map(r => (
                                    <tr key={r.supplier_id} className="hover:bg-gray-50">
                                        <td className="px-3 py-3 whitespace-nowrap">
                                            <Link to={`/supplier-ledger/${r.supplier_id}`} className="font-semibold text-blue-600 hover:underline">
                                                {r.entity_name}
                                            </Link>
                                            {r.awaiting_acceptance > 0 && (
                                                <span className="block text-xs text-gray-500">
                                                    {r.awaiting_acceptance} invoice{r.awaiting_acceptance === 1 ? '' : 's'} awaiting acceptance
                                                </span>
                                            )}
                                        </td>
                                        <td className="px-3 py-3 whitespace-nowrap">
                                            <CreditDaysEditor supplierId={r.supplier_id} value={r.credit_days} canEdit={canWrite} />
                                        </td>
                                        <Td right strong>{fmtMoney(r.outstanding)}</Td>
                                        <Td right className={r.overdue > 0 ? 'text-red-700 font-semibold' : ''}>{money(r.overdue)}</Td>
                                        <Td right className={`bg-amber-50/60 ${r.due_this_wednesday > 0 ? 'text-amber-800 font-semibold' : ''}`}>{money(r.due_this_wednesday)}</Td>
                                        <Td right>{money(r.due_next_wednesday)}</Td>
                                        <Td right>{money(r.later)}</Td>
                                        <Td className={r.last_payment_on ? '' : 'text-gray-400'}>{r.last_payment_on ? fmtDate(r.last_payment_on) : 'None yet'}</Td>
                                        <Td className={r.last_reconciled_on ? '' : 'text-gray-400'}>{r.last_reconciled_on ? fmtDate(r.last_reconciled_on) : 'Never'}</Td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    )}
                </div>

                <p className="text-xs text-gray-500">
                    An invoice is due its submission date plus the supplier's credit days (blank counts as 0) and goes
                    in the first Wednesday run on or after that; it is overdue once that run has passed. The due figures
                    assume payments clear the oldest invoices first — nothing is stored against an invoice.
                    {totals.awaiting > 0 && <> {totals.awaiting} submitted invoice{totals.awaiting === 1 ? ' is' : 's are'} waiting for finance to accept {totals.awaiting === 1 ? 'it' : 'them'} and {totals.awaiting === 1 ? 'is' : 'are'} not counted — see <Link to="/outsource-invoices?fs=New&fs=Hold" className="text-blue-600 hover:underline">Outsource Invoices</Link>.</>}
                </p>
            </div>
        </div>
    )
}

function Tile({ label, value, note, tone = '', highlight = false }) {
    return (
        <div className={`bg-white rounded-xl shadow-sm p-4 ${highlight ? 'border-2 border-amber-400' : 'border border-gray-200'}`}>
            <p className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">{label}</p>
            <p className={`text-2xl font-bold text-gray-900 ${tone}`}>{value}</p>
            {note && <p className="text-xs text-gray-500 mt-0.5">{note}</p>}
        </div>
    )
}

function Th({ children, right = false, className = '' }) {
    return (
        <th className={`px-3 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap ${right ? 'text-right' : 'text-left'} ${className}`}>
            {children}
        </th>
    )
}

function Td({ children, right = false, strong = false, className = '' }) {
    return (
        <td className={`px-3 py-3 whitespace-nowrap ${right ? 'text-right tabular-nums' : ''} ${strong ? 'font-semibold text-gray-900' : 'text-gray-700'} ${className}`}>
            {children}
        </td>
    )
}
