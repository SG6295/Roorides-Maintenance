import { useMemo, useState } from 'react'
import FormulaTip from '../shared/FormulaTip'
import {
    PERIOD_PRESETS, periodRange, istToday, byMonth, byOdometer, inr, inrShort,
    explainBand, splitsIn, explainSplit, REPORT_ODOMETER_CAP, THIN_BAND_VEHICLES, plural,
} from '../../utils/maintenanceCost'
import { companyLabel, companyShortLabel } from '../../constants/vehicleCompanies'

/** Bar colours per company — distinct in lightness too, not hue alone. */
const COMPANY_BAR = {
    nvs_travels: 'bg-blue-600',
    nvs_travel_solutions: 'bg-purple-400',
    unknown: 'bg-amber-300',
}

// ---------------------------------------------------------------------------
// Period picker
// ---------------------------------------------------------------------------

/** value: { preset, start, end } */
export function PeriodPicker({ value, onChange }) {
    const pick = preset => {
        if (preset === 'custom') onChange({ ...value, preset })
        else onChange({ preset, ...periodRange(preset, istToday()) })
    }
    return (
        <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Period">
            <span className="text-sm text-gray-600 mr-1">Period</span>
            {PERIOD_PRESETS.map(p => (
                <button
                    key={p.value}
                    type="button"
                    aria-pressed={value.preset === p.value}
                    onClick={() => pick(p.value)}
                    className={`px-3.5 py-2 rounded-full border text-sm ${value.preset === p.value
                        ? 'bg-blue-700 border-blue-700 text-white'
                        : 'bg-white border-gray-300 text-gray-700 hover:bg-gray-50'}`}
                >
                    {p.label}
                </button>
            ))}
            {value.preset === 'custom' && (
                <span className="flex flex-wrap items-center gap-2 text-sm">
                    <label className="flex items-center gap-1.5 text-gray-600">From
                        <input type="date" value={value.start} max={value.end}
                            onChange={e => e.target.value && onChange({ ...value, start: e.target.value })}
                            className="border border-gray-300 rounded-lg px-2 py-1.5 text-sm" />
                    </label>
                    <label className="flex items-center gap-1.5 text-gray-600">To
                        <input type="date" value={value.end} min={value.start}
                            onChange={e => e.target.value && onChange({ ...value, end: e.target.value })}
                            className="border border-gray-300 rounded-lg px-2 py-1.5 text-sm" />
                    </label>
                </span>
            )}
        </div>
    )
}

// ---------------------------------------------------------------------------
// Tile
// ---------------------------------------------------------------------------

export function StatTile({ label, value, note, tip, tone, placeholder = false }) {
    return (
        <div className={`bg-white rounded-xl p-4 ${placeholder ? 'border border-dashed border-gray-400' : 'border border-gray-200'}`}>
            <div className="flex items-start justify-between gap-2">
                <span className="text-xs text-gray-600 uppercase tracking-wide">{label}</span>
                {tip && <FormulaTip text={tip} title={placeholder ? 'Why this is empty' : undefined} />}
            </div>
            <div className={`text-2xl font-bold mt-1 ${placeholder ? 'text-gray-400' : tone === 'warn' ? 'text-amber-700' : 'text-gray-900'}`}>{value}</div>
            {note && <div className="text-xs text-gray-600 mt-1">{note}</div>}
        </div>
    )
}

// ---------------------------------------------------------------------------
// Cost by month / by odometer
// ---------------------------------------------------------------------------

const BAR_AREA = 170

function Segmented({ label, options, value, onChange, small = false }) {
    return (
        <div role="group" aria-label={label} className="inline-flex border border-gray-300 rounded-lg overflow-hidden text-xs">
            {options.map((o, i) => (
                <button
                    key={o.value}
                    type="button"
                    disabled={o.disabled}
                    title={o.title}
                    aria-pressed={value === o.value}
                    onClick={() => onChange(o.value)}
                    className={`${small ? 'px-2.5 py-1' : 'px-3 py-1.5'} ${i ? 'border-l border-gray-300' : ''} ${o.disabled
                        ? 'bg-gray-50 text-gray-400 cursor-not-allowed'
                        : value === o.value ? 'bg-blue-700 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'}`}
                >
                    {o.label}
                </button>
            ))}
        </div>
    )
}

/**
 * One chart with a switch: By month, or By odometer (10,000 km). `scope` 'vehicle' sums
 * each band; 'report' averages cost per vehicle in each band and stacks months by company.
 */
