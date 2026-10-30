import { useState, useMemo } from 'react'
import { Link } from 'react-router-dom'
import { format, parseISO, startOfMonth } from 'date-fns'
import { ArrowDownTrayIcon } from '@heroicons/react/24/outline'
import { useLabourReport } from '../../hooks/useLabourReport'
import { useAllSites } from '../../hooks/useSites'
import { formatSiteLabel } from '../../utils/siteLabel'
import { todayLocal } from '../../utils/datetime'
import { formatHours } from '../../utils/labour'
import {
    MAX_GRID_DAYS, HOUR_BANDS, hourBand, enumerateDays, dayCount,
    filterRows, summarise, buildGrid, rankSites, siteSlices,
} from '../../utils/labourReport'
import { exportLabourToExcel } from '../../utils/labourExport'
import { ROLE_LABELS } from '../../constants/userRoles'
import DateRangeFilter from '../../components/tickets/DateRangeFilter'
import MultiFilterSelect from '../../components/shared/MultiFilterSelect'
import FilterSelect from '../../components/shared/FilterSelect'

// Categorical slice colours; "Other" is always the grey.
const SLICE_COLORS = ['#2563eb', '#d97706', '#059669', '#7c3aed', '#db2777', '#0891b2']
const OTHER_COLOR = '#9ca3af'

/**
 * Analytics › Labour utilisation (MAIN-117). Hours per technician per day and per site,
 * placed by each work item's activity complete date (issues.completed_on).
 */
