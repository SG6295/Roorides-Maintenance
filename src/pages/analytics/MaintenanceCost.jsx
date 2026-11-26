import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { ArrowDownTrayIcon, ChevronUpDownIcon } from '@heroicons/react/24/outline'
import MultiFilterSelect from '../../components/shared/MultiFilterSelect'
import FormulaTip from '../../components/shared/FormulaTip'
import { PeriodPicker, StatTile, CostChart, CategoryBars } from '../../components/cost/CostWidgets'
import { useMaintenanceCost } from '../../hooks/useMaintenanceCost'
import { useAllSites } from '../../hooks/useSites'
import { useWorkshopSiteGroups } from '../../hooks/useSiteWorkshops'
import { useWorkshopLocations } from '../../hooks/useWorkshopLocations'
import { formatSiteLabel } from '../../utils/siteLabel'
import { VEHICLE_COMPANIES, companyLabel, UNKNOWN_COMPANY } from '../../constants/vehicleCompanies'
import {
    periodRange, istToday, filterLines, summarise, perVehicle, byCompany, byHub, bySite,
    byCategory, byVehicle, topShare, NO_HUB, inr, plural, explainTotal, explainPerVehicleGroup,
    explainLabour,
} from '../../utils/maintenanceCost'
import { exportMaintenanceCost } from '../../utils/maintenanceCostExport'

const TOP_ROWS = 10
const list = v => (v ? v.split(',').filter(Boolean) : [])