export function CostChart({ lines, period, scope = 'vehicle' }) {
    const [view, setView] = useState('month')
    const [source, setSource] = useState('job_card')
    // A period reaching into the future (This financial year) stops at today's month.
    const months = useMemo(() => {
        const today = istToday()
        return byMonth(lines, { start: period.start, end: period.end > today ? today : period.end })
    }, [lines, period])
    const odo = useMemo(
        () => byOdometer(lines, scope === 'report' ? { mode: 'perVehicle', cap: REPORT_ODOMETER_CAP } : {}),
        [lines, scope]
    )
    const stacked = scope === 'report' && new Set(lines.map(l => l.company)).size > 1

    const bars = view === 'month' ? months : odo.bands
    const max = Math.max(1, ...bars.map(b => b.amount))
    const title = view === 'month'
        ? 'Cost by month'
        : scope === 'report' ? 'Cost per vehicle by odometer' : 'Cost by odometer'

    return (
        <section className="bg-white rounded-xl border border-gray-200 p-5" aria-label={title}>
            <div className="flex flex-wrap items-center justify-between gap-3">
                <h2 className="text-base font-semibold text-gray-900">{title}</h2>
                <Segmented
                    label="Chart by"
                    value={view}
                    onChange={setView}
                    options={[{ value: 'month', label: 'By month' }, { value: 'odometer', label: 'By odometer (10,000 km)' }]}
                />
            </div>

            {view === 'odometer' && (
                <div className="flex flex-wrap items-center gap-2 mt-2 text-xs text-gray-600">
                    <span>Reading from</span>
                    <Segmented
                        small
                        label="Reading from"
                        value={source}
                        onChange={setSource}
                        options={[
                            { value: 'job_card', label: 'Job card' },
                            { value: 'roorides', label: 'Roorides (after MAIN-169)', disabled: true, title: "Roorides' reading arrives with MAIN-169" },
                        ]}
                    />
                </div>
            )}

            <p className="text-xs text-gray-600 mt-2">
                {view === 'month'
                    ? 'A spare counts in the month it was added; an outsourced or multi-vehicle invoice on its date of activity.'
                    : scope === 'report'
                        ? `Band cost ÷ vehicles with a job card in that band, by the odometer typed on the job card. Lighter bars: fewer than ${THIN_BAND_VEHICLES} vehicles.`
                        : 'Spend per 10,000 km of the odometer typed on each job card.'}
            </p>

            {bars.length === 0 ? (
                <p className="text-sm text-gray-500 py-10 text-center">
                    {view === 'month' ? 'No cost in this period.' : 'No job card in this period has an odometer reading.'}
                </p>
            ) : (
                <div className="overflow-x-auto">
                    <div className="min-w-full" style={{ minWidth: `${bars.length * 34}px` }}>
                        <div className="flex items-end gap-1.5 border-b border-gray-300 px-1 mt-4" style={{ height: BAR_AREA + 24 }}>
                            {bars.map(b => {
                                const h = b.amount > 0 ? Math.max(3, Math.round((b.amount / max) * BAR_AREA)) : 0
                                const tip = view === 'month'
                                    ? `${b.label}: ${inr(b.amount)}${stacked ? ` — ${Object.entries(b.byCompany).map(([c, a]) => `${companyShortLabel(c)} ${inr(a)}`).join(', ')}` : ''}.`
                                    : explainBand(b, scope === 'report' ? 'perVehicle' : 'total')
                                return (
                                    <div key={view === 'month' ? b.key : b.start} className="flex-1 flex flex-col items-center justify-end h-full min-w-[26px]">
                                        <span className="text-[10px] text-gray-600 mb-1">{b.amount > 0 ? inrShort(b.amount) : '0'}</span>
                                        <FormulaTip text={tip} title={view === 'month' ? 'This month' : 'This band'} className="w-full max-w-[72px]" triggerClassName="w-full block" triggerLabel={view === 'month' ? `${b.label}: ${inr(b.amount)}` : `${b.start / 1000}k km band: ${inr(b.amount)}`} align="left">
                                            <span className="flex flex-col-reverse w-full" style={{ height: h }}>
                                                {view === 'month' && stacked
                                                    ? Object.entries(b.byCompany).map(([c, a]) => (
                                                        <span key={c} className={`block w-full ${COMPANY_BAR[c] ?? 'bg-gray-400'}`} style={{ height: `${(a / b.amount) * 100}%` }} />
                                                    ))
                                                    : <span className={`block w-full h-full rounded-t ${b.thin ? 'bg-blue-300' : 'bg-blue-600'}`} />}
                                            </span>
                                        </FormulaTip>
                                    </div>
                                )
                            })}
                        </div>
                        <div className="flex gap-1.5 px-1 pt-1.5 text-[10px] text-gray-600">
                            {bars.map(b => (
                                <span key={view === 'month' ? b.key : b.start} className="flex-1 text-center min-w-[26px]">
                                    {view === 'month' ? b.label : `${b.start / 1000}k`}
                                </span>
                            ))}
                        </div>
                        {view === 'odometer' && (
                            <p className="text-[11px] text-gray-600 text-center mt-1">Odometer at the job card (km, start of each 10,000 km band)</p>
                        )}
                    </div>
                </div>
            )}

            {view === 'month' && stacked && (
                <div className="flex flex-wrap gap-4 mt-3 text-xs text-gray-700">
                    {Object.entries(COMPANY_BAR).map(([c, cls]) => (
                        <span key={c} className="flex items-center gap-1.5"><span className={`w-3 h-3 rounded-sm ${cls}`} />{companyLabel(c)}</span>
                    ))}
                </div>
            )}

            {view === 'odometer' && (odo.noReading.amount > 0 || odo.beyond.amount > 0) && (
                <div className="flex gap-2 items-start text-xs text-amber-900 bg-amber-50 rounded-lg px-3 py-2 mt-3">
                    <span>
                        Not on the chart:{' '}
                        {odo.noReading.amount > 0 && `${inr(odo.noReading.amount)} on ${plural(odo.noReading.jobCards.length, 'job card')} with no odometer reading`}
                        {odo.noReading.amount > 0 && odo.beyond.amount > 0 && ', and '}
                        {odo.beyond.amount > 0 && `${inr(odo.beyond.amount)} on readings of ${REPORT_ODOMETER_CAP.toLocaleString('en-IN')} km or more`}
                        . Fills in as readings are entered — they are required before a job card is closed.
                    </span>
                    {scope === 'vehicle' && odo.noReading.jobCards.length > 0 && (
                        <FormulaTip
                            title="Job cards with no reading"
                            text={odo.noReading.jobCards.map(n => (typeof n === 'number' ? `JC ${n}` : n)).join(', ')}
                        />
                    )}
                </div>
            )}
        </section>
    )
}

