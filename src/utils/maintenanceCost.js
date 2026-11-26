/**
 * Maintenance cost (MAIN-164) — the arithmetic behind the vehicle page and
 * Analytics › Maintenance cost. Both pages use only this file, so their figures agree.
 *
 * The database supplies the lines (get_maintenance_cost → maintenance_cost_lines):
 *   spare       an in-house spare at first-in-first-out cost incl. GST
 *   outsourced  an outsourced job card's Approved Amount, one line per issue (split equally)
 *   mvi         a multi-vehicle invoice line
 *   labour      an issue's labour hours (no rupees)
 *   job_card    one line per job card, amount 0, so cards with no cost still count
 *
 * Money is added up in paise (whole numbers) and turned back into rupees at the end.
 */
import { format, parseISO, addMonths, startOfMonth } from 'date-fns'
import { companyLabel, companyShortLabel } from '../constants/vehicleCompanies'
import { workTypeLabel } from '../constants/batchWorkTypes'

/** Nothing before this exists in the app: "All time" starts here. */
export const ALL_TIME_START = '2026-05-08'

export const COST_KINDS = ['spare', 'outsourced', 'mvi']

export const NO_HUB = 'No hub (multi-vehicle invoices)'

/** Odometer bands are this wide; the report draws them up to REPORT_ODOMETER_CAP. */
export const ODOMETER_STEP = 10000
export const REPORT_ODOMETER_CAP = 150000
/** A report band with fewer vehicles than this is drawn lighter. */
export const THIN_BAND_VEHICLES = 5

const toPaise = v => Math.round(Number(v || 0) * 100)
const fromPaise = p => p / 100

// ---------------------------------------------------------------------------
// Reading the response
// ---------------------------------------------------------------------------

/** { columns, rows: [[...]] } → one object per line, numbers as numbers. */
export function linesFromResponse(response) {
    const columns = response?.columns ?? []
    return (response?.rows ?? []).map(row => {
        const line = {}
        columns.forEach((c, i) => { line[c] = row[i] })
        line.amount = Number(line.amount ?? 0)
        line.hours = line.hours == null ? null : Number(line.hours)
        line.quantity = line.quantity == null ? null : Number(line.quantity)
        return line
    })
}

export const isCostLine = line => COST_KINDS.includes(line.kind)

/** What a line counts under in "by category": its issue category, or the MVI's work. */
export function categoryOf(line) {
    if (line.kind === 'mvi') return `Multi-vehicle: ${workTypeLabel(line)}`
    return line.category || 'Uncategorised'
}

export const hubOf = line => line.hub || NO_HUB

// ---------------------------------------------------------------------------
// Periods (dates are Indian dates, 'YYYY-MM-DD')
// ---------------------------------------------------------------------------

const IST_DAY = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' })

/** The Indian date of an instant, 'YYYY-MM-DD' — whatever the browser's own time zone. */
export const istDay = date => IST_DAY.format(date)

/** Today in India — the database dates every cost line in Indian time. */
export const istToday = () => istDay(new Date())

/**
 * The Indian date of a database timestamp. Columns like job_cards.created_at are stored
 * without a zone and hold UTC, so a bare value is read as UTC.
 */
export function istDayOf(value) {
    if (!value) return null
    const s = String(value).replace(' ', 'T')
    const zoned = /Z$|[+-]\d\d:?\d\d$/.test(s) ? s : `${s}Z`
    return istDay(new Date(zoned))
}

export const PERIOD_PRESETS = [
    { value: 'all', label: 'All time (since 8 May 2026)' },
    { value: '90d', label: 'Last 90 days' },
    { value: 'fy', label: 'This financial year' },
    { value: 'custom', label: 'Custom…' },
]

/** The financial year (April–March) a date falls in, as { start, end }. */
export function financialYear(today) {
    const d = parseISO(today)
    const startYear = d.getMonth() >= 3 ? d.getFullYear() : d.getFullYear() - 1
    return { start: `${startYear}-04-01`, end: `${startYear + 1}-03-31` }
}

/** A preset's { start, end } on `today` ('YYYY-MM-DD', Indian date). */
export function periodRange(preset, today) {
    if (preset === '90d') {
        const d = parseISO(today)
        d.setDate(d.getDate() - 89)
        return { start: format(d, 'yyyy-MM-dd'), end: today }
    }
    if (preset === 'fy') return financialYear(today)
    return { start: ALL_TIME_START, end: today }
}

// ---------------------------------------------------------------------------
// Filtering
// ---------------------------------------------------------------------------

/**
 * Lines matching the report's filters. Each filter is an array of allowed values; empty
 * means all. `categories` filters cost lines only — job card and labour lines follow the
 * category of their issue where they have one.
 */
