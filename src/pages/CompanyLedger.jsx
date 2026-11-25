import { useState } from 'react'
import { Link, Navigate, useParams } from 'react-router-dom'
import Navigation from '../components/shared/Navigation'
import { Tile } from '../components/supplier-ledger/LedgerParts'
import ReasonModal from '../components/supplier-ledger/ReasonModal'
import ReconcileCompanyModal from '../components/company-ledger/ReconcileCompanyModal'
import { useCompanyLedger, useReverseCompanyLedgerAdjustment } from '../hooks/useCompanyLedger'
import { useAuth } from '../hooks/useAuth'
import { useToast } from '../hooks/useFeedback'
import {
    LEDGER_COMPANIES, ENTRY_TAGS, GST_STATUSES, RECONCILE_FIGURES, companyFromSlug, companyLedgerPath,
    describeEntry, owedWording, ledgerTotals, linesInRange, isAdjustment, isSigned, isVoided, lineAmount, lastReconciled,
} from '../utils/companyLedger'
import { companyLabel } from '../constants/vehicleCompanies'
import { LEDGER_WRITE_ROLES } from '../constants/supplierLedger'
import { exportCompanyLedger } from '../utils/companyLedgerExport'
import { todayLocal } from '../utils/datetime'
import { fmtMoney, fmtDate, fmtDateTime } from '../components/outsource-invoices/format'

/**
 * One company's ledger (MAIN-156, epic MAIN-154): every purchase and accepted invoice
 * billed to it, and every vehicle sale between the two companies, in the order recorded.
 * Two running columns — spent to date, and owed between the companies — because adding
 * them together would mean nothing. Every line is derived, except the reconciliation
 * adjustments finance and super_admin post against Tally (MAIN-163) — each figure on its own.
 */
export default function CompanyLedger() {
    const { company: slug } = useParams()
    const company = companyFromSlug(slug)
    if (!company) return <Navigate to={companyLedgerPath('nvs_travels')} replace />
    return <Ledger key={company} company={company} />
}

