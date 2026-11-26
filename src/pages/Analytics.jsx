import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { format, subMonths, endOfMonth } from 'date-fns'
import Navigation from '../components/shared/Navigation'
import { useAllSites } from '../hooks/useSites'
import { formatSiteLabel } from '../utils/siteLabel'
import { useWorkshopSiteGroups } from '../hooks/useSiteWorkshops'
import MultiFilterSelect from '../components/shared/MultiFilterSelect'
import DateRangeFilter from '../components/tickets/DateRangeFilter'
import { buildSlaReport, slaReportCsv, percentText } from '../utils/slaReport'
import { ArrowDownTrayIcon, CheckCircleIcon, ClockIcon, ExclamationTriangleIcon } from '@heroicons/react/24/outline'

/**
 * Analytics › SLA & tickets. `embedded` drops the page's own navigation when it sits inside
 * AnalyticsLayout, which supplies it (MAIN-117).
 */
export default function Analytics({ embedded = false }) {
    // All sites, not just active — reporting on a departed school must still be possible.
    const { data: sites = [] } = useAllSites()
    // Workshop rows in the site filter tick the sites mapped to them (MAIN-131).
    const workshopGroups = useWorkshopSiteGroups(sites)
    // [] = all sites. Exact `sites.name` values — matching is case-sensitive.
    const [selectedSites, setSelectedSites] = useState([])
    const [dateRange, setDateRange] = useState({
        start: format(subMonths(new Date(), 11), 'yyyy-MM-01'), // Default last 12 months
        end: format(endOfMonth(new Date()), 'yyyy-MM-dd')
    })

    // One call for the whole selection: the counts come back pooled and every rate below
    // is computed from pooled counts. Never fetch per site and average the percentages
    // (MAIN-86). Which bucket a ticket or issue counts in is decided in the database
    // (analytics_ticket_rows / analytics_issue_rows, MAIN-171) — this page only lays the
    // counts out.
    const { data: stats = null } = useQuery({
        queryKey: ['analytics', dateRange, selectedSites],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_maintenance_stats', {
                p_filters: { from: dateRange.start, to: dateRange.end, sites: selectedSites }
            })
            if (error) throw error
            return data
        }
    })

    // Live overdue count — ignores date range, always reflects right now, but follows
    // the site filter.
    const { data: overdueCount = 0 } = useQuery({
        queryKey: ['overdue_tickets_live', selectedSites],
        queryFn: async () => {
            let query = supabase
                .from('tickets')
                .select('*', { count: 'exact', head: true })
                .not('status', 'in', '("Resolved","Closed","Rejected")')
                .lt('final_sla_end_date', new Date().toISOString())
            if (selectedSites.length) query = query.in('site', selectedSites)
            const { count, error } = await query
            if (error) throw error
            return count || 0
        },
        refetchInterval: 5 * 60 * 1000
    })

    // The screen and the Download are both drawn from this, so they cannot disagree.
    const report = useMemo(() => buildSlaReport(stats), [stats])

    const downloadCSV = () => {
        if (!report) return
        const csv = slaReportCsv(report, { start: dateRange.start, end: dateRange.end, sites: selectedSites })
        // The byte-order mark makes Excel read the file as UTF-8, so "–" and "₹"-style
        // characters don't arrive garbled.
        const blob = new Blob(['﻿', csv], { type: 'text/csv;charset=utf-8' })
        const url = window.URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = `detailed_maintenance_stats_${format(new Date(), 'yyyyMMdd')}.csv`
        a.click()
        window.URL.revokeObjectURL(url)
    }

    return (
        <div className={embedded ? '' : 'min-h-screen bg-gray-50 pb-12'}>
            {!embedded && <Navigation breadcrumbs={[{ label: 'Analytics' }]} />}

            {/* Header & Filters */}
            <div className={embedded ? 'bg-white rounded-xl border border-gray-200' : 'bg-white border-b sticky top-0 z-10'}>
                <div className={embedded ? 'px-4 py-4' : 'max-w-7xl mx-auto px-4 sm:px-6 py-4'}>
                    <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                        <h1 className="text-2xl font-bold text-gray-900 mb-4 sm:mb-0">SLA &amp; tickets</h1>

                        <div className="flex flex-wrap items-center gap-3 w-full sm:w-auto">
                            {/* Date Filter */}
                            <DateRangeFilter dateRange={dateRange} onDateRangeChange={setDateRange} />

                            {/* Site Filter */}
                            <MultiFilterSelect
                                value={selectedSites}
                                onChange={setSelectedSites}
                                placeholder="All Sites"
                                noun="sites"
                                groups={workshopGroups}
                                options={sites.map(s => ({ value: s.name, label: formatSiteLabel(s) }))}
                            />

                            <button
                                onClick={downloadCSV}
                                className="inline-flex items-center px-4 py-2.5 border border-blue-600 shadow-sm text-sm font-medium rounded-lg text-blue-600 bg-white hover:bg-blue-50 whitespace-nowrap"
                            >
                                <ArrowDownTrayIcon className="h-5 w-5 mr-2" />
                                Export Report
                            </button>
                        </div>
                    </div>
                </div>
            </div>

            <div className={embedded ? 'py-6 space-y-10' : 'max-w-7xl mx-auto px-4 sm:px-6 py-8 space-y-10'}>

                {/* SLA Performance */}
                <div>
                    <h2 className="text-base font-semibold text-gray-700 mb-4">SLA Performance</h2>
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
                        <SLAKPICard
                            title="Overall SLA Adherence"
                            subtitle={`${dateRange.start} – ${dateRange.end}`}
                            rate={report?.completion.percentAll}
                            detail={report ? `${report.completion.all.Adhered || 0} adhered · ${report.completion.all.Violated || 0} violated${report.completion.all.NA ? ` · ${report.completion.all.NA} not applicable` : ''} (of ${report.completion.total} total tickets)` : null}
                            icon={<CheckCircleIcon className="w-5 h-5" />}
                        />
                        <SLAKPICard
                            title="Acceptance SLA Compliance"
                            subtitle={`${dateRange.start} – ${dateRange.end}`}
                            rate={report?.acceptance.percent}
                            detail={report ? `${report.acceptance.adhered} on time · ${report.acceptance.violated} late${report.acceptance.na ? ` · ${report.acceptance.na} not applicable` : ''} · ${report.acceptance.pending} awaiting issue` : null}
                            icon={<ClockIcon className="w-5 h-5" />}
                        />
                        <SLAKPICard
                            title="Currently Overdue"
                            subtitle="Live — open tickets past deadline"
                            count={overdueCount}
                            icon={<ExclamationTriangleIcon className="w-5 h-5" />}
                        />
                    </div>
                </div>

                {/* Every table's rows add up to its total (MAIN-171). */}
                {report && (
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">

                        <VerticalTable title="Tickets by Status">
                            <Row label="Total" value={report.status.total} bold />
                            {report.status.rows.map(r => (
                                <Row key={r.key} label={r.label} value={r.value} color={STATUS_COLORS[r.key]} />
                            ))}
                        </VerticalTable>

                        <VerticalTable title="Issues by Job Card Type">
                            {report.jobCardType.rows.map(r => (
                                <Row key={r.key} label={r.label} value={r.value} color={r.key === 'none' ? 'text-gray-500' : undefined} />
                            ))}
                            <Row label="Total" value={report.jobCardType.total} bold />
                        </VerticalTable>

                        {report.severities.map(s => (
                            <VerticalTable key={s.severity} title={`Issues by Severity (${s.severity})`}>
                                <Row label={`${s.severity} Total`} value={s.total} bold />
                                {s.rows.map(r => <Row key={r.key} label={r.label} value={r.value} />)}
                            </VerticalTable>
                        ))}

                        <div className="lg:col-span-2">
                            <CompletionTable completion={report.completion} />
                        </div>

                        <VerticalTable title="Ratings & Feedback">
                            <Row label="Rating Pending" value={report.ratings.pending} color="text-gray-500" />
                            <Row label="Ratings Collected" value={report.ratings.collected} />
                            <Row label="Collection % (Sharan KPI)" value={percentText(report.ratings.collectionPercent)} bold />
                            <Row label="Good" value={report.ratings.good} color="text-green-600" />
                            <Row label="Ok" value={report.ratings.ok} color="text-yellow-600" />
                            <Row label="Bad" value={report.ratings.bad} color="text-red-600" />
                            <Row label="CSAT % (Manjunath KPI)" value={percentText(report.ratings.csatPercent)} bold />
                        </VerticalTable>

                    </div>
                )}
            </div>
        </div>
    )
}

