import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import Navigation from '../components/shared/Navigation'
import CreditDaysEditor from '../components/supplier-ledger/CreditDaysEditor'
import RecordSupplierPaymentModal from '../components/supplier-ledger/RecordSupplierPaymentModal'
import ReconcileModal from '../components/supplier-ledger/ReconcileModal'
import CancelPaymentModal from '../components/supplier-ledger/CancelPaymentModal'
import { useAuth } from '../hooks/useAuth'
import { useSupplierBalance, useSupplierStatement, useSupplierOpenItems } from '../hooks/useSupplierLedger'
import { LEDGER_WRITE_ROLES } from '../constants/supplierLedger'
import { describeLine, invoiceOwner, LINE_TAGS } from '../utils/supplierLedger'
import { exportSupplierStatement } from '../utils/supplierLedgerExport'
import { batchPath } from '../utils/batchNumber'
import { todayLocal } from '../utils/datetime'
import { fmtMoney, fmtDate } from '../components/outsource-invoices/format'

const BUCKET_LABELS = {
    overdue:        { label: 'Overdue',             className: 'text-red-700' },
    this_wednesday: { label: 'This Wednesday',      className: 'text-amber-700' },
    next_wednesday: { label: 'Next Wednesday',      className: 'text-gray-700' },
    later:          { label: 'Later',               className: 'text-gray-500' },
}

/**
 * One supplier's ledger statement (MAIN-119): every invoice, advance, payment and
 * adjustment in date order with the running balance; what is still open and which
 * Wednesday it goes in; and finance's actions — record or cancel a payment, reconcile,
 * set credit days. Exec reads only.
 */