// ---------------------------------------------------------------------------
// Cost by category
// ---------------------------------------------------------------------------

/** groups from byCategory(); `onSelect(key)` filters elsewhere when given. */
export function CategoryBars({ groups, lines, selected = null, onSelect = null }) {
    const max = Math.max(1, ...groups.map(g => g.amount))
    if (!groups.length) return <p className="text-sm text-gray-500 py-4">No cost in this period.</p>
    return (
        <ul className="space-y-2.5">
            {groups.map(g => {
                const splits = g.split ? splitsIn(lines, g.key) : []
                const row = (
                    <>
                        <span className="truncate text-left" title={g.key}>{g.key}</span>
                        <span className="h-2.5 bg-gray-100 rounded-full" aria-hidden="true">
                            <span className="block h-2.5 rounded-full bg-blue-600" style={{ width: `${Math.max(1, (g.amount / max) * 100)}%` }} />
                        </span>
                        <span className="text-right font-semibold">{inr(g.amount)}</span>
                    </>
                )
                return (
                    <li key={g.key} className="flex items-center gap-1">
                        {onSelect ? (
                            <button
                                type="button"
                                onClick={() => onSelect(selected === g.key ? null : g.key)}
                                aria-pressed={selected === g.key}
                                className={`flex-1 grid grid-cols-[140px_1fr_90px] gap-2.5 items-center text-sm rounded px-1 py-0.5 ${selected === g.key ? 'bg-blue-50 ring-1 ring-blue-300' : 'hover:bg-gray-50'}`}
                            >
                                {row}
                            </button>
                        ) : (
                            <span className="flex-1 grid grid-cols-[140px_1fr_90px] gap-2.5 items-center text-sm px-1">{row}</span>
                        )}
                        <span className="w-6">
                            {splits.length > 0 && (
                                <FormulaTip
                                    title="Includes a split outsourced amount"
                                    label={`How ${g.key} includes split outsourced amounts`}
                                    text={splits.map(explainSplit).join(' ')}
                                />
                            )}
                        </span>
                    </li>
                )
            })}
        </ul>
    )
}