const STATUS_COLORS = {
    New: 'text-yellow-600',
    Accepted: 'text-blue-600',
    'Work In Progress': 'text-purple-600',
    Resolved: 'text-green-600',
    Closed: 'text-gray-600',
    Rejected: 'text-red-600',
}

const RESULT_COLORS = { Adhered: 'text-green-600', Violated: 'text-red-600', NA: 'text-gray-500' }

/**
 * Completion SLA, one column per job card type of the ticket: Outsource if any of its
 * issues is on an Outsource job card, else In-house if any is on an In-house one, else
 * No job card yet; tickets with no issues on their own. All = every ticket.
 */
function CompletionTable({ completion }) {
    const cols = completion.columns
    const th = 'px-4 py-3 text-right text-xs font-semibold text-gray-600 uppercase tracking-wide whitespace-nowrap'
    const td = 'px-4 py-3 text-right text-sm whitespace-nowrap'
    return (
        <div className="bg-white shadow sm:rounded-lg overflow-hidden">
            <div className="px-4 py-3 bg-gray-50 border-b border-gray-300">
                <h3 className="text-base font-semibold text-gray-900">Completion SLA</h3>
                <p className="text-xs text-gray-500 mt-0.5">
                    By the ticket's job card type. In-house SLA % is Sharan's KPI; Outsource SLA % is Manjunath's KPI.
                </p>
            </div>
            <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                    <thead>
                        <tr>
                            <th className="px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase tracking-wide">Job card type</th>
                            {cols.map(c => <th key={c.key} className={th}>{c.label}</th>)}
                            <th className={th}>All</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-200">
                        {completion.rows.map(r => (
                            <tr key={r.key} className="hover:bg-gray-50">
                                <td className="px-4 py-3 text-sm text-gray-600 font-medium">{r.label}</td>
                                {cols.map(c => (
                                    <td key={c.key} className={`${td} ${RESULT_COLORS[r.key] || 'text-gray-900'}`}>{r.values[c.key]}</td>
                                ))}
                                <td className={`${td} ${RESULT_COLORS[r.key] || 'text-gray-900'}`}>{r.all}</td>
                            </tr>
                        ))}
                        <tr className="bg-gray-50">
                            <td className="px-4 py-3 text-sm text-gray-900 font-bold">Total</td>
                            {cols.map(c => <td key={c.key} className={`${td} font-bold text-gray-900`}>{completion.totals[c.key]}</td>)}
                            <td className={`${td} font-bold text-gray-900`}>{completion.total}</td>
                        </tr>
                        <tr>
                            <td className="px-4 py-3 text-sm text-gray-900 font-bold">SLA %</td>
                            {cols.map(c => <td key={c.key} className={`${td} font-bold text-gray-900`}>{percentText(completion.percents[c.key])}</td>)}
                            <td className={`${td} font-bold text-gray-900`}>{percentText(completion.percentAll)}</td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
    )
}

