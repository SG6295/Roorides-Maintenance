import { STOCK_COMPANIES, companyLabel, companyShortLabel } from '../constants/vehicleCompanies'
import { formatPurchaseNumber, purchaseInvoicePath } from './purchaseInvoice'
import { formatBatchNumber, batchPath } from './batchNumber'
import { formatAs, toDate } from './datetime'

/**
 * The company ledgers (MAIN-156, epic MAIN-154), read from `get_company_ledger` rows.
 *
 * Two running figures, never mixed: `spent_to_date` (purchases and invoices billed to the
 * company, incl. GST) and `owed_balance` (between the two companies — positive means the
 * other company owes this one). A vehicle bought from the other company is owed, not spent.
 */

/** Address slug ↔ company value. `/company-ledger/nvs-travels`. */
const SLUGS = {
    nvs_travels: 'nvs-travels',
    nvs_travel_solutions: 'nvs-travel-solutions',
}

export const LEDGER_COMPANIES = STOCK_COMPANIES.map(c => ({ ...c, slug: SLUGS[c.value] }))

export const companyLedgerPath = company => `/company-ledger/${SLUGS[company] ?? SLUGS.nvs_travels}`

export const companyFromSlug = slug =>
    Object.entries(SLUGS).find(([, s]) => s === slug)?.[0] ?? null

export const otherCompany = company =>
    STOCK_COMPANIES.find(c => c.value !== company)?.value ?? null

export const ENTRY_TAGS = {
    purchase:       { label: 'Purchase',              className: 'bg-blue-100 text-blue-800' },
    refurbishment:  { label: 'Refurbishment',         className: 'bg-teal-100 text-teal-800' },
    job_card:       { label: 'Job card invoice',      className: 'bg-violet-100 text-violet-800' },
    multi_vehicle:  { label: 'Multi-vehicle invoice', className: 'bg-indigo-100 text-indigo-800' },
    vehicle_sold:   { label: 'Vehicle sold',          className: 'bg-emerald-100 text-emerald-800' },
    vehicle_bought: { label: 'Vehicle bought',        className: 'bg-amber-100 text-amber-800' },
    adjustment:          { label: 'Adjustment', className: 'bg-orange-100 text-orange-800' },
    reversed_adjustment: { label: 'Reversed',   className: 'bg-red-100 text-red-800' },
}

/**
 * The two figures a company ledger is reconciled on (MAIN-163), each on its own.
 * `column` is the get_company_ledger field the figure is a running total of.
 */
export const RECONCILE_FIGURES = {
    spent: { label: 'Spent to date',          column: 'spend' },
    owed:  { label: 'Owed between companies', column: 'owed' },
}

/** Whether the GST on an entry was claimed back — from finance's status. */
export const GST_STATUSES = {
    claimed:        { label: 'Claimed',            className: 'text-emerald-700' },
    no_gst:         { label: 'No GST',             className: 'text-gray-600' },
    not_reconciled: { label: 'Not yet reconciled', className: 'text-amber-700' },
    unknown:        { label: 'Unknown',            className: 'text-gray-500' },
    inter_company:  { label: 'Inter-company',      className: 'text-gray-600' },
}

export const isSpend = line => Number(line.spend) !== 0

/** A reconciliation adjustment (MAIN-163), active or reversed. It carries no GST. */
export const isAdjustment = line => line.kind === 'adjustment' || line.kind === 'reversed_adjustment'
/** A reversed adjustment: shown struck through, adds nothing. */
export const isVoided = line => line.kind === 'reversed_adjustment'

/** The signed amount a line shows: an adjustment's own (+/−), else the spend or the owed amount. */
export function lineAmount(line) {
    if (isAdjustment(line)) return Number(line.detail?.amount ?? 0)
    return isSpend(line) ? Number(line.spend) : Math.abs(Number(line.owed))
}
export const entryDay = line => formatAs(line.entry_at, 'yyyy-MM-dd', '')

const IST_DAY = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' })
/** The IST day (`yyyy-MM-dd`) a line was entered — the clock reconcile_company_ledger cuts off on, whatever the browser's. */
export const entryIstDay = line => {
    const d = toDate(line.entry_at)
    return d ? IST_DAY.format(d) : ''
}

const fmtDay = d => formatAs(d, 'dd MMM yyyy', '')

/**
 * How a line reads: `title`, a grey `sub` line and `link` ({ to, label }) to its record.
 * `company` is the ledger's, used to word an Owed figure.
 */