function Ledger({ company }) {
    const { data: lines = [], isLoading, error } = useCompanyLedger(company)
    const [from, setFrom] = useState('')
    const [to, setTo] = useState('')
    const today = todayLocal()
    const name = companyLabel(company)
    const { userProfile } = useAuth()
    const canWrite = LEDGER_WRITE_ROLES.includes(userProfile?.role)
    const reverse = useReverseCompanyLedgerAdjustment()
    const toast = useToast()
    const [dialog, setDialog] = useState(null)
    const close = () => setDialog(null)
    const reconciledNote = balance => {
        const day = lastReconciled(lines, balance)
        return day ? `Last reconciled as of ${fmtDate(day)}` : 'Not reconciled yet'
    }

    const all = ledgerTotals(lines)
    const last = lines[lines.length - 1]
    const visible = linesInRange(lines, from, to)
    const shown = ledgerTotals(visible)

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Company ledger', href: '/company-ledger' }, { label: name }]} />
            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6 space-y-5">
                <div className="flex flex-wrap items-start justify-between gap-4">
                    <div>
                        <h1 className="text-2xl font-bold text-gray-900">Company ledger</h1>
                        <div className="mt-2 inline-flex rounded-lg border border-gray-300 bg-white p-0.5" role="tablist">
                            {LEDGER_COMPANIES.map(c => (
                                <Link
                                    key={c.value}
                                    to={companyLedgerPath(c.value)}
                                    role="tab"
                                    aria-selected={c.value === company}
                                    className={`px-3 py-1.5 text-sm rounded-md ${c.value === company ? 'bg-blue-600 text-white font-medium' : 'text-gray-700 hover:bg-gray-50'}`}
                                >
                                    {c.label}
                                </Link>
                            ))}
                        </div>
                    </div>
                    <div className="flex flex-wrap gap-2">
                        {canWrite && (
                            <button
                                type="button"
                                onClick={() => setDialog({ type: 'reconcile' })}
                                disabled={isLoading || !!error}
                                className="text-sm px-3 py-2 text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50"
                            >
                                Reconcile with Tally
                            </button>
                        )}
                        <button
                            type="button"
                            onClick={() => exportCompanyLedger(company, visible, today)}
                            disabled={visible.length === 0}
                            className="text-sm px-3 py-2 text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50"
                        >
                            Export to Excel
                        </button>
                    </div>
                </div>

                {error ? (
                    <div className="p-8 text-center text-sm text-red-600">Could not load the ledger: {error.message}</div>
                ) : (
                    <>
                        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                            <Tile label="Spent to date" value={fmtMoney(all.spent)} note={`Purchases and invoices, incl. GST · ${reconciledNote('spent')}`} />
                            <Tile label="GST in spending" value={fmtMoney(all.spendGst)} note={all.gstNotRecorded > 0 ? `+ ${all.gstNotRecorded} invoice${all.gstNotRecorded === 1 ? '' : 's'} with GST not recorded` : 'Included in Spent to date'} />
                            <Tile
                                label="Owed between companies"
                                value={fmtMoney(Math.abs(Number(last?.owed_balance ?? 0)))}
                                note={`${owedWording(last?.owed_balance, company)} · ${reconciledNote('owed')}`}
                                highlight
                            />
                        </div>

                        <GstBreakdown totals={all} />

                        <div className="flex flex-wrap items-center gap-3 text-sm">
                            <span className="text-gray-500">Entered from</span>
                            <input type="date" aria-label="From date" value={from} max={to || today} onChange={e => setFrom(e.target.value)} className="border border-gray-300 rounded-lg px-2 py-1.5" />
                            <span className="text-gray-500">to</span>
                            <input type="date" aria-label="To date" value={to} min={from || undefined} max={today} onChange={e => setTo(e.target.value)} className="border border-gray-300 rounded-lg px-2 py-1.5" />
                        </div>

                        <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-x-auto">
                            {isLoading ? (
                                <div className="p-8 text-center text-sm text-gray-500">Loading…</div>
                            ) : visible.length === 0 ? (
                                <div className="p-8 text-center text-sm text-gray-400">
                                    {lines.length === 0 ? `Nothing in ${name}'s ledger yet.` : 'No entries in this range.'}
                                </div>
                            ) : (
                                <table className="min-w-full divide-y divide-gray-200 text-sm">
                                    <thead className="bg-gray-50">
                                        <tr>
                                            <Th>Entered</Th>
                                            <Th>Entry</Th>
                                            <Th right>Amount</Th>
                                            <Th right>GST</Th>
                                            <Th>GST status</Th>
                                            <Th right>Spent to date</Th>
                                            <Th right>Owed between companies</Th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-100">
                                        {visible.map(l => (
                                            <Row
                                                key={l.kind + l.line_id}
                                                line={l}
                                                company={company}
                                                onReverse={canWrite && l.kind === 'adjustment' ? () => setDialog({ type: 'reverse', line: l }) : null}
                                            />
                                        ))}
                                    </tbody>
                                    <tfoot>
                                        <tr className="border-t-2 border-gray-200 font-semibold">
                                            <td className="px-3 py-3" colSpan={2}>
                                                {visible.length} entr{visible.length === 1 ? 'y' : 'ies'}{to ? `, to end of ${fmtDate(to)}` : ''}
                                                <span className="block text-xs font-normal text-gray-500">Amount and GST totals: spending only, with its adjustments</span>
                                            </td>
                                            <td className="px-3 py-3 text-right tabular-nums whitespace-nowrap">{fmtMoney(shown.spent)}</td>
                                            <td className="px-3 py-3 text-right tabular-nums whitespace-nowrap">{fmtMoney(shown.spendGst)}</td>
                                            <td />
                                            <td className="px-3 py-3 text-right tabular-nums whitespace-nowrap font-bold">{fmtMoney(visible[visible.length - 1].spent_to_date)}</td>
                                            <td className="px-3 py-3 text-right tabular-nums whitespace-nowrap font-bold">
                                                <Owed value={visible[visible.length - 1].owed_balance} company={company} />
                                            </td>
                                        </tr>
                                    </tfoot>
                                </table>
                            )}
                        </div>
                        {(from || to) && visible.length > 0 && (
                            <p className="text-xs text-gray-500">The Amount and GST totals cover the spending in the entries shown. The last two columns are running totals from the first entry in the ledger.</p>
                        )}

                        <p className="text-xs text-gray-500">
                            An invoice enters when finance accepts it, and leaves again if it goes back to Hold or on to Reject.
                            A purchase recorded before purchases went to finance counts from when it was recorded. Spares used on
                            an in-house job card are not entered: their cost was counted when the stock was bought. A vehicle bought
                            from the other company counts in Owed between companies, not in Spent. A spare transferred from the other
                            company&apos;s stock to this company&apos;s vehicle adds to this company&apos;s Spent and to what it owes; one
                            transferred to the other company&apos;s vehicle takes it off this company&apos;s Spent and is owed back. Removing
                            the spare reverses it on the day it was removed. A reconciliation adjustment
                            moves only the figure it reconciles, and has no GST.
                        </p>
                    </>
                )}
            </div>

            {dialog?.type === 'reconcile' && (
                <ReconcileCompanyModal
                    company={company}
                    lines={lines}
                    onClose={close}
                    onDone={agree => {
                        close()
                        toast.success(agree ? 'Reconciliation recorded — the figures agree.' : 'Adjustment posted.')
                    }}
                />
            )}
            {dialog?.type === 'reverse' && (
                <ReasonModal
                    title="Reverse adjustment"
                    subtitle={`${RECONCILE_FIGURES[dialog.line.detail?.balance]?.label ?? ''} · as of ${fmtDate(dialog.line.detail?.as_of)} · ${signedMoney(lineAmount(dialog.line))}`}
                    intro="For an adjustment posted in error. It stays on the ledger, struck through, and the figure goes back to what it was without it."
                    keepLabel="Keep adjustment"
                    confirmLabel="Reverse adjustment"
                    mutation={reverse}
                    onConfirm={reason => reverse.mutate({ adjustmentId: dialog.line.line_id, reason }, {
                        onSuccess: () => { close(); toast.success('Adjustment reversed.') },
                    })}
                    onClose={close}
                />
            )}
        </div>
    )
}

