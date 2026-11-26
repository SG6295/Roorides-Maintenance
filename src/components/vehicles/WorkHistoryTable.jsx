import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import FormulaTip from '../shared/FormulaTip'
import FilterSelect from '../shared/FilterSelect'
import { mechanicPath } from '../../utils/employeeId'
import { batchPath, formatBatchNumber } from '../../utils/batchNumber'
import { workTypeLabel } from '../../constants/batchWorkTypes'
import { companyShortLabel } from '../../constants/vehicleCompanies'
import { issueLabourHours, formatHours } from '../../utils/labour'
import { inr, inrExact, istDayOf, explainSplit } from '../../utils/maintenanceCost'
import { format, parseISO } from 'date-fns'

const PAGE = 25
const ACCEPTED = ['Accepted', 'GST reconciled & closed', 'GST not applicable & closed']

const STATUS_BADGE = {
    Completed: 'bg-green-100 text-green-800',
    Open: 'bg-blue-100 text-blue-800',
    'Completed - Invoice Pending': 'bg-amber-100 text-amber-800',
}

const Badge = ({ className, children }) => (
    <span className={`inline-block px-2 py-0.5 rounded-full text-[11px] whitespace-nowrap ${className}`}>{children}</span>
)

/** An embedded one-to-one row arrives as an object or a one-item array. */
const one = v => (Array.isArray(v) ? v[0] ?? null : v ?? null)

// day is an Indian date 'YYYY-MM-DD'; parseISO reads it as a calendar date, no zone shift.
const dateText = day => (day ? format(parseISO(day), 'd MMM yyyy') : '—')

/** One work history row from a job card. */
function jobCardRow(jc) {
    const issues = [...(jc.issues || [])].sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)))
    const tickets = [...new Set(issues.map(i => i.ticket?.ticket_number).filter(Boolean))].sort((a, b) => a - b)
    const invoice = one(jc.invoice)
    const spares = issues.flatMap(i => (i.issue_parts || []).map(p => ({ ...p, issueId: i.id })))
    const searchText = [
        ...issues.map(i => i.description),
        ...spares.map(p => p.part?.name),
        ...issues.flatMap(i => (i.issue_labour || []).map(l => l.technician?.name)),
        jc.supplier?.entity_name,
    ].filter(Boolean).join(' ').toLowerCase()
    return {
        kind: 'job_card',
        key: jc.id,
        day: istDayOf(jc.created_at),
        jc, issues, tickets, invoice, spares, searchText,
        categories: new Set(issues.map(i => i.category)),
    }
}

/** One work history row from a multi-vehicle invoice line. */
function mviRow(line, awaiting) {
    const b = line.batch
    return {
        kind: 'mvi',
        key: line.id,
        day: one(b.invoice)?.date_of_activity ?? istDayOf(b.created_at),
        line, batch: b, awaiting,
        searchText: [workTypeLabel(line), b.supplier?.entity_name].filter(Boolean).join(' ').toLowerCase(),
        categories: new Set([`Multi-vehicle: ${workTypeLabel(line)}`]),
    }
}

/**
 * The vehicle's work history (MAIN-164): every job card and multi-vehicle invoice line in
 * the period, newest first, with every detail in its row — nothing to open.
 * `awaitingMvi` is the set of MVI line ids finance has not yet accepted (from the cost lines).
 */