export default function SupplierStatement() {
    const { supplierId } = useParams()
    const { userProfile } = useAuth()
    const canWrite = LEDGER_WRITE_ROLES.includes(userProfile?.role)
    const { data: supplier, isLoading, error } = useSupplierBalance(supplierId)
    const { data: lines = [], isLoading: linesLoading } = useSupplierStatement(supplierId)
    const { data: openItems = [] } = useSupplierOpenItems(supplierId)

    const [dialog, setDialog] = useState(null)
    const [from, setFrom] = useState('')
    const [to, setTo] = useState('')
    const [showAll, setShowAll] = useState(true)
    const today = todayLocal()

    if (isLoading) return <Page><div className="p-8 text-center text-sm text-gray-500">Loading…</div></Page>
    if (error || !supplier) {
        return <Page><div className="p-8 text-center text-sm text-red-600">{error ? `Could not load the ledger: ${error.message}` : 'Supplier not found.'}</div></Page>
    }

    const visible = lines.filter(l =>
        (!from || l.entry_date >= from) &&
        (!to || l.entry_date <= to) &&
        (showAll || l.counts),
    )
    // Totals over what is shown, in paise so they add up exactly.
    const paise = v => Math.round(Number(v) * 100)
    const owedTotal = visible.reduce((s, l) => s + (l.counts && Number(l.amount) > 0 ? paise(l.amount) : 0), 0) / 100
    const paidTotal = visible.reduce((s, l) => s + (l.counts && Number(l.amount) < 0 ? -paise(l.amount) : 0), 0) / 100
    const closing = visible.length ? visible[visible.length - 1].balance : 0

    return (
        <Page name={supplier.entity_name}>
            <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                    <h1 className="text-2xl font-bold text-gray-900">{supplier.entity_name}</h1>
                    <p className="text-sm text-gray-600 mt-1 flex flex-wrap items-center gap-x-1">
                        Credit period <CreditDaysEditor supplierId={supplier.supplier_id} value={supplier.credit_days} canEdit={canWrite} /> days
                        <span className="text-gray-400">·</span>
                        {supplier.last_reconciled_on ? `Last reconciled ${fmtDate(supplier.last_reconciled_on)}` : 'Not reconciled yet'}
                    </p>
                </div>
                <div className="flex flex-wrap gap-2">
                    <button
                        type="button"
                        onClick={() => exportSupplierStatement(supplier.entity_name, visible, today)}
                        disabled={visible.length === 0}
                        className="text-sm px-3 py-2 text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50"
                    >
                        Export to Excel
                    </button>
                    {canWrite && (
                        <>
                            <button type="button" onClick={() => setDialog({ type: 'reconcile' })} className="text-sm px-3 py-2 text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50">
                                Reconcile balance
                            </button>
                            <button type="button" onClick={() => setDialog({ type: 'payment' })} className="text-sm px-3 py-2 font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700">
                                Record payment
                            </button>
                        </>
                    )}
                </div>
            </div>

            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <Tile label="Outstanding" value={fmtMoney(supplier.outstanding)} note={supplier.outstanding < 0 ? 'In credit with us' : null} />
                <Tile label="Overdue" value={fmtMoney(supplier.overdue)} tone={supplier.overdue > 0 ? 'text-red-700' : ''} />
                <Tile label="Due this Wednesday" value={fmtMoney(supplier.due_this_wednesday)} tone={supplier.due_this_wednesday > 0 ? 'text-amber-700' : ''} note={`Run of ${fmtDate(supplier.this_wednesday)}`} highlight />
                <Tile
                    label="Next Wednesday · later"
                    value={fmtMoney(supplier.due_next_wednesday)}
                    note={supplier.later > 0 ? `+ ${fmtMoney(supplier.later)} later` : 'Nothing later'}
                />
            </div>

            {openItems.length > 0 && (
                <section className="bg-white rounded-xl border border-gray-200 shadow-sm p-4">
                    <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-2">Still open</h2>
                    <p className="text-xs text-gray-500 mb-3">Payments clear the oldest invoices first. This is how the outstanding balance splits across Wednesday runs.</p>
                    <div className="overflow-x-auto">
                        <table className="min-w-full text-sm">
                            <thead>
                                <tr className="text-xs text-gray-500 uppercase tracking-wide">
                                    <th className="text-left font-medium py-1 pr-3">Item</th>
                                    <th className="text-left font-medium py-1 px-3">Due</th>
                                    <th className="text-left font-medium py-1 px-3">Run</th>
                                    <th className="text-right font-medium py-1 px-3">Open</th>
                                    <th className="text-left font-medium py-1 pl-3">When</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100">
                                {openItems.map(o => {
                                    const b = BUCKET_LABELS[o.bucket]
                                    return (
                                        <tr key={o.line_id + o.kind}>
                                            <td className="py-2 pr-3 whitespace-nowrap">
                                                {o.kind === 'adjustment' ? 'Reconciliation adjustment' : <>{o.invoice_no} <OwnerLink line={o} /></>}
                                            </td>
                                            <td className="py-2 px-3 whitespace-nowrap">{fmtDate(o.due_date)}</td>
                                            <td className="py-2 px-3 whitespace-nowrap">Wed {fmtDate(o.run_date)}</td>
                                            <td className="py-2 px-3 text-right tabular-nums whitespace-nowrap">
                                                {fmtMoney(o.remaining)}
                                                {Number(o.remaining) < Number(o.amount) && <span className="text-xs text-gray-500"> of {fmtMoney(o.amount)}</span>}
                                            </td>
                                            <td className={`py-2 pl-3 whitespace-nowrap font-medium ${b.className}`}>{b.label}</td>
                                        </tr>
                                    )
                                })}
                            </tbody>
                        </table>
                    </div>
                </section>
            )}

            <div className="flex flex-wrap items-center gap-3 text-sm">
                <span className="text-gray-500">From</span>
                <input type="date" aria-label="From date" value={from} max={to || today} onChange={e => setFrom(e.target.value)} className="border border-gray-300 rounded-lg px-2 py-1.5" />
                <span className="text-gray-500">to</span>
                <input type="date" aria-label="To date" value={to} min={from || undefined} max={today} onChange={e => setTo(e.target.value)} className="border border-gray-300 rounded-lg px-2 py-1.5" />
                <label className="flex items-center gap-2 text-gray-700 ml-2">
                    <input type="checkbox" checked={showAll} onChange={e => setShowAll(e.target.checked)} />
                    Show reimbursements and cancelled payments
                </label>
            </div>

            <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-x-auto">
                {linesLoading ? (
                    <div className="p-8 text-center text-sm text-gray-500">Loading…</div>
                ) : visible.length === 0 ? (
                    <div className="p-8 text-center text-sm text-gray-400">
                        {lines.length === 0 ? 'Nothing in this ledger yet. Invoices appear once finance accepts them.' : 'No entries in this range.'}
                    </div>
                ) : (
                    <table className="min-w-full divide-y divide-gray-200 text-sm">
                        <thead className="bg-gray-50">
                            <tr>
                                <Th>Date</Th>
                                <Th>Entry</Th>
                                <Th right>Owed</Th>
                                <Th right>Paid</Th>
                                <Th right>Balance</Th>
                                {canWrite && <th className="px-3 py-3" aria-label="Actions" />}
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100">
                            {visible.map(l => (
                                <StatementRow
                                    key={l.kind + l.line_id}
                                    line={l}
                                    canWrite={canWrite}
                                    onCancel={() => setDialog({ type: 'cancel', line: l })}
                                />
                            ))}
                        </tbody>
                        <tfoot>
                            <tr className="border-t-2 border-gray-200 font-semibold">
                                <td className="px-3 py-3" colSpan={2}>Closing balance{to ? `, ${fmtDate(to)}` : ''}</td>
                                <td className="px-3 py-3 text-right tabular-nums">{fmtMoney(owedTotal)}</td>
                                <td className="px-3 py-3 text-right tabular-nums">{fmtMoney(paidTotal)}</td>
                                <td className="px-3 py-3 text-right tabular-nums font-bold">{fmtMoney(closing)}</td>
                                {canWrite && <td />}
                            </tr>
                        </tfoot>
                    </table>
                )}
            </div>

            <p className="text-xs text-gray-500">
                Payments posted to a person's ledger (Manjunath, Gokilavanan, PCN) pay that person back for an advance.
                They are listed for reference and do not change what the supplier is owed.
                {from && ' Owed and Paid totals cover the dates shown; the balance is the running balance.'}
            </p>

            {dialog?.type === 'payment' && (
                <RecordSupplierPaymentModal supplier={{ id: supplier.supplier_id, entity_name: supplier.entity_name }} outstanding={supplier.outstanding} onClose={() => setDialog(null)} />
            )}
            {dialog?.type === 'reconcile' && (
                <ReconcileModal supplier={{ id: supplier.supplier_id, entity_name: supplier.entity_name }} lines={lines} onClose={() => setDialog(null)} />
            )}
            {dialog?.type === 'cancel' && (
                <CancelPaymentModal
                    payment={dialog.line}
                    description={`${describeLine(dialog.line).title} · ${fmtMoney(-Number(dialog.line.amount))} on ${fmtDate(dialog.line.entry_date)}`}
                    onClose={() => setDialog(null)}
                />
            )}
        </Page>
    )
}