export function filterLines(lines, { companies = [], hubs = [], sites = [], categories = [], vehicle = null } = {}) {
    return lines.filter(l =>
        (!vehicle || l.vehicle_number === vehicle) &&
        (!companies.length || companies.includes(l.company)) &&
        (!hubs.length || hubs.includes(hubOf(l))) &&
        (!sites.length || sites.includes(l.site)) &&
        (!categories.length || l.kind === 'job_card' || categories.includes(categoryOf(l)))
    )
}

// ---------------------------------------------------------------------------
// Totals
// ---------------------------------------------------------------------------

/** Headline figures for a set of lines. */
export function summarise(lines) {
    let spares = 0, outsourced = 0, mvi = 0, awaiting = 0, hours = 0
    let spareLines = 0, missingPrices = 0
    const jobCards = new Set()
    const costedCards = new Set()
    const spareCards = new Set()
    const vehicles = new Set()
    let openCards = 0
    for (const l of lines) {
        if (l.kind === 'job_card') {
            jobCards.add(l.job_card_id)
            if (l.job_card_status === 'Open') openCards++
            continue
        }
        if (l.kind === 'labour') { hours += Number(l.hours || 0); continue }
        const p = toPaise(l.amount)
        if (l.kind === 'spare') {
            if (l.price_missing) { missingPrices++; continue }
            spares += p; spareLines++; spareCards.add(l.job_card_id)
        } else if (l.kind === 'outsourced') outsourced += p
        else if (l.kind === 'mvi') mvi += p
        if (l.awaiting_finance) awaiting += p
        if (p > 0) {
            vehicles.add(l.vehicle_number)
            if (l.job_card_id) costedCards.add(l.job_card_id)
        }
    }
    return {
        total: fromPaise(spares + outsourced + mvi),
        spares: fromPaise(spares),
        outsourced: fromPaise(outsourced + mvi),
        outsourcedCards: fromPaise(outsourced),
        mvi: fromPaise(mvi),
        awaitingFinance: fromPaise(awaiting),
        labourHours: Math.round(hours * 100) / 100,
        jobCards: jobCards.size,
        openJobCards: openCards,
        jobCardsWithCost: costedCards.size,
        spareLines,
        spareJobCards: spareCards.size,
        missingPrices,
        vehiclesWithCost: vehicles.size,
    }
}

/**
 * Cost lines grouped by `keyOf`, largest first:
 * [{ key, amount, vehicles, jobCards, split }] — `split` is true when a group holds an
 * outsourced amount that was shared across categories.
 */
export function groupCost(lines, keyOf) {
    const groups = new Map()
    for (const l of lines) {
        if (!isCostLine(l) || l.price_missing) continue
        const key = keyOf(l)
        let g = groups.get(key)
        if (!g) { g = { key, paise: 0, vehicles: new Set(), jobCards: new Set(), split: false }; groups.set(key, g) }
        g.paise += toPaise(l.amount)
        g.vehicles.add(l.vehicle_number)
        if (l.job_card_id) g.jobCards.add(l.job_card_id)
        if (l.kind === 'outsourced' && l.split_count > 1) g.split = true
    }
    return [...groups.values()]
        .map(g => ({ key: g.key, amount: fromPaise(g.paise), vehicles: g.vehicles.size, jobCards: g.jobCards.size, split: g.split }))
        .sort((a, b) => b.amount - a.amount || String(a.key).localeCompare(String(b.key)))
}

export const byCompany = lines => groupCost(lines, l => l.company)
export const byHub = lines => groupCost(lines, hubOf)
export const bySite = lines => groupCost(lines, l => l.site || '—')
export const byCategory = lines => groupCost(lines, categoryOf)
export const byVehicle = lines => groupCost(lines, l => l.vehicle_number)

/** The outsourced splits behind a category: [{ jobCardNumber, approved, count, share }]. */
export function splitsIn(lines, category) {
    const cards = new Map()
    for (const l of lines) {
        if (l.kind !== 'outsourced' || !(l.split_count > 1) || categoryOf(l) !== category) continue
        if (!cards.has(l.job_card_id)) {
            cards.set(l.job_card_id, {
                jobCardNumber: l.job_card_number,
                count: l.split_count,
                share: l.amount,
                approved: fromPaise(toPaise(l.amount) * l.split_count),
            })
        }
    }
    return [...cards.values()]
}