export default function LabourUtilisation() {
    const [dateRange, setDateRange] = useState({
        start: format(startOfMonth(new Date()), 'yyyy-MM-dd'),
        end: todayLocal(),
    })
    const [selectedSites, setSelectedSites] = useState([])
    const [trade, setTrade] = useState('')
    const [technicianId, setTechnicianId] = useState('')

    const { data: rows = [], isLoading, isFetching, error } = useLabourReport(dateRange)
    const { data: sites = [] } = useAllSites()

    const days = useMemo(() => enumerateDays(dateRange.start, dateRange.end), [dateRange])
    const tooManyDays = dayCount(dateRange.start, dateRange.end) > MAX_GRID_DAYS

    // Technicians come from the data, not the active-user list, so someone who has since
    // left still appears for the period they worked.
    const technicianOptions = useMemo(() => {
        const seen = new Map()
        for (const r of rows) if (r.attributed && r.technician_id) seen.set(r.technician_id, r.technician_name)
        return [...seen.entries()]
            .map(([value, label]) => ({ value, label: label || 'Unknown' }))
            .sort((a, b) => a.label.localeCompare(b.label))
    }, [rows])

    const filtered = useMemo(
        () => filterRows(rows, { sites: selectedSites, trade, technicianId }),
        [rows, selectedSites, trade, technicianId]
    )
    const summary = useMemo(() => summarise(filtered), [filtered])
    const grid = useMemo(() => (tooManyDays ? null : buildGrid(filtered, days)), [filtered, days, tooManyDays])
    const ranked = useMemo(() => rankSites(filtered), [filtered])
    const slices = useMemo(() => siteSlices(ranked), [ranked])

    const siteLabel = useMemo(() => {
        const byName = new Map(sites.map(s => [s.name, formatSiteLabel(s)]))
        return (name) => byName.get(name) || name
    }, [sites])

    return (
        <div className="space-y-5">
            {/* Header & filters */}
            <div className="bg-white rounded-xl border border-gray-200 px-4 py-4 space-y-3">
                <div className="flex flex-wrap items-center gap-3">
                    <h1 className="text-xl font-bold text-gray-900">Labour utilisation</h1>
                    {isFetching && !isLoading && <span className="text-xs text-gray-500">Updating…</span>}
                </div>
                <div className="flex flex-wrap items-center gap-3">
                    <DateRangeFilter dateRange={dateRange} onDateRangeChange={setDateRange} />
                    <MultiFilterSelect
                        value={selectedSites}
                        onChange={setSelectedSites}
                        placeholder="All Sites"
                        noun="sites"
                        options={sites.map(s => ({ value: s.name, label: formatSiteLabel(s) }))}
                    />
                    <FilterSelect
                        value={trade}
                        onChange={setTrade}
                        placeholder="All Trades"
                        options={[
                            { value: 'mechanic', label: ROLE_LABELS.mechanic },
                            { value: 'electrician', label: ROLE_LABELS.electrician },
                        ]}
                    />
                    <FilterSelect
                        value={technicianId}
                        onChange={setTechnicianId}
                        placeholder="All Technicians"
                        options={technicianOptions}
                    />
                    <button
                        type="button"
                        onClick={() => exportLabourToExcel({ grid: grid || buildGrid([], []), days: grid ? days : [], rows: filtered, dateRange })}
                        disabled={!filtered.length}
                        className="sm:ml-auto inline-flex items-center px-4 py-2.5 border border-blue-600 text-sm font-medium rounded-lg text-blue-600 bg-white hover:bg-blue-50 disabled:opacity-50 whitespace-nowrap"
                    >
                        <ArrowDownTrayIcon className="h-5 w-5 mr-2" />
                        Export to Excel
                    </button>
                </div>
                {(trade || technicianId) && (
                    <p className="text-xs text-gray-500">Hours logged before per-person tracking are left out while a trade or technician filter is on.</p>
                )}
            </div>

            {error ? (
                <div className="bg-white rounded-xl border border-red-200 p-6 text-sm text-red-700">
                    Could not load labour: {error.message}
                </div>
            ) : isLoading ? (
                <div className="bg-white rounded-xl border border-gray-200 p-12 text-center text-sm text-gray-500">Loading…</div>
            ) : (
                <>
                    {/* Tiles */}
                    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
                        <Tile
                            label="Total labour hours"
                            value={formatHours(summary.totalHours)}
                            note={`${summary.workItems} work item${summary.workItems === 1 ? '' : 's'}`}
                        />
                        <Tile
                            label="Avg per technician per day"
                            value={summary.avgPerTechnicianDay ? `${formatHours(summary.avgPerTechnicianDay)} h` : '—'}
                            note={`${summary.technicianCount} technician${summary.technicianCount === 1 ? '' : 's'} · days they logged hours`}
                        />
                        <Tile
                            label="Sites served"
                            value={summary.sitesServed}
                            note={summary.topSite ? `Top: ${summary.topSite.site} · ${Math.round(summary.topSite.share * 100)}%` : '—'}
                        />
                        <Tile
                            label="Unattributed"
                            value={`${formatHours(summary.unattributedHours)} h`}
                            note="Logged before per-person tracking"
                        />
                    </div>
                    {summary.openHours > 0 && (
                        <p className="text-xs text-gray-600 -mt-2">
                            Plus {formatHours(summary.openHours)} h on work items not yet done — they count once completed.
                        </p>
                    )}

                    {/* Technician × day */}
                    <section className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
                        <div className="flex flex-wrap items-center gap-3">
                            <h2 className="text-base font-semibold text-gray-900">Hours per technician per day</h2>
                            <div className="sm:ml-auto flex flex-wrap items-center gap-2 text-xs text-gray-600">
                                {HOUR_BANDS.map(b => (
                                    <span key={b.label} className="inline-flex items-center gap-1">
                                        <span className={`w-3.5 h-3.5 rounded ${b.className.split(' ')[0]}`} aria-hidden="true" />
                                        {b.label}
                                    </span>
                                ))}
                            </div>
                        </div>

                        {tooManyDays ? (
                            <p className="text-sm text-gray-600 py-6 text-center">
                                The daily grid shows up to {MAX_GRID_DAYS} days. Pick a shorter date range to see it.
                            </p>
                        ) : grid.technicians.length === 0 ? (
                            <p className="text-sm text-gray-600 py-6 text-center">
                                No hours recorded against a technician in this period
                                {summary.unattributedHours > 0 && ` — the ${formatHours(summary.unattributedHours)} h here were logged before per-person tracking`}.
                            </p>
                        ) : (
                            <LabourGrid grid={grid} days={days} />
                        )}

                        <p className="text-xs text-gray-500">
                            Hours fall on the day each work item was completed, so a job that took several days shows on its last day.
                            Hover a cell for the work items behind it.
                        </p>
                    </section>

                    {/* Site-wise */}
                    <section className="flex flex-wrap gap-4">
                        <div className="flex-[1_1_22rem] min-w-0 bg-white rounded-xl border border-gray-200 p-4 space-y-3">
                            <h2 className="text-base font-semibold text-gray-900">Site-wise share</h2>
                            {slices.length === 0 ? (
                                <p className="text-sm text-gray-600 py-6 text-center">No labour in this period.</p>
                            ) : (
                                <div className="flex flex-wrap items-center gap-5">
                                    <Donut slices={slices} total={summary.totalHours} siteCount={ranked.length} />
                                    <ul className="flex-1 min-w-[10rem] space-y-1.5">
                                        {slices.map((s, i) => (
                                            <li key={s.label} className="flex items-center gap-2 text-sm" title={s.other ? undefined : siteLabel(s.label)}>
                                                <span className="w-3 h-3 rounded-sm shrink-0" style={{ background: s.other ? OTHER_COLOR : SLICE_COLORS[i] }} aria-hidden="true" />
                                                <span className="flex-1 truncate text-gray-800">{s.label}</span>
                                                <span className="text-gray-600 tabular-nums">{Math.round(s.share * 100)}%</span>
                                            </li>
                                        ))}
                                    </ul>
                                </div>
                            )}
                        </div>

                        <div className="flex-[1_1_22rem] min-w-0 bg-white rounded-xl border border-gray-200 p-4 space-y-3">
                            <div className="flex items-center">
                                <h2 className="text-base font-semibold text-gray-900">All sites, ranked</h2>
                                <span className="ml-auto text-xs text-gray-500">hrs</span>
                            </div>
                            {ranked.length === 0 ? (
                                <p className="text-sm text-gray-600 py-6 text-center">No labour in this period.</p>
                            ) : (
                                <ul className="space-y-2 max-h-72 overflow-y-auto pr-1">
                                    {ranked.map(s => (
                                        <li key={s.site} className="grid grid-cols-[5rem_minmax(0,1fr)_3.5rem] items-center gap-3" title={siteLabel(s.site)}>
                                            <span className="text-sm text-gray-800 truncate">{s.site}</span>
                                            <span className="h-3.5 bg-gray-100 rounded">
                                                <span className="block h-3.5 bg-blue-600 rounded" style={{ width: `${(s.hours / ranked[0].hours) * 100}%` }} />
                                            </span>
                                            <span className="text-sm text-gray-700 text-right tabular-nums">{formatHours(s.hours)}</span>
                                        </li>
                                    ))}
                                </ul>
                            )}
                        </div>
                    </section>
                </>
            )}
        </div>
    )
}

