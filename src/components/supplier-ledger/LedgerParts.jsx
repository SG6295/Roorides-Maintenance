import { useState } from 'react'
import { Link } from 'react-router-dom'
import { invoiceOwner, LINE_TAGS, isVoided, entryDay } from '../../utils/supplierLedger'
import { batchPath } from '../../utils/batchNumber'
import { purchaseInvoicePath } from '../../utils/purchaseInvoice'
import { todayLocal } from '../../utils/datetime'
import { fmtMoney, fmtDate, fmtDateTime } from '../outsource-invoices/format'

/**
 * The pieces a supplier's statement and a person's advances statement share (MAIN-119):
 * the figure tiles, the "still open" table and the statement itself.
 */

export function Tile({ label, value, note, tone = '', highlight = false }) {
    return (
        <div className={`bg-white rounded-xl shadow-sm p-4 ${highlight ? 'border-2 border-amber-400' : 'border border-gray-200'}`}>
            <p className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">{label}</p>
            <p className={`text-2xl font-bold text-gray-900 ${tone}`}>{value}</p>
            {note && <p className="text-xs text-gray-500 mt-0.5">{note}</p>}
        </div>
    )
}

export function OwnerLink({ line }) {
    const owner = invoiceOwner(line)
    if (!owner) return null
    const to = owner.purchaseInvoiceId
        ? purchaseInvoicePath(owner.purchaseInvoiceId)
        : owner.jobCardNumber != null ? `/job-cards/${owner.jobCardNumber}` : batchPath(owner.batchNumber)
    return <Link to={to} className="text-blue-600 hover:underline">{owner.label}</Link>
}

const BUCKETS = {
    overdue:        { label: 'Overdue',        className: 'text-red-700' },
    this_wednesday: { label: 'This Wednesday', className: 'text-amber-700' },
    next_wednesday: { label: 'Next Wednesday', className: 'text-gray-700' },
    later:          { label: 'Later',          className: 'text-gray-500' },
}