/** Cost per month from the period's first month to its last, empty months as 0. */
export function byMonth(lines, { start, end }) {
    const months = []
    for (let m = startOfMonth(parseISO(start)); m <= parseISO(end); m = addMonths(m, 1)) {
        months.push(format(m, 'yyyy-MM'))
    }
    const totals = new Map(months.map(m => [m, 0]))
    const perCompany = new Map(months.map(m => [m, new Map()]))
    for (const l of lines) {
        if (!isCostLine(l) || l.price_missing || !l.cost_date) continue
        const m = l.cost_date.slice(0, 7)
        if (!totals.has(m)) continue
        const p = toPaise(l.amount)
        totals.set(m, totals.get(m) + p)
        const pc = perCompany.get(m)
        pc.set(l.company, (pc.get(l.company) ?? 0) + p)
    }
    return months.map(m => ({
        key: m,
        label: format(parseISO(`${m}-01`), 'MMM yy'),
        amount: fromPaise(totals.get(m)),
        byCompany: Object.fromEntries([...perCompany.get(m)].map(([c, p]) => [c, fromPaise(p)])),
    }))
}

export function median(values) {
    if (!values.length) return 0
    const s = [...values].sort((a, b) => a - b)
    const mid = Math.floor(s.length / 2)
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2
}

/** Average and median cost per vehicle that had a cost. */
export function perVehicle(lines) {
    const vehicles = byVehicle(lines)
    const total = vehicles.reduce((s, v) => s + toPaise(v.amount), 0)
    return {
        vehicles: vehicles.length,
        average: vehicles.length ? fromPaise(Math.round(total / vehicles.length)) : 0,
        median: median(vehicles.map(v => v.amount)),
    }
}

/** Share of all cost carried by the costliest `fraction` of vehicles (0.1 = top 10%). */
export function topShare(lines, fraction = 0.1) {
    const vehicles = byVehicle(lines)
    if (!vehicles.length) return { count: 0, share: 0, amount: 0 }
    const count = Math.max(1, Math.round(vehicles.length * fraction))
    const total = vehicles.reduce((s, v) => s + toPaise(v.amount), 0)
    const top = vehicles.slice(0, count).reduce((s, v) => s + toPaise(v.amount), 0)
    return { count, amount: fromPaise(top), share: total ? top / total : 0 }
}

/**
 * How one vehicle compares with the fleet, over the same period's fleet lines:
 * its cost, the average of vehicles of its company that had a cost, the ratio and its rank
 * among all vehicles with a cost.
 */
export function compareWithFleet(fleetLines, vehicleNumber, company) {
    const vehicles = byVehicle(fleetLines)
    const mine = vehicles.find(v => v.key === vehicleNumber)
    const own = mine?.amount ?? 0
    const companyVehicles = byVehicle(fleetLines.filter(l => l.company === company))
    const companyTotal = companyVehicles.reduce((s, v) => s + toPaise(v.amount), 0)
    const average = companyVehicles.length ? fromPaise(Math.round(companyTotal / companyVehicles.length)) : 0
    return {
        own,
        company,
        companyTotal: fromPaise(companyTotal),
        companyVehicles: companyVehicles.length,
        average,
        ratio: average ? own / average : null,
        rank: mine ? vehicles.indexOf(mine) + 1 : null,
        ranked: vehicles.length,
    }
}

// ---------------------------------------------------------------------------
// Odometer bands
// ---------------------------------------------------------------------------

/** 42,442 → 40000 (the start of its 10,000 km band). */
export const bandOf = (km, step = ODOMETER_STEP) => Math.floor(km / step) * step

/**
 * Cost by odometer band, using the reading on each line's job card.
 * mode 'total': each band's cost (vehicle page), bands from the lowest to the highest
 * reading, empty bands as 0. mode 'perVehicle': band cost ÷ vehicles with a reading in the
 * band (the report), bands from 0 to `cap`; bands above it are summed into `beyond`.
 * Returns { bands: [{ start, amount, total, vehicles, jobCards, thin }], noReading, beyond }.
 */
export function byOdometer(lines, { mode = 'total', step = ODOMETER_STEP, cap = null } = {}) {
    const bands = new Map()
    const noReading = { amount: 0, jobCards: new Set() }
    const beyond = { amount: 0, jobCards: new Set() }
    for (const l of lines) {
        if (!isCostLine(l) || l.price_missing) continue
        const km = l.job_card_odometer
        const p = toPaise(l.amount)
        if (km == null) {
            noReading.amount += p
            noReading.jobCards.add(l.job_card_number ?? `MVI-${l.batch_number}`)
            continue
        }
        const start = bandOf(km, step)
        if (cap != null && start >= cap) {
            beyond.amount += p
            beyond.jobCards.add(l.job_card_number)
            continue
        }
        let b = bands.get(start)
        if (!b) { b = { start, paise: 0, vehicles: new Set(), jobCards: new Set() }; bands.set(start, b) }
        b.paise += p
        b.vehicles.add(l.vehicle_number)
        b.jobCards.add(l.job_card_number)
    }
    const starts = [...bands.keys()]
    const out = []
    if (starts.length) {
        const first = mode === 'perVehicle' ? 0 : Math.min(...starts)
        const last = mode === 'perVehicle' && cap != null ? cap - step : Math.max(...starts)
        for (let s = first; s <= last; s += step) {
            const b = bands.get(s)
            const total = b ? b.paise : 0
            const vehicles = b ? b.vehicles.size : 0
            out.push({
                start: s,
                total: fromPaise(total),
                vehicles,
                jobCards: b ? [...b.jobCards].sort((x, y) => x - y) : [],
                amount: mode === 'perVehicle' ? (vehicles ? fromPaise(Math.round(total / vehicles)) : 0) : fromPaise(total),
                thin: mode === 'perVehicle' && vehicles > 0 && vehicles < THIN_BAND_VEHICLES,
            })
        }
    }
    return {
        bands: out,
        noReading: { amount: fromPaise(noReading.amount), jobCards: [...noReading.jobCards] },
        beyond: { amount: fromPaise(beyond.amount), jobCards: [...beyond.jobCards] },
    }
}