/** A table sortable on every column; shows TOP_ROWS first, then Show all. */
function SortableTable({ caption, columns, rows, defaultSort, footer }) {
    const [sort, setSort] = useState(defaultSort)
    const [showAll, setShowAll] = useState(false)
    const sorted = useMemo(() => {
        const col = columns.find(c => c.key === sort.key)
        return [...rows].sort((a, b) => {
            const x = col.value(a), y = col.value(b)
            const cmp = typeof x === 'number' ? x - y : String(x).localeCompare(String(y))
            return sort.dir === 'asc' ? cmp : -cmp
        })
    }, [rows, sort, columns])
    const shown = showAll ? sorted : sorted.slice(0, TOP_ROWS)

    return (
        <section className="bg-white rounded-xl border border-gray-200 overflow-hidden" aria-label={caption}>
            <h2 className="px-5 py-3.5 text-base font-semibold border-b border-gray-200">{caption}</h2>
            <div className="overflow-x-auto">
                <table className="w-full text-sm">
                    <thead>
                        <tr className="bg-gray-50 text-[11px] text-gray-600 uppercase tracking-wide">
                            {columns.map(c => (
                                <th key={c.key} scope="col" aria-sort={sort.key === c.key ? (sort.dir === 'asc' ? 'ascending' : 'descending') : 'none'}
                                    className={`px-4 py-2 font-semibold ${c.align === 'right' ? 'text-right' : 'text-left'}`}>
                                    <button
                                        type="button"
                                        onClick={() => setSort(s => ({ key: c.key, dir: s.key === c.key && s.dir === 'desc' ? 'asc' : 'desc' }))}
                                        className="inline-flex items-center gap-1 uppercase hover:text-gray-900"
                                    >
                                        {c.label}<ChevronUpDownIcon className="h-3.5 w-3.5" aria-hidden="true" />
                                    </button>
                                </th>
                            ))}
                        </tr>
                    </thead>
                    <tbody>
                        {shown.map(r => (
                            <tr key={r.key} className="border-t border-gray-100">
                                {columns.map(c => (
                                    <td key={c.key} className={`px-4 py-2.5 ${c.align === 'right' ? 'text-right' : ''} ${c.className ?? ''}`}>{c.render ? c.render(r) : c.value(r)}</td>
                                ))}
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
            <div className="px-5 py-2.5 border-t border-gray-200 text-xs text-gray-600 flex flex-wrap justify-between gap-2">
                <span>{footer}</span>
                {rows.length > TOP_ROWS && (
                    <button type="button" onClick={() => setShowAll(s => !s)} className="text-blue-700 hover:underline">
                        {showAll ? 'Show fewer' : `Show all ${rows.length}`}
                    </button>
                )}
            </div>
        </section>
    )
}

/**
 * Analytics › Maintenance cost (MAIN-164): what vehicles, sites, hubs and companies cost to
 * maintain. Exec, super_admin and finance. Filters live in the address so a view can be
 * shared; every figure comes from src/utils/maintenanceCost.js and explains itself.
 */
export default function MaintenanceCost() {
    const [params, setParams] = useSearchParams()
    const preset = params.get('period') || 'fy'
    const period = useMemo(() => (
        preset === 'custom' && params.get('from') && params.get('to')
            ? { preset, start: params.get('from'), end: params.get('to') }
            : { preset, ...periodRange(preset, istToday()) }
    ), [preset, params])
    const filters = useMemo(() => ({
        companies: list(params.get('co')),
        hubs: list(params.get('hub')),
        sites: list(params.get('site')),
        categories: list(params.get('cat')),
    }), [params])

    const update = changes => {
        const next = new URLSearchParams(params)
        for (const [k, v] of Object.entries(changes)) {
            const value = Array.isArray(v) ? v.join(',') : v
            if (value) next.set(k, value); else next.delete(k)
        }
        setParams(next, { replace: true })
    }
    const setPeriod = p => update({ period: p.preset, from: p.preset === 'custom' ? p.start : '', to: p.preset === 'custom' ? p.end : '' })

    const { data: allLines = [], isLoading, isFetching, error } = useMaintenanceCost(period)
    const { data: sites = [] } = useAllSites()
    const workshopGroups = useWorkshopSiteGroups(sites)
    const { data: locations = [] } = useWorkshopLocations({ includeInactive: true })

    const lines = useMemo(() => filterLines(allLines, filters), [allLines, filters])
    const summary = useMemo(() => summarise(lines), [lines])
    const per = useMemo(() => perVehicle(lines), [lines])
    const companies = useMemo(() => byCompany(lines), [lines])
    const hubs = useMemo(() => byHub(lines), [lines])
    const categories = useMemo(() => byCategory(lines), [lines])
    const siteRows = useMemo(() => bySite(lines), [lines])
    const vehicleRows = useMemo(() => {
        const companyOf = new Map(lines.map(l => [l.vehicle_number, l.company]))
        return byVehicle(lines).map(v => ({ ...v, company: companyOf.get(v.key) }))
    }, [lines])
    const top = useMemo(() => topShare(lines, 0.1), [lines])

    const siteLabel = useMemo(() => {
        const byName = new Map(sites.map(s => [s.name, formatSiteLabel(s)]))
        return name => byName.get(name) || name
    }, [sites])
    const categoryOptions = useMemo(() => byCategory(allLines).map(c => ({ value: c.key, label: c.key })), [allLines])

    return (
        <div className="space-y-5">
            {/* Header & filters */}
            <div className="bg-white rounded-xl border border-gray-200 px-4 py-4 space-y-3">
                <div className="flex flex-wrap items-center gap-3">
                    <h1 className="text-xl font-bold text-gray-900">Maintenance cost</h1>
                    {isFetching && !isLoading && <span className="text-xs text-gray-500">Updating…</span>}
                </div>
                <PeriodPicker value={period} onChange={setPeriod} />
                <div className="flex flex-wrap items-center gap-3">
                    <MultiFilterSelect
                        value={filters.companies}
                        onChange={v => update({ co: v })}
                        placeholder="All companies"
                        noun="companies"
                        options={VEHICLE_COMPANIES.map(c => ({ value: c.value, label: c.label }))}
                    />
                    <MultiFilterSelect
                        value={filters.hubs}
                        onChange={v => update({ hub: v })}
                        placeholder="All hubs"
                        noun="hubs"
                        options={[...locations.map(l => ({ value: l.name, label: l.name })), { value: NO_HUB, label: NO_HUB }]}
                    />
                    <MultiFilterSelect
                        value={filters.sites}
                        onChange={v => update({ site: v })}
                        placeholder="All sites"
                        noun="sites"
                        groups={workshopGroups}
                        options={sites.map(s => ({ value: s.name, label: formatSiteLabel(s) }))}
                    />
                    <MultiFilterSelect
                        value={filters.categories}
                        onChange={v => update({ cat: v })}
                        placeholder="All categories"
                        noun="categories"
                        options={categoryOptions}
                    />
                    <button
                        type="button"
                        onClick={() => exportMaintenanceCost(lines, `maintenance_cost_${period.start}_to_${period.end}.xlsx`)}
                        disabled={!lines.length}
                        className="sm:ml-auto inline-flex items-center px-4 py-2.5 border border-blue-600 text-sm font-medium rounded-lg text-blue-700 bg-white hover:bg-blue-50 disabled:opacity-50 whitespace-nowrap"
                    >
                        <ArrowDownTrayIcon className="h-5 w-5 mr-2" aria-hidden="true" />
                        Export to Excel
                    </button>
                </div>
            </div>

            {error ? (
                <div className="bg-white rounded-xl border border-red-200 p-6 text-sm text-red-700">Could not load costs: {error.message}</div>
            ) : isLoading ? (
                <div className="bg-white rounded-xl border border-gray-200 p-12 text-center text-sm text-gray-500">Loading…</div>
            ) : (
                <>
                    {/* Tiles */}
                    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
                        <StatTile label="Maintenance cost" value={inr(summary.total)}
                            note={`Spares ${inr(summary.spares)} · Outsourced ${inr(summary.outsourced)}`}
                            tip={explainTotal(summary)} />
                        <StatTile label="Per vehicle" value={inr(per.average)}
                            note={`${plural(per.vehicles, 'vehicle')} had a cost · median ${inr(per.median)}`}
                            tip={`Average = ${inr(summary.total)} ÷ ${plural(per.vehicles, 'vehicle')} that had a cost in the period = ${inr(per.average)}. Vehicles with no cost are left out so parked ones don't pull it down. Median: half the vehicles cost less than ${inr(per.median)}.`} />
                        <StatTile label="Job cards" value={summary.jobCards.toLocaleString('en-IN')}
                            note={`${summary.jobCardsWithCost.toLocaleString('en-IN')} carry a cost · ${summary.openJobCards} open`}
                            tip={`${plural(summary.jobCards, 'job card')} opened in the period; ${summary.jobCardsWithCost.toLocaleString('en-IN')} have spares or an outsourced invoice in it.`} />
                        <StatTile label="Labour" value={`${summary.labourHours.toLocaleString('en-IN')} hrs`} note="Hours only — no rupee rate" tip={explainLabour(summary.labourHours)} />
                        <StatTile placeholder label="Km driven" value="—" note="Waiting for Roorides distance"
                            tip="Km driven will be the sum of each vehicle's km from Roorides for the period (MAIN-169 — Distance and odometer from Roorides for cost per km)." />
                        <StatTile placeholder label="Cost per km" value="—" note="Maintenance cost ÷ km, once Roorides sends km"
                            tip="Cost per km will use only the vehicles Roorides has km for, and say how many that is. Waiting for MAIN-169." />
                    </div>

                    {/* By company */}
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                        {VEHICLE_COMPANIES.filter(c => !filters.companies.length || filters.companies.includes(c.value)).map(c => {
                            const g = companies.find(x => x.key === c.value) ?? { amount: 0, vehicles: 0 }
                            const unknown = c.value === UNKNOWN_COMPANY
                            return (
                                <div key={c.value} className={`rounded-xl p-4 border ${unknown ? 'bg-amber-50 border-amber-200' : 'bg-white border-gray-200'}`}>
                                    <div className="flex justify-between items-start gap-2">
                                        <span className="text-sm font-semibold text-gray-900">{c.label}</span>
                                        {g.vehicles > 0 && <FormulaTip text={explainPerVehicleGroup(g)} />}
                                    </div>
                                    <div className="text-2xl font-bold mt-1">{inr(g.amount)}</div>
                                    <div className={`text-xs mt-1 ${unknown ? 'text-amber-900' : 'text-gray-600'}`}>
                                        {plural(g.vehicles, 'vehicle')}{g.vehicles ? ` · ${inr(g.amount / g.vehicles)} per vehicle` : ''}
                                        {unknown && g.vehicles > 0 && ' · finance to assign these vehicles'}
                                    </div>
                                </div>
                            )
                        })}
                    </div>

                    {/* Chart, categories and hubs */}
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 items-start">
                        <CostChart lines={lines} period={period} scope="report" />
                        <section className="bg-white rounded-xl border border-gray-200 p-5 space-y-4" aria-label="By issue category and hub">
                            <h2 className="text-base font-semibold">By issue category</h2>
                            <CategoryBars groups={categories} lines={lines} />
                            {categories.some(c => c.split) && (
                                <p className="text-xs text-gray-600 bg-gray-50 rounded-lg px-3 py-2">
                                    An outsourced job card's amount is split equally across its issues' categories; the ⓘ beside a category shows the split.
                                </p>
                            )}
                            <div className="border-t border-gray-100 pt-3">
                                <h2 className="text-base font-semibold mb-2">By hub</h2>
                                <ul className="text-sm space-y-1">
                                    {hubs.map(h => (
                                        <li key={h.key} className="flex justify-between gap-3">
                                            <span>{h.key} <span className="text-gray-600">· {plural(h.jobCards, 'job card')}</span></span>
                                            <span className="font-semibold">{inr(h.amount)}</span>
                                        </li>
                                    ))}
                                </ul>
                            </div>
                        </section>
                    </div>

                    {/* Sites and vehicles */}
                    <div className="grid grid-cols-1 xl:grid-cols-2 gap-4 items-start">
                        <SortableTable
                            caption="By site"
                            rows={siteRows}
                            defaultSort={{ key: 'amount', dir: 'desc' }}
                            footer={`${plural(siteRows.length, 'site')} with a cost`}
                            columns={[
                                { key: 'site', label: 'Site', value: r => r.key, render: r => siteLabel(r.key) },
                                { key: 'vehicles', label: 'Vehicles', align: 'right', value: r => r.vehicles },
                                { key: 'amount', label: 'Cost', align: 'right', value: r => r.amount, render: r => <span className="font-semibold">{inr(r.amount)}</span> },
                                {
                                    key: 'per', label: 'Per vehicle', align: 'right', value: r => r.amount / r.vehicles,
                                    render: r => <FormulaTip text={explainPerVehicleGroup(r)} title="Per vehicle">{inr(r.amount / r.vehicles)}</FormulaTip>,
                                },
                            ]}
                        />
                        <SortableTable
                            caption="Costliest vehicles"
                            rows={vehicleRows}
                            defaultSort={{ key: 'amount', dir: 'desc' }}
                            footer={top.count ? `The costliest ${plural(top.count, 'vehicle')} (top 10% of ${vehicleRows.length}) carry ${Math.round(top.share * 100)}% of the cost (${inr(top.amount)}).` : ''}
                            columns={[
                                {
                                    key: 'vehicle', label: 'Vehicle', value: r => r.key, className: 'font-mono',
                                    render: r => <Link to={`/vehicles/${encodeURIComponent(r.key)}`} className="text-blue-700 hover:underline">{r.key}</Link>,
                                },
                                { key: 'company', label: 'Company', value: r => companyLabel(r.company) },
                                { key: 'cards', label: 'Job cards', align: 'right', value: r => r.jobCards },
                                { key: 'amount', label: 'Cost', align: 'right', value: r => r.amount, render: r => <span className="font-semibold">{inr(r.amount)}</span> },
                            ]}
                        />
                    </div>
                </>
            )}
        </div>
    )
}