function Page({ name, children }) {
    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Supplier ledger', href: '/supplier-ledger' }, ...(name ? [{ label: name }] : [])]} />
            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6 space-y-5">{children}</div>
        </div>
    )
}

function OwnerLink({ line }) {
    const owner = invoiceOwner(line)
    if (!owner) return null
    const to = owner.jobCardNumber != null ? `/job-cards/${owner.jobCardNumber}` : batchPath(owner.batchNumber)
    return <>· <Link to={to} className="text-blue-600 hover:underline">{owner.label}</Link></>
}

function StatementRow({ line, canWrite, onCancel }) {
    const { title, sub } = describeLine(line)
    const tag = LINE_TAGS[line.kind]
    const amount = Number(line.amount)
    const muted = !line.counts
    const struck = line.kind === 'cancelled'
    const cancellable = line.kind === 'payment' || line.kind === 'reimbursement'

    return (
        <tr className={muted ? 'bg-gray-50/70 text-gray-500' : 'text-gray-700'}>
            <td className="px-3 py-3 whitespace-nowrap align-top">{fmtDate(line.entry_date)}</td>
            <td className="px-3 py-3 align-top min-w-[20rem]">
                <span className={`inline-block text-[11px] font-semibold px-2 py-0.5 rounded-full mr-2 ${tag?.className}`}>{tag?.label}</span>
                <span className={struck ? 'line-through' : ''}>{title}</span>
                {(line.kind === 'invoice' || line.kind === 'advance') && <> <OwnerLink line={line} /></>}
                {sub && <span className="block text-xs text-gray-500 mt-0.5">{sub}</span>}
            </td>
            <td className="px-3 py-3 text-right tabular-nums whitespace-nowrap align-top">{amount > 0 ? fmtMoney(amount) : ''}</td>
            <td className={`px-3 py-3 text-right tabular-nums whitespace-nowrap align-top ${struck ? 'line-through text-gray-400' : ''}`}>
                {amount < 0 ? (muted && !struck ? `(${fmtMoney(-amount)})` : fmtMoney(-amount)) : ''}
            </td>
            <td className={`px-3 py-3 text-right tabular-nums whitespace-nowrap align-top ${muted ? '' : 'font-semibold text-gray-900'}`}>{fmtMoney(line.balance)}</td>
            {canWrite && (
                <td className="px-3 py-3 whitespace-nowrap align-top">
                    {cancellable && (
                        <button type="button" onClick={onCancel} className="text-xs text-red-700 hover:underline">Cancel</button>
                    )}
                </td>
            )}
        </tr>
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

function Th({ children, right = false }) {
    return (
        <th className={`px-3 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap ${right ? 'text-right' : 'text-left'}`}>
            {children}
        </th>
    )
}