export default function WorkHistoryTable({ jobCards, batchLines, period, awaitingMvi, category, onCategoryChange, categoryOptions }) {
    const [search, setSearch] = useState('')
    const [type, setType] = useState('')
    const [showAll, setShowAll] = useState(false)

    const rows = useMemo(() => {
        const all = [
            ...jobCards.map(jobCardRow),
            ...batchLines.filter(l => l.batch?.status !== 'Cancelled').map(l => mviRow(l, awaitingMvi.has(l.id))),
        ]
        return all
            .filter(r => r.day && r.day >= period.start && r.day <= period.end)
            .sort((a, b) => b.day.localeCompare(a.day) || String(b.key).localeCompare(String(a.key)))
    }, [jobCards, batchLines, period, awaitingMvi])

    const filtered = useMemo(() => {
        const q = search.trim().toLowerCase()
        return rows.filter(r =>
            (!type || r.kind === type) &&
            (!category || r.categories.has(category)) &&
            (!q || r.searchText.includes(q))
        )
    }, [rows, search, type, category])

    const shown = showAll ? filtered : filtered.slice(0, PAGE)
    const listedValue = filtered.reduce((s, r) => s + Number(r.kind === 'mvi' ? r.line.amount : r.jc.value ?? 0), 0)
    const cardCount = filtered.filter(r => r.kind === 'job_card').length
    const mviCount = filtered.length - cardCount

    return (
        <section className="bg-white rounded-xl border border-gray-200 overflow-hidden" aria-label="Work history">
            <div className="px-5 py-4 flex flex-wrap gap-3 justify-between items-center border-b border-gray-200">
                <div>
                    <h2 className="text-base font-semibold text-gray-900">Work history</h2>
                    <p className="text-xs text-gray-600 mt-0.5">
                        Everything on each job card, with nothing to open. Odometer: the reading typed on the job card, and
                        Roorides' reading when the card was created (from MAIN-169).
                    </p>
                </div>
                <div className="flex flex-wrap gap-2 items-center">
                    <label className="flex items-center gap-1.5 text-sm text-gray-600">
                        Search
                        <input
                            type="search"
                            value={search}
                            onChange={e => setSearch(e.target.value)}
                            placeholder="Issue, part or technician"
                            className="border border-gray-300 rounded-lg px-2.5 py-1.5 text-sm w-52"
                        />
                    </label>
                    <FilterSelect value={category ?? ''} onChange={v => onCategoryChange(v || null)} placeholder="All categories" options={categoryOptions.map(c => ({ value: c, label: c }))} />
                    <FilterSelect
                        value={type}
                        onChange={setType}
                        placeholder="Job cards + multi-vehicle invoices"
                        options={[{ value: 'job_card', label: 'Job cards' }, { value: 'mvi', label: 'Multi-vehicle invoices' }]}
                    />
                </div>
            </div>

            {filtered.length === 0 ? (
                <p className="p-10 text-center text-sm text-gray-500">
                    {rows.length ? 'Nothing matches these filters.' : 'No job cards or multi-vehicle invoices in this period.'}
                </p>
            ) : (
                <div className="overflow-x-auto">
                    <table className="w-full text-sm min-w-[1150px]">
                        <thead>
                            <tr className="bg-gray-50 text-[11px] text-gray-600 uppercase tracking-wide text-left">
                                <th scope="col" className="pl-5 pr-2 py-2.5 font-semibold w-[100px]">Date</th>
                                <th scope="col" className="px-2 py-2.5 font-semibold w-[96px]">Job card</th>
                                <th scope="col" className="px-2 py-2.5 font-semibold w-[118px]">Status</th>
                                <th scope="col" className="px-2 py-2.5 font-semibold w-[120px]">Workshop</th>
                                <th scope="col" className="px-2 py-2.5 font-semibold w-[160px]">Odometer (km)</th>
                                <th scope="col" className="px-2 py-2.5 font-semibold">Work done &amp; labour</th>
                                <th scope="col" className="px-2 py-2.5 font-semibold">Spares / vendor (cost incl. GST)</th>
                                <th scope="col" className="pl-2 pr-5 py-2.5 font-semibold text-right w-[96px]">Value</th>
                            </tr>
                        </thead>
                        <tbody>
                            {shown.map(r => (r.kind === 'job_card' ? <JobCardRow key={r.key} row={r} /> : <MviRow key={r.key} row={r} />))}
                        </tbody>
                    </table>
                </div>
            )}

            <div className="px-5 py-3 border-t border-gray-200 flex flex-wrap gap-2 justify-between text-sm text-gray-600">
                <span>
                    Showing {shown.length} of {filtered.length} · {cardCount} job card{cardCount === 1 ? '' : 's'}
                    {mviCount > 0 && ` · ${mviCount} multi-vehicle invoice line${mviCount === 1 ? '' : 's'}`} · value of all listed {inr(listedValue)}
                </span>
                {filtered.length > PAGE && (
                    <button type="button" onClick={() => setShowAll(s => !s)} className="text-blue-700 hover:underline">
                        {showAll ? 'Show fewer' : 'Show all'}
                    </button>
                )}
            </div>
        </section>
    )
}