/** 40000 → "40k–50k km" */
export const bandLabel = (start, step = ODOMETER_STEP) =>
    `${start / 1000}k–${(start + step) / 1000}k km`

// ---------------------------------------------------------------------------
// Words
// ---------------------------------------------------------------------------

/** ₹97,764 — whole rupees for tiles and charts. */
export const inr = v => `₹${Math.round(Number(v || 0)).toLocaleString('en-IN')}`

/** ₹30,927.80 — paise kept, for spare lines. */
export const inrExact = v =>
    `₹${Number(v || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

/** Short form for chart labels: 4,104,690 → "41.05L", 53,158 → "53.2k", 900 → "900". */
export function inrShort(v) {
    const n = Number(v || 0)
    if (n >= 100000) return `${(n / 100000).toFixed(2)}L`
    if (n >= 1000) return `${(n / 1000).toFixed(1)}k`
    return String(Math.round(n))
}

export const plural = (n, one, many = `${one}s`) => `${n.toLocaleString('en-IN')} ${n === 1 ? one : many}`

export function explainTotal(s) {
    const parts = [`Spares ${inr(s.spares)} (${plural(s.spareLines, 'line')} on ${plural(s.spareJobCards, 'job card')})`]
    parts.push(`outsourced ${inr(s.outsourcedCards)}`)
    if (s.mvi) parts.push(`multi-vehicle invoices ${inr(s.mvi)}`)
    let text = `${parts.join(' + ')} = ${inr(s.total)}`
    if (s.awaitingFinance) text += `. ${inr(s.awaitingFinance)} of it is awaiting finance's acceptance.`
    if (s.missingPrices) text += ` ${plural(s.missingPrices, 'spare')} with no price ${s.missingPrices === 1 ? 'is' : 'are'} left out.`
    return text
}

export function explainCompare(c) {
    if (!c.ratio) return `No ${companyLabel(c.company)} vehicle had a cost in this period.`
    return [
        `This vehicle ${inr(c.own)} ÷ ${companyShortLabel(c.company)} average ${inr(c.average)} = ${c.ratio.toFixed(1)}×.`,
        `Average = ${companyLabel(c.company)} cost ${inr(c.companyTotal)} ÷ ${plural(c.companyVehicles, 'vehicle')} that had a cost in the period.`,
        c.rank ? `Rank: ${c.rank} of ${c.ranked.toLocaleString('en-IN')} vehicles with a cost, all companies.` : '',
    ].filter(Boolean).join(' ')
}

export const explainPerVehicleGroup = g =>
    `${inr(g.amount)} ÷ ${plural(g.vehicles, 'vehicle')} = ${inr(g.vehicles ? g.amount / g.vehicles : 0)}`

export function explainSplit(split) {
    return `Approved ${inrExact(split.approved)} ÷ ${split.count} issues = ${inrExact(split.share)} each (job card ${split.jobCardNumber}). The invoice has one amount, so it is shared equally among the card's issues for the category totals.`
}

export function explainBand(band, mode) {
    const cards = band.jobCards.length
    if (mode === 'perVehicle') {
        return `${bandLabel(band.start)}: ${inr(band.total)} ÷ ${plural(band.vehicles, 'vehicle')} with a job card in this band = ${inr(band.amount)} per vehicle (${plural(cards, 'job card')}).${band.thin ? ` Fewer than ${THIN_BAND_VEHICLES} vehicles — read with care.` : ''}`
    }
    return `${bandLabel(band.start)}: ${inr(band.total)} on ${plural(cards, 'job card')}${cards ? ` (JC ${band.jobCards.join(', ')})` : ''}.`
}

export const explainLabour = hours =>
    `${hours} hours: technicians' hours where recorded, otherwise the hours logged on the item before per-person tracking (MAIN-116). Placed by each item's activity complete date. Hours only — there is no rupee rate.`