function Tile({ label, value, note }) {
    return (
        <div className="bg-white rounded-xl border border-gray-200 px-4 py-3.5">
            <p className="text-xs text-gray-600">{label}</p>
            <p className="text-2xl font-bold text-gray-900 mt-0.5 tabular-nums">{value}</p>
            <p className="text-xs text-gray-500 mt-0.5 truncate">{note}</p>
        </div>
    )
}

function LabourGrid({ grid, days }) {
    return (
        <div className="overflow-x-auto">
            <table className="border-separate border-spacing-[3px] text-xs">
                <thead>
                    <tr>
                        <th className="sticky left-0 z-10 bg-white text-left font-semibold text-gray-600 pr-3 min-w-[9rem]">Technician</th>
                        {days.map(d => {
                            const date = parseISO(d)
                            const weekend = [0, 6].includes(date.getDay())
                            return (
                                <th key={d} className={`min-w-[2.5rem] px-0.5 py-1 rounded text-center font-semibold ${weekend ? 'bg-gray-50 text-gray-500' : 'text-gray-800'}`}>
                                    <span className="block font-normal text-[10px]">{format(date, 'EEE')}</span>
                                    {format(date, 'd')}
                                    {date.getDate() === 1 && <span className="block font-normal text-[10px]">{format(date, 'MMM')}</span>}
                                </th>
                            )
                        })}
                        <th className="px-2 text-right font-semibold text-gray-800">Total</th>
                    </tr>
                </thead>
                <tbody>
                    {grid.technicians.map(t => (
                        <tr key={t.id}>
                            <td className="sticky left-0 z-10 bg-white pr-3 py-0.5 whitespace-nowrap">
                                <Link to={`/mechanics/${t.id}`} className="block text-sm text-blue-600 hover:underline">{t.name}</Link>
                                <span className="text-[11px] text-gray-500">{ROLE_LABELS[t.role] || t.role}</span>
                            </td>
                            {t.cells.map(c => (
                                <td
                                    key={c.day}
                                    title={c.items.length ? `${format(parseISO(c.day), 'dd MMM')}\n${c.items.join('\n')}` : undefined}
                                    className={`h-9 rounded text-center font-semibold tabular-nums ${HOUR_BANDS[hourBand(c.hours)].className}`}
                                >
                                    {c.hours ? formatHours(c.hours) : '–'}
                                </td>
                            ))}
                            <td className="px-2 text-right text-sm font-bold text-gray-900 tabular-nums">{formatHours(t.total)}</td>
                        </tr>
                    ))}
                    <tr>
                        <td className="sticky left-0 z-10 bg-white pr-3 pt-2 text-xs font-semibold text-gray-600 border-t border-gray-200">Day total</td>
                        {grid.dayTotals.map((h, i) => (
                            <td key={days[i]} className="pt-2 text-center font-semibold text-gray-700 border-t border-gray-200 tabular-nums">
                                {h ? formatHours(h) : ''}
                            </td>
                        ))}
                        <td className="px-2 pt-2 text-right text-sm font-bold text-gray-900 border-t border-gray-200 tabular-nums">{formatHours(grid.grandTotal)}</td>
                    </tr>
                </tbody>
            </table>
        </div>
    )
}