function JobCardRow({ row }) {
    const { jc, issues, tickets, invoice, spares } = row
    const outsourced = jc.type === 'Outsource'
    const awaiting = outsourced && invoice?.approved_amount != null && !ACCEPTED.includes(invoice.finance_payment_status)
    const splitCount = issues.length
    const split = outsourced && invoice?.approved_amount != null && splitCount > 1
        ? { approved: Number(invoice.approved_amount), count: splitCount, share: Number(invoice.approved_amount) / splitCount, jobCardNumber: jc.job_card_number }
        : null

    return (
        <tr className="border-t border-gray-200 align-top">
            <td className="pl-5 pr-2 py-3 font-semibold whitespace-nowrap">{dateText(row.day)}</td>
            <td className="px-2 py-3 leading-relaxed">
                <Link to={`/job-cards/${jc.job_card_number}`} className="text-blue-700 hover:underline">JC-{jc.job_card_number}</Link>
                {tickets.map(t => (
                    <div key={t}><Link to={`/tickets/${t}`} className="text-xs text-blue-700 hover:underline">Ticket {t}</Link></div>
                ))}
            </td>
            <td className="px-2 py-3 space-y-1">
                <div><Badge className={STATUS_BADGE[jc.status] ?? 'bg-gray-100 text-gray-700'}>{jc.status}</Badge></div>
                {awaiting && <div><Badge className="bg-amber-100 text-amber-900">Awaiting finance</Badge></div>}
            </td>
            <td className="px-2 py-3 leading-relaxed">
                <div>{outsourced ? 'Outsourced' : 'In-house'}</div>
                <div className="text-gray-600">{outsourced ? (jc.supplier?.entity_name || 'Vendor not set') : (jc.location?.name || '—')}</div>
            </td>
            <td className="px-2 py-3 text-xs leading-relaxed whitespace-nowrap">
                <div>
                    {jc.odometer != null
                        ? <strong className="text-gray-900">{Number(jc.odometer).toLocaleString('en-IN')}</strong>
                        : <span className="text-gray-500">Not recorded</span>}{' '}
                    <span className="text-gray-600">(job card)</span>
                </div>
                <div><span className="text-gray-500">—</span> <span className="text-gray-600">(Roorides)</span></div>
            </td>
            <td className="px-2 py-3 leading-relaxed">
                {issues.length === 0 && <span className="text-gray-500">No work items</span>}
                {issues.map(i => {
                    const labour = issueLabourHours(i)
                    const techs = (i.issue_labour || []).filter(l => l.technician)
                    return (
                        <div key={i.id} className="mb-1.5 last:mb-0">
                            <div>
                                <Badge className="bg-gray-100 text-gray-800 mr-1.5">{i.category}</Badge>
                                <strong>{i.description || 'No description'}</strong>{' '}
                                <span className={i.status === 'Done' ? 'text-green-800' : 'text-gray-600'}>· {i.status}</span>
                            </div>
                            <div className="text-gray-600 text-xs">
                                {outsourced
                                    ? 'Done by vendor'
                                    : techs.length
                                        ? techs.map((l, idx) => (
                                            <span key={l.id}>
                                                {idx > 0 && ', '}
                                                <Link to={mechanicPath(l.technician.employee_id)} className="text-blue-700 hover:underline">{l.technician.name}</Link>
                                                {' '}· {formatHours(Number(l.hours))} h
                                            </span>
                                        ))
                                        : labour.hours > 0 ? `${formatHours(labour.hours)} h · no technician recorded` : 'No labour recorded'}
                            </div>
                        </div>
                    )
                })}
            </td>
            <td className="px-2 py-3 leading-relaxed">
                {outsourced ? (
                    invoice?.approved_amount != null ? (
                        <>
                            <div>Invoice {invoice.invoice_no || '—'} · Approved {inrExact(invoice.approved_amount)}</div>
                            {split && (
                                <div className="flex items-center gap-1.5 text-xs text-blue-800 mt-1">
                                    <FormulaTip title="How the categories were split" label="How the categories were split" text={explainSplit(split)} align="left" />
                                    Split across {split.count} categories
                                </div>
                            )}
                        </>
                    ) : <span className="text-gray-500">Invoice pending</span>
                ) : spares.length === 0 ? (
                    <span className="text-gray-500">No spares used</span>
                ) : (
                    spares.map(p => {
                        const qty = Number(p.quantity_used)
                        const unitCost = p.cost != null && qty > 1 ? Number(p.cost) / qty : null
                        return (
                            <div key={p.id} className="flex justify-between gap-3">
                                <span>
                                    {p.part?.name} · {qty.toLocaleString('en-IN')} {p.part?.unit}
                                    {unitCost != null && ` × ${inrExact(unitCost)}`}
                                    {p.transfer && p.transfer.status !== 'Reversed' && (
                                        <span className="block text-xs text-purple-800">Transferred from {companyShortLabel(p.transfer.from_company)}</span>
                                    )}
                                </span>
                                <span className="whitespace-nowrap">{p.cost != null ? inrExact(p.cost) : <span className="text-amber-800">Price missing</span>}</span>
                            </div>
                        )
                    })
                )}
            </td>
            <td className="pl-2 pr-5 py-3 text-right font-bold whitespace-nowrap">
                {jc.value != null ? inr(jc.value) : <span className="font-normal text-gray-500">{outsourced ? 'Invoice pending' : 'Price missing'}</span>}
            </td>
        </tr>
    )
}

