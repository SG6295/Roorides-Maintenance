import { useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import { format, parseISO } from 'date-fns'
import { ArrowDownTrayIcon } from '@heroicons/react/24/outline'
import Navigation from '../components/shared/Navigation'
import FormulaTip from '../components/shared/FormulaTip'
import { TicketListSkeleton } from '../components/shared/LoadingSkeleton'
import { PeriodPicker, StatTile, CostChart, CategoryBars } from '../components/cost/CostWidgets'
import WorkHistoryTable from '../components/vehicles/WorkHistoryTable'
import {
    useMaintenanceCost, useVehicleByRegistration, useVehicleWorkHistory, useVehicleTickets,
} from '../hooks/useMaintenanceCost'
import { useVehicleBatchServices } from '../hooks/useBatchServices'
import { useVehicleCompanyChanges } from '../hooks/useVehicleCompany'
import { useAllSites } from '../hooks/useSites'
import { useSiteWorkshops } from '../hooks/useSiteWorkshops'
import { useWorkshopLocations } from '../hooks/useWorkshopLocations'
import { companyLabel, companyColor, companyShortLabel } from '../constants/vehicleCompanies'
import {
    periodRange, istToday, istDayOf, filterLines, summarise, compareWithFleet, byCategory,
    inr, inrExact, plural, explainTotal, explainCompare, explainLabour,
} from '../utils/maintenanceCost'
import { exportMaintenanceCost } from '../utils/maintenanceCostExport'

/** 1 → "highest", 2 → "2nd highest", 13 → "13th highest". */
const rankText = n => {
    if (n === 1) return 'highest'
    const tens = n % 100
    const suffix = tens >= 11 && tens <= 13 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' }[n % 10] ?? 'th')
    return `${n}${suffix} highest`
}

const shortDate = d => (d ? format(parseISO(d), 'd MMM yyyy') : '—')

/** The vehicle's company history as one line, oldest first. */
function companyHistoryText(entries) {
    if (!entries.length) return 'No company recorded yet'
    return [...entries].reverse().map(e => {
        const when = shortDate(istDayOf(e.created_at))
        if (e.kind === 'initial_load') return `${companyLabel(e.new_company)} since first load (${when})`
        if (e.kind === 'assignment') return `assigned to ${companyLabel(e.new_company)} on ${when}`
        return `sold from ${companyShortLabel(e.old_company)} to ${companyShortLabel(e.new_company)} on ${when} for ${inrExact(e.sale_value)}`
    }).join(' · ')
}

/** The costliest spares in the period, by part: [{ name, amount, quantity, unit, jobCards }]. */
function biggestSpares(lines, count = 3) {
    const parts = new Map()
    for (const l of lines) {
        if (l.kind !== 'spare' || l.price_missing) continue
        const p = parts.get(l.part_name) ?? { name: l.part_name, paise: 0, quantity: 0, unit: l.unit, jobCards: new Set() }
        p.paise += Math.round(l.amount * 100)
        p.quantity += Number(l.quantity || 0)
        p.jobCards.add(l.job_card_number)
        parts.set(l.part_name, p)
    }
    return [...parts.values()]
        .map(p => ({ ...p, amount: p.paise / 100, jobCards: [...p.jobCards] }))
        .sort((a, b) => b.amount - a.amount)
        .slice(0, count)
}

/**
 * A vehicle's page (MAIN-164): what it costs to maintain and every piece of work done on
 * it. Exec, super_admin and finance. Every figure comes from src/utils/maintenanceCost.js
 * and explains itself on its ⓘ.
 */
export default function VehicleHistory() {
    const { vehicleNumber } = useParams()
    const registration = decodeURIComponent(vehicleNumber)
    const [period, setPeriod] = useState(() => ({ preset: 'all', ...periodRange('all', istToday()) }))
    const [category, setCategory] = useState(null)

    const { data: vehicle, isLoading: vehicleLoading } = useVehicleByRegistration(registration)
    const { data: fleetLines = [], isLoading: costLoading, error: costError } = useMaintenanceCost(period)
    const { data: jobCards = [], isLoading: historyLoading } = useVehicleWorkHistory(registration)
    const { data: batchLines = [] } = useVehicleBatchServices(registration)
    const { data: tickets = [] } = useVehicleTickets(registration)
    const { data: companyChanges } = useVehicleCompanyChanges({ vehicleId: vehicle?.id ?? null, pageSize: 50 })
    const { data: sites = [] } = useAllSites()
    const { data: siteWorkshops = [] } = useSiteWorkshops()
    const { data: locations = [] } = useWorkshopLocations({ includeInactive: true })

    const lines = useMemo(() => filterLines(fleetLines, { vehicle: registration }), [fleetLines, registration])
    const summary = useMemo(() => summarise(lines), [lines])
    const comparison = useMemo(
        () => (vehicle ? compareWithFleet(fleetLines, registration, vehicle.company) : null),
        [fleetLines, registration, vehicle]
    )
    const categories = useMemo(() => byCategory(lines), [lines])
    const topSpares = useMemo(() => biggestSpares(lines), [lines])
    const awaitingMvi = useMemo(
        () => new Set(lines.filter(l => l.kind === 'mvi' && l.awaiting_finance).map(l => l.line_id.slice(4))),
        [lines]
    )

    const siteNames = useMemo(() => (vehicle?.vehicle_sites ?? []).map(s => s.site_name), [vehicle])
    // The hub(s) mapped to the vehicle's sites in Workshop Hub Mapping (MAIN-131).
    const hubs = useMemo(() => {
        const siteIds = new Set(sites.filter(s => siteNames.includes(s.name)).map(s => s.id))
        const locIds = new Set(siteWorkshops.filter(m => siteIds.has(m.site_id)).map(m => m.location_id))
        return locations.filter(l => locIds.has(l.id)).map(l => l.name)
    }, [sites, siteWorkshops, locations, siteNames])

    const lastReading = useMemo(
        () => jobCards.filter(jc => jc.odometer != null).sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0] ?? null,
        [jobCards]
    )

    const periodTickets = useMemo(
        () => tickets.filter(t => { const d = istDayOf(t.created_at); return d >= period.start && d <= period.end }),
        [tickets, period]
    )
    const ticketsWithoutCard = periodTickets.filter(t => !(t.issues || []).some(i => i.job_card_id))

    const categoryOptions = useMemo(() => {
        const set = new Set(categories.map(c => c.key))
        for (const jc of jobCards) for (const i of jc.issues || []) if (i.category) set.add(i.category)
        return [...set].sort()
    }, [categories, jobCards])

    const loading = vehicleLoading || historyLoading
    const entries = companyChanges?.entries ?? []

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Vehicles', href: '/vehicles' }, { label: registration }]} />

            <main className="max-w-7xl mx-auto px-4 sm:px-6 py-7 space-y-5">
                {/* Header */}
                <section className="bg-white rounded-xl border border-gray-200 p-6 flex flex-wrap gap-6 justify-between items-start">
                    <div className="space-y-2.5">
                        <div className="flex flex-wrap items-center gap-3">
                            <h1 className="text-3xl font-bold font-mono tracking-wide text-gray-900">{registration}</h1>
                            {vehicle && <span className={`px-2.5 py-1 rounded-full text-xs font-semibold ${companyColor(vehicle.company)}`}>{companyLabel(vehicle.company)}</span>}
                            {vehicle && (
                                <span className={`px-2.5 py-1 rounded-full text-xs font-semibold ${vehicle.is_active ? 'bg-green-100 text-green-800' : 'bg-gray-200 text-gray-700'}`}>
                                    {vehicle.is_active ? 'Active' : 'Inactive — left the Roorides feed'}
                                </span>
                            )}
                        </div>
                        {vehicle ? (
                            <>
                                <p className="text-sm text-gray-700">
                                    {[vehicle.make && vehicle.make !== '0' ? vehicle.make : null, vehicle.model].filter(Boolean).join(' · ') || 'Make and model not in the Roorides feed'} · Year {vehicle.year || '—'}
                                </p>
                                <div className="flex flex-wrap gap-x-5 gap-y-1 text-sm text-gray-600">
                                    <span>Site <strong className="text-gray-900">{siteNames.join(', ') || '—'}</strong></span>
                                    <span>Hub <strong className="text-gray-900">{hubs.join(', ') || 'Not mapped'}</strong></span>
                                    <span>
                                        Last odometer{' '}
                                        {lastReading
                                            ? <><strong className="text-gray-900">{Number(lastReading.odometer).toLocaleString('en-IN')} km</strong> (job card JC-{lastReading.job_card_number}, {shortDate(istDayOf(lastReading.created_at))})</>
                                            : <strong className="text-gray-900">not recorded</strong>}
                                        {' · '}<strong className="text-gray-900">—</strong> (Roorides)
                                    </span>
                                    <span>Company history: {companyHistoryText(entries)}</span>
                                </div>
                            </>
                        ) : !vehicleLoading && (
                            <p className="text-sm text-gray-600">This registration is not in the vehicle list; its past work is shown below.</p>
                        )}
                    </div>
                    <button
                        type="button"
                        onClick={() => exportMaintenanceCost(lines, `maintenance_cost_${registration}_${period.start}_to_${period.end}.xlsx`)}
                        disabled={!lines.length}
                        className="inline-flex items-center px-3.5 py-2 border border-gray-300 rounded-lg text-sm text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50"
                    >
                        <ArrowDownTrayIcon className="h-4 w-4 mr-1.5" aria-hidden="true" />
                        Export
                    </button>
                </section>

                <PeriodPicker value={period} onChange={setPeriod} />

                {costError && (
                    <div className="bg-white rounded-xl border border-red-200 p-4 text-sm text-red-700">Could not load costs: {costError.message}</div>
                )}

                {loading || costLoading ? <TicketListSkeleton /> : (
                    <>
                        {/* Tiles */}
                        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                            <StatTile
                                label="Maintenance cost"
                                value={inr(summary.total)}
                                note={`Spares ${inr(summary.spares)} · Outsourced ${inr(summary.outsourced)}`}
                                tip={explainTotal(summary)}
                            />
                            <StatTile
                                label="Compared with fleet"
                                value={comparison?.ratio ? `${comparison.ratio.toFixed(1)}×` : '—'}
                                tone={comparison?.ratio > 1.5 ? 'warn' : undefined}
                                note={comparison?.ratio
                                    ? `${companyShortLabel(comparison.company)} average ${inr(comparison.average)}${comparison.rank ? ` · ${rankText(comparison.rank)} of ${comparison.ranked}` : ''}`
                                    : 'No cost to compare in this period'}
                                tip={comparison ? explainCompare(comparison) : null}
                            />
                            <StatTile
                                label="Job cards"
                                value={summary.jobCards}
                                note={`${summary.openJobCards} open · ${plural(periodTickets.length, 'ticket')} (${ticketsWithoutCard.length} without a job card)`}
                                tip={`${plural(summary.jobCards, 'job card')} opened in the period, ${summary.jobCardsWithCost} with a cost. ${plural(periodTickets.length, 'ticket')} raised in the period${ticketsWithoutCard.length ? `; without a job card: ${ticketsWithoutCard.map(t => `${t.ticket_number} (${t.status})`).join(', ')}` : ''}.`}
                            />
                            <StatTile
                                label="Labour"
                                value={`${summary.labourHours} hrs`}
                                note="Hours only — no rupee rate"
                                tip={explainLabour(summary.labourHours)}
                            />
                            <StatTile
                                placeholder
                                label="Km driven"
                                value="—"
                                note="Waiting for Roorides distance"
                                tip="Km driven will come from Roorides' distance for the period (MAIN-169 — Distance and odometer from Roorides for cost per km). The odometer typed on job cards is not used for this."
                            />
                            <StatTile
                                placeholder
                                label="Cost per km"
                                value="—"
                                note="Maintenance cost ÷ km, once Roorides sends km"
                                tip="Cost per km = the vehicle's maintenance cost in the period ÷ the km Roorides says it drove in the period. Waiting for MAIN-169."
                            />
                        </div>

                        {/* Charts */}
                        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 items-start">
                            <CostChart lines={lines} period={period} scope="vehicle" />
                            <section className="bg-white rounded-xl border border-gray-200 p-5 space-y-4" aria-label="Where the money went">
                                <div>
                                    <h2 className="text-base font-semibold text-gray-900">Where the money went</h2>
                                    <p className="text-xs text-gray-600 mt-0.5">By issue category · click one to filter the work history below</p>
                                </div>
                                <CategoryBars groups={categories} lines={lines} selected={category} onSelect={setCategory} />
                                {categories.some(c => c.split) && (
                                    <p className="text-xs text-gray-600 bg-gray-50 rounded-lg px-3 py-2">
                                        An outsourced job card's amount is split equally across its issues' categories; the ⓘ beside a category shows the split.
                                    </p>
                                )}
                                {topSpares.length > 0 && (
                                    <div className="border-t border-gray-100 pt-3">
                                        <h3 className="text-sm font-semibold mb-1.5">Biggest spares</h3>
                                        <ul className="text-sm space-y-1">
                                            {topSpares.map(p => (
                                                <li key={p.name} className="flex justify-between gap-3">
                                                    <span>
                                                        {p.name} · {p.quantity.toLocaleString('en-IN')} {p.unit}{' '}
                                                        <span className="text-gray-600">{p.jobCards.length === 1 ? `· JC-${p.jobCards[0]}` : `on ${p.jobCards.length} job cards`}</span>
                                                    </span>
                                                    <FormulaTip text={`${p.name}: ${p.quantity.toLocaleString('en-IN')} ${p.unit || ''} on ${p.jobCards.map(n => `JC ${n}`).join(', ')}, at first-in-first-out cost incl. GST = ${inrExact(p.amount)}.`} title="This spare">
                                                        <span className="font-semibold">{inr(p.amount)}</span>
                                                    </FormulaTip>
                                                </li>
                                            ))}
                                        </ul>
                                    </div>
                                )}
                            </section>
                        </div>

                        <WorkHistoryTable
                            jobCards={jobCards}
                            batchLines={batchLines}
                            period={period}
                            awaitingMvi={awaitingMvi}
                            category={category}
                            onCategoryChange={setCategory}
                            categoryOptions={categoryOptions}
                        />
                    </>
                )}
            </main>
        </div>
    )
}