const signedMoney = v => (v === 0 ? fmtMoney(0) : `${v < 0 ? '−' : '+'} ${fmtMoney(Math.abs(v))}`)

function GstBreakdown({ totals }) {
    const parts = Object.entries(GST_STATUSES).filter(([k]) => totals.gstByStatus[k] !== 0)
    if (parts.length === 0 && totals.gstNotRecorded === 0) return null
    return (
        <section className="bg-white rounded-xl border border-gray-200 shadow-sm p-4">
            <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">GST by status</h2>
            <dl className="flex flex-wrap gap-x-8 gap-y-3 text-sm">
                {parts.map(([k, s]) => (
                    <div key={k}>
                        <dt className={`text-xs font-medium ${s.className}`}>{s.label}</dt>
                        <dd className="font-semibold text-gray-900 tabular-nums">{fmtMoney(totals.gstByStatus[k])}</dd>
                    </div>
                ))}
                {totals.gstNotRecorded > 0 && (
                    <div>
                        <dt className="text-xs font-medium text-gray-500">Not recorded</dt>
                        <dd className="text-gray-700">
                            {totals.gstNotRecorded} job card / multi-vehicle invoice{totals.gstNotRecorded === 1 ? '' : 's'} ({fmtMoney(totals.gstNotRecordedAmount)})
                        </dd>
                    </div>
                )}
            </dl>
            <p className="text-xs text-gray-500 mt-3">
                Claimed = GST reconciled &amp; closed · No GST = GST not applicable &amp; closed · Not yet reconciled = still Accepted ·
                Unknown = a purchase recorded before purchases went to finance.
                A job card or multi-vehicle invoice counts its bill&apos;s GST in proportion to the Approved Amount
                (GST × Approved ÷ Invoice Value); Not recorded = an invoice saved without a GST breakdown.
            </p>
        </section>
    )
}

function Row({ line, company, onReverse }) {
    const { title, sub, link } = describeEntry(line, company)
    const tag = ENTRY_TAGS[line.kind]
    const adjustment = isAdjustment(line)
    const signed = isSigned(line)
    const status = adjustment ? null : GST_STATUSES[line.gst_status]
    const amount = lineAmount(line)
    const voided = isVoided(line) ? 'line-through text-gray-400' : ''
    return (
        <tr className="text-gray-700">
            <td className="px-3 py-3 whitespace-nowrap align-top">{fmtDateTime(line.entry_at)}</td>
            <td className="px-3 py-3 align-top min-w-[22rem]">
                <span className={`inline-block text-[11px] font-semibold px-2 py-0.5 rounded-full mr-2 ${tag?.className ?? 'bg-gray-100 text-gray-700'}`}>{tag?.label ?? line.kind}</span>
                <span className={voided}>{title}</span>
                {link && <> · <Link to={link.to} className="text-blue-600 hover:underline">{link.label}</Link></>}
                {sub && <span className="block text-xs text-gray-500 mt-0.5">{sub}</span>}
                {onReverse && (
                    <button type="button" onClick={onReverse} className="block text-xs text-red-600 hover:underline mt-1">Reverse</button>
                )}
            </td>
            <td className={`px-3 py-3 text-right tabular-nums whitespace-nowrap align-top ${voided}`}>
                {signed ? signedMoney(amount) : fmtMoney(amount)}
                {adjustment && <span className="block text-[11px] font-normal text-gray-500 no-underline">{RECONCILE_FIGURES[line.detail?.balance]?.label}</span>}
            </td>
            <td className="px-3 py-3 text-right tabular-nums whitespace-nowrap align-top">
                {adjustment ? <span className="text-gray-400">—</span>
                    : line.gst == null ? <span className="text-xs text-gray-400">Not recorded</span>
                    : signed ? signedMoney(Number(line.gst)) : fmtMoney(line.gst)}
            </td>
            <td className={`px-3 py-3 whitespace-nowrap align-top text-xs font-medium ${status?.className ?? ''}`}>{adjustment ? '' : status?.label ?? line.gst_status}</td>
            <td className="px-3 py-3 text-right tabular-nums whitespace-nowrap align-top font-semibold text-gray-900">{fmtMoney(line.spent_to_date)}</td>
            <td className="px-3 py-3 text-right tabular-nums whitespace-nowrap align-top font-semibold text-gray-900">
                <Owed value={line.owed_balance} company={company} />
            </td>
        </tr>
    )
}

function Owed({ value, company }) {
    return (
        <>
            {fmtMoney(Math.abs(Number(value ?? 0)))}
            <span className="block text-[11px] font-normal text-gray-500">{owedWording(value, company)}</span>
        </>
    )
}

function Th({ children, right = false }) {
    return (
        <th className={`px-3 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wide whitespace-nowrap ${right ? 'text-right' : 'text-left'}`}>
            {children}
        </th>
    )
}