function MviRow({ row }) {
    const { line, batch, awaiting } = row
    return (
        <tr className="border-t border-gray-200 align-top">
            <td className="pl-5 pr-2 py-3 font-semibold whitespace-nowrap">{dateText(row.day)}</td>
            <td className="px-2 py-3">
                <Link to={batchPath(batch.batch_number)} className="px-2 py-0.5 rounded-full bg-indigo-50 text-indigo-800 text-xs hover:underline">
                    {formatBatchNumber(batch.batch_number)}
                </Link>
            </td>
            <td className="px-2 py-3">{awaiting ? <Badge className="bg-amber-100 text-amber-900">Awaiting finance</Badge> : <Badge className="bg-green-100 text-green-800">Accepted</Badge>}</td>
            <td className="px-2 py-3 leading-relaxed">
                <div>Multi-vehicle invoice</div>
                <div className="text-gray-600">{batch.supplier?.entity_name || '—'}</div>
            </td>
            <td className="px-2 py-3 text-xs text-gray-500">No job card</td>
            <td className="px-2 py-3 leading-relaxed">
                <div><Badge className="bg-gray-100 text-gray-800 mr-1.5">{workTypeLabel(line)}</Badge>{line.site && <span className="text-gray-600">Site {line.site}</span>}</div>
                {line.linked_job_card && (
                    <div className="text-xs">Linked to <Link to={`/job-cards/${line.linked_job_card.job_card_number}`} className="text-blue-700 hover:underline">JC-{line.linked_job_card.job_card_number}</Link></div>
                )}
            </td>
            <td className="px-2 py-3 leading-relaxed">
                <div>Invoice {one(batch.invoice)?.invoice_no || '—'}</div>
                {line.rate != null && <div>{line.quantity} × {inrExact(line.rate)} for this vehicle</div>}
            </td>
            <td className="pl-2 pr-5 py-3 text-right font-bold">{inr(line.amount)}</td>
        </tr>
    )
}