function VerticalTable({ title, children }) {
    return (
        <div className="bg-white shadow sm:rounded-lg overflow-hidden">
            <div className="px-4 py-3 bg-gray-50 border-b border-gray-300">
                <h3 className="text-base font-semibold text-gray-900">{title}</h3>
            </div>
            <div className="divide-y divide-gray-200">
                {children}
            </div>
        </div>
    )
}

function Row({ label, value, color = "text-gray-900", bold = false }) {
    return (
        <div className="flex justify-between items-center px-4 py-3 hover:bg-gray-50">
            <span className="text-sm text-gray-600 font-medium">{label}</span>
            <span className={`text-sm ${color} ${bold ? 'font-bold' : ''}`}>{value}</span>
        </div>
    )
}

function SLAKPICard({ title, subtitle, rate, detail, count, icon }) {
    const isCountCard = count !== undefined

    const rateColor = rate === null || rate === undefined
        ? 'text-gray-400'
        : rate >= 80 ? 'text-green-600'
        : rate >= 60 ? 'text-yellow-500'
        : 'text-red-600'

    const barColor = rate >= 80 ? 'bg-green-500' : rate >= 60 ? 'bg-yellow-400' : 'bg-red-500'

    const countColor = count === 0 ? 'text-green-600' : count <= 3 ? 'text-yellow-500' : 'text-red-600'

    return (
        <div className="bg-white rounded-lg shadow p-5 flex flex-col gap-3">
            <div className="flex items-center justify-between">
                <p className="text-sm font-semibold text-gray-700">{title}</p>
                <span className="text-gray-400">{icon}</span>
            </div>

            {isCountCard ? (
                <div className={`text-4xl font-bold ${countColor}`}>{count}</div>
            ) : (
                <>
                    <div className={`text-4xl font-bold ${rateColor}`}>
                        {rate !== null && rate !== undefined ? `${rate}%` : '—'}
                    </div>
                    <div className="w-full bg-gray-100 rounded-full h-1.5">
                        <div
                            className={`h-1.5 rounded-full transition-all ${barColor}`}
                            style={{ width: `${rate ?? 0}%` }}
                        />
                    </div>
                </>
            )}

            <div className="space-y-0.5">
                {detail && <p className="text-xs text-gray-500">{detail}</p>}
                <p className="text-xs text-gray-400">{subtitle}</p>
            </div>
        </div>
    )
}