export function describeEntry(line, company) {
    const d = line.detail ?? {}
    switch (line.kind) {
        case 'purchase':
        case 'refurbishment':
            return {
                title: [d.invoice_no, d.supplier].filter(Boolean).join(' · '),
                sub: [
                    line.doc_date && `Bill dated ${fmtDay(line.doc_date)}`,
                    !d.finance_status && 'Recorded before purchases went to finance',
                ].filter(Boolean).join(' · '),
                link: d.purchase_number != null
                    ? { to: purchaseInvoicePath(d.purchase_number), label: formatPurchaseNumber(d.purchase_number) }
                    : null,
            }
        case 'job_card':
            return {
                title: [d.invoice_no, d.supplier].filter(Boolean).join(' · '),
                sub: [d.vehicle, line.doc_date && `Work on ${fmtDay(line.doc_date)}`].filter(Boolean).join(' · '),
                link: d.job_card_number != null
                    ? { to: `/job-cards/${d.job_card_number}`, label: `Job card ${d.job_card_number}` }
                    : null,
            }
        case 'multi_vehicle':
            return {
                title: [d.invoice_no, d.supplier].filter(Boolean).join(' · '),
                sub: [
                    d.vehicle_count != null && `${d.vehicle_count} vehicle${Number(d.vehicle_count) === 1 ? '' : 's'}`,
                    line.doc_date && `Work on ${fmtDay(line.doc_date)}`,
                ].filter(Boolean).join(' · '),
                link: d.batch_number != null
                    ? { to: batchPath(d.batch_number), label: formatBatchNumber(d.batch_number) }
                    : null,
            }
        case 'vehicle_sold':
        case 'vehicle_bought': {
            const sold = line.kind === 'vehicle_sold'
            return {
                title: `${d.vehicle} ${sold ? 'sold to' : 'bought from'} ${companyLabel(d.other_company)}`,
                sub: [`GST ${Number(d.gst_percent)}% included`, d.performed_by && `Recorded by ${d.performed_by}`]
                    .filter(Boolean).join(' · '),
                link: null,
            }
        }
        case 'adjustment':
        case 'reversed_adjustment': {
            const figure = RECONCILE_FIGURES[d.balance]
            const show = v => d.balance === 'owed' ? figureInWords(v, company) : fmtRupees(v)
            const base = [
                `As of ${fmtDay(d.as_of)}`,
                `${d.confirmed_against ?? 'Tally'} ${show(d.confirmed_balance)}, app ${show(d.system_balance)}`,
                d.reason,
                d.created_by && `Recorded by ${d.created_by}`,
            ].filter(Boolean).join(' · ')
            return {
                title: `${figure?.label ?? d.balance} reconciled with ${d.confirmed_against ?? 'Tally'}`,
                sub: line.kind === 'reversed_adjustment'
                    ? `${base}. Reversed${d.reversed_by ? ` by ${d.reversed_by}` : ''}: ${d.reverse_reason ?? ''}`
                    : base,
                link: null,
            }
        }
        default:
            return { title: line.kind, sub: '', link: null }
    }
}

/**
 * The owed-between-companies figure in words, from `company`'s side:
 * "Pvt Ltd owes NVS Travels", "NVS Travels owes Pvt Ltd" or "Nothing owed".
 */
export function owedWording(balance, company) {
    const n = Math.round(Number(balance ?? 0) * 100)
    if (n === 0) return 'Nothing owed'
    const us = companyShortLabel(company)
    const them = companyShortLabel(otherCompany(company))
    return n > 0 ? `${them} owes ${us}` : `${us} owes ${them}`
}

const paise = v => Math.round(Number(v ?? 0) * 100)

const fmtRupees = v => `₹${(paise(v) / 100).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

/** An Owed figure with its direction: "₹500.00 (Pvt Ltd owes NVS Travels)". */
export function figureInWords(value, company) {
    const n = paise(value)
    if (n === 0 || !company) return n === 0 ? `${fmtRupees(0)} (nothing owed)` : fmtRupees(value)
    return `${fmtRupees(Math.abs(n) / 100)} (${owedWording(value, company)})`
}

/**
 * The app's figure (`spent` or `owed`, MAIN-163) at the end of an IST day, in paise — what
 * reconcile_company_ledger freezes (it recomputes it when posting). Reversed adjustments
 * already add nothing.
 */
export function figureAsOf(lines, balance, day) {
    const column = RECONCILE_FIGURES[balance]?.column
    if (!column) return 0
    return lines.reduce((sum, l) => (entryIstDay(l) <= day ? sum + paise(l[column]) : sum), 0)
}

/** The latest as-of date an active adjustment reconciled `balance` to, or null. */
export function lastReconciled(lines, balance) {
    return lines
        .filter(l => l.kind === 'adjustment' && l.detail?.balance === balance)
        .reduce((latest, l) => (!latest || l.detail.as_of > latest ? l.detail.as_of : latest), null)
}

/**
 * Totals over the given lines, added in paise so they are exact:
 * spent, the net owed between the companies over these lines, GST in all, on spending
 * alone, and per status
 * (lines whose GST is not recorded are counted, not added), and how many lines there are.
 */
export function ledgerTotals(lines) {
    const gstByStatus = Object.fromEntries(Object.keys(GST_STATUSES).map(k => [k, 0]))
    let spent = 0, owed = 0, gst = 0, gstNotRecorded = 0, gstNotRecordedAmount = 0
    for (const l of lines) {
        spent += paise(l.spend)
        owed += paise(l.owed)
        // An adjustment moves a figure but has no GST, and is not an invoice missing one.
        if (isAdjustment(l)) continue
        if (l.gst == null) {
            gstNotRecorded += 1
            gstNotRecordedAmount += paise(l.spend)
        } else {
            gst += paise(l.gst)
            if (l.gst_status in gstByStatus) gstByStatus[l.gst_status] += paise(l.gst)
        }
    }
    return {
        spent: spent / 100,
        owed: owed / 100,
        gst: gst / 100,
        // GST on purchases and invoices only — the GST on a vehicle sale is not spending.
        spendGst: (gst - gstByStatus.inter_company) / 100,
        gstByStatus: Object.fromEntries(Object.entries(gstByStatus).map(([k, v]) => [k, v / 100])),
        gstNotRecorded,
        gstNotRecordedAmount: gstNotRecordedAmount / 100,
        count: lines.length,
    }
}

/** Lines entered between two IST days (`yyyy-MM-dd`, either may be blank). */
export const linesInRange = (lines, from, to) =>
    lines.filter(l => {
        const day = entryDay(l)
        return (!from || day >= from) && (!to || day <= to)
    })