/** What is still open, oldest due first, and which Wednesday run it goes in. */
export function OpenItems({ items, showSupplier = false }) {
    if (items.length === 0) return null
    return (
        <section className="bg-white rounded-xl border border-gray-200 shadow-sm p-4">
            <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-1">Still open</h2>
            <p className="text-xs text-gray-500 mb-3">Payments clear the earliest-due items first. This is how the balance splits across Wednesday runs.</p>
            <div className="overflow-x-auto">
                <table className="min-w-full text-sm">
                    <thead>
                        <tr className="text-xs text-gray-500 uppercase tracking-wide">
                            <th className="text-left font-medium py-1 pr-3">Item</th>
                            {showSupplier && <th className="text-left font-medium py-1 px-3">Supplier</th>}
                            <th className="text-left font-medium py-1 px-3">Due</th>
                            <th className="text-left font-medium py-1 px-3">Run</th>
                            <th className="text-right font-medium py-1 px-3">Open</th>
                            <th className="text-left font-medium py-1 pl-3">When</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100">
                        {items.map(o => {
                            const b = BUCKETS[o.bucket]
                            return (
                                <tr key={o.line_id + (o.kind ?? '')}>
                                    <td className="py-2 pr-3 whitespace-nowrap">
                                        {o.kind === 'adjustment' ? 'Reconciliation adjustment' : <>{o.invoice_no} · <OwnerLink line={o} /></>}
                                    </td>
                                    {showSupplier && <td className="py-2 px-3 whitespace-nowrap">{o.supplier}</td>}
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
    )
}

/**
 * The statement, in recording order with its running balance. Date filter and a switch
 * to hide cancelled/reversed lines run here; `actionFor(line)` gives a row's button.
 */
export function LedgerTable({ lines, loading, describe, actionFor, hasActions, emptyText }) {
    const [from, setFrom] = useState('')
    const [to, setTo] = useState('')
    const [showVoided, setShowVoided] = useState(true)
    const today = todayLocal()

    const visible = lines.filter(l => {
        const day = entryDay(l)
        return (!from || day >= from) && (!to || day <= to) && (showVoided || !isVoided(l))
    })
    // Totals over what is shown, in paise so they add up exactly.
    const paise = v => Math.round(Number(v) * 100)
    const owedTotal = visible.reduce((s, l) => s + (l.counts && Number(l.amount) > 0 ? paise(l.amount) : 0), 0) / 100
    const paidTotal = visible.reduce((s, l) => s + (l.counts && Number(l.amount) < 0 ? -paise(l.amount) : 0), 0) / 100
    const closing = visible.length ? visible[visible.length - 1].balance : 0

    return (
        <>
            <div className="flex flex-wrap items-center gap-3 text-sm">
                <span className="text-gray-500">Entered from</span>
                <input type="date" aria-label="From date" value={from} max={to || today} onChange={e => setFrom(e.target.value)} className="border border-gray-300 rounded-lg px-2 py-1.5" />
                <span className="text-gray-500">to</span>
                <input type="date" aria-label="To date" value={to} min={from || undefined} max={today} onChange={e => setTo(e.target.value)} className="border border-gray-300 rounded-lg px-2 py-1.5" />
                <label className="flex items-center gap-2 text-gray-700 ml-2">
                    <input type="checkbox" checked={showVoided} onChange={e => setShowVoided(e.target.checked)} />
                    Show cancelled and reversed entries
                </label>
            </div>

            <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-x-auto">
                {loading ? (
                    <div className="p-8 text-center text-sm text-gray-500">Loading…</div>
                ) : visible.length === 0 ? (
                    <div className="p-8 text-center text-sm text-gray-400">{lines.length === 0 ? emptyText : 'No entries in this range.'}</div>
                ) : (
                    <table className="min-w-full divide-y divide-gray-200 text-sm">
                        <thead className="bg-gray-50">
                            <tr>
                                <Th>Entered</Th>
                                <Th>Entry</Th>
                                <Th right>Owed</Th>
                                <Th right>Paid</Th>
                                <Th right>Balance</Th>
                                {hasActions && <th className="px-3 py-3" aria-label="Actions" />}
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100">
                            {visible.map(l => (
                                <Row key={l.kind + l.line_id} line={l} describe={describe} action={actionFor?.(l)} hasActions={hasActions} />
                            ))}
                        </tbody>
                        <tfoot>
                            <tr className="border-t-2 border-gray-200 font-semibold">
                                <td className="px-3 py-3" colSpan={2}>Closing balance{to ? `, end of ${fmtDate(to)}` : ''}</td>
                                <td className="px-3 py-3 text-right tabular-nums">{fmtMoney(owedTotal)}</td>
                                <td className="px-3 py-3 text-right tabular-nums">{fmtMoney(paidTotal)}</td>
                                <td className="px-3 py-3 text-right tabular-nums font-bold">{fmtMoney(closing)}</td>
                                {hasActions && <td />}
                            </tr>
                        </tfoot>
                    </table>
                )}
            </div>
            {from && <p className="text-xs text-gray-500">Owed and Paid totals cover the entries shown; Balance is the running balance.</p>}
        </>
    )
}

function Row({ line, describe, action, hasActions }) {
    const { title, sub } = describe(line)
    const tag = LINE_TAGS[line.kind]
    const amount = Number(line.amount)
    const voided = isVoided(line)
    const showOwner = line.kind === 'invoice' || line.kind === 'advance'

    return (
        <tr className={voided ? 'bg-gray-50/70 text-gray-500' : 'text-gray-700'}>
            <td className="px-3 py-3 whitespace-nowrap align-top">{fmtDateTime(line.entry_at)}</td>
            <td className="px-3 py-3 align-top min-w-[22rem]">
                <span className={`inline-block text-[11px] font-semibold px-2 py-0.5 rounded-full mr-2 ${tag?.className}`}>{tag?.label}</span>
                <span className={voided ? 'line-through' : ''}>{title}</span>
                {showOwner && invoiceOwner(line) && <> · <OwnerLink line={line} /></>}
                {sub && <span className="block text-xs text-gray-500 mt-0.5">{sub}</span>}
            </td>
            <td className={`px-3 py-3 text-right tabular-nums whitespace-nowrap align-top ${voided ? 'line-through text-gray-400' : ''}`}>{amount > 0 ? fmtMoney(amount) : ''}</td>
            <td className={`px-3 py-3 text-right tabular-nums whitespace-nowrap align-top ${voided ? 'line-through text-gray-400' : ''}`}>{amount < 0 ? fmtMoney(-amount) : ''}</td>
            <td className={`px-3 py-3 text-right tabular-nums whitespace-nowrap align-top ${voided ? '' : 'font-semibold text-gray-900'}`}>{fmtMoney(line.balance)}</td>
            {hasActions && (
                <td className="px-3 py-3 whitespace-nowrap align-top">
                    {action && <button type="button" onClick={action.onClick} className="text-xs text-red-700 hover:underline">{action.label}</button>}
                </td>
            )}
        </tr>
    )
}

function Th({ children, right = false }) {
    return (
        <th className={`px-3 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap ${right ? 'text-right' : 'text-left'}`}>
            {children}
        </th>
    )
}