function Donut({ slices, total, siteCount }) {
    const r = 62
    const circumference = 2 * Math.PI * r
    // Where each slice starts along the ring: the lengths of the slices before it
    const starts = slices.map((_, i) => slices.slice(0, i).reduce((s, x) => s + x.share * circumference, 0))
    return (
        <svg width="170" height="170" viewBox="0 0 170 170" role="img"
            aria-label={`Labour hours by site: ${slices.map(s => `${s.label} ${Math.round(s.share * 100)}%`).join(', ')}`}>
            <circle cx="85" cy="85" r={r} fill="none" stroke="#f3f4f6" strokeWidth="26" />
            {slices.map((s, i) => {
                const len = s.share * circumference
                // A 2px gap between slices, unless a single slice is the whole ring
                const gap = slices.length > 1 ? 2 : 0
                return (
                    <circle
                        key={s.label}
                        cx="85" cy="85" r={r} fill="none"
                        stroke={s.other ? OTHER_COLOR : SLICE_COLORS[i]}
                        strokeWidth="26"
                        strokeDasharray={`${Math.max(len - gap, 0)} ${circumference - len + gap}`}
                        strokeDashoffset={-starts[i]}
                        transform="rotate(-90 85 85)"
                    />
                )
            })}
            <text x="85" y="82" textAnchor="middle" fontSize="22" fontWeight="700" fill="#111827">{formatHours(total)}</text>
            <text x="85" y="101" textAnchor="middle" fontSize="11" fill="#4b5563">hrs · {siteCount} site{siteCount === 1 ? '' : 's'}</text>
        </svg>
    )
}
