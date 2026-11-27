import { useMemo } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { format, subMonths, endOfMonth } from 'date-fns'
import Navigation from '../components/shared/Navigation'
import { useAllSites } from '../hooks/useSites'
import { formatSiteLabel } from '../utils/siteLabel'
import { useWorkshopSiteGroups } from '../hooks/useSiteWorkshops'
import MultiFilterSelect from '../components/shared/MultiFilterSelect'
import DateRangeFilter from '../components/tickets/DateRangeFilter'
import { buildSlaReport, slaReportCsv, percentText, percent } from '../utils/slaReport'
import { analyticsHref } from '../utils/analyticsDrill'
import { ArrowDownTrayIcon, CheckCircleIcon, ClockIcon, ExclamationTriangleIcon } from '@heroicons/react/24/outline'

/**
 * Analytics › SLA & tickets. `embedded` drops the page's own navigation when it sits inside
 * AnalyticsLayout, which supplies it (MAIN-117).
 *
 * The period and sites live in the address (`from`, `to`, `site`), so a reload or a shared
 * link opens the same view. Every count opens, in a new tab, the Tickets or Issues list of
 * exactly the records it counted (MAIN-152, src/utils/analyticsDrill.js).
 */
export default function Analytics({ embedded = false }) {
    // All sites, not just active — reporting on a departed school must still be possible.
    const { data: sites = [] } = useAllSites()
    // Workshop rows in the site filter tick the sites mapped to them (MAIN-131).
    const workshopGroups = useWorkshopSiteGroups(sites)
    const [params, setParams] = useSearchParams()
    // [] = all sites. Exact `sites.name` values — matching is case-sensitive.
    const siteKey = params.getAll('site').join('\n')
    const selectedSites = useMemo(() => (siteKey ? siteKey.split('\n') : []), [siteKey])
    const dateRange = {
        start: params.get('from') || format(subMonths(new Date(), 11), 'yyyy-MM-01'), // Default last 12 months
        end: params.get('to') || format(endOfMonth(new Date()), 'yyyy-MM-dd'),
    }
    const setFilters = ({ range = dateRange, sites: picked = selectedSites }) => {
        const next = new URLSearchParams()
        next.set('from', range.start || '')
        next.set('to', range.end || '')
        for (const s of picked) next.append('site', s)
        setParams(next, { replace: true })
    }
    const setDateRange = range => setFilters({ range })
    const setSelectedSites = picked => setFilters({ sites: picked })

    // The address a count opens: the same period and sites, and the bucket clicked.
    const selection = { from: dateRange.start, to: dateRange.end, sites: selectedSites }
    const ticketsHref = where => analyticsHref('tickets', selection, where)
    const issuesHref = where => analyticsHref('issues', selection, where)

    // One call for the whole selection: the counts come back pooled and every rate below
    // is computed from pooled counts. Never fetch per site and average the percentages
    // (MAIN-86). Which bucket a ticket or issue counts in is decided in the database
    // (analytics_ticket_rows / analytics_issue_rows, MAIN-171) — this page only lays the
    // counts out.
    const { data: stats = null } = useQuery({
        queryKey: ['analytics', dateRange.start, dateRange.end, selectedSites],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_maintenance_stats', {
                p_filters: { from: dateRange.start, to: dateRange.end, sites: selectedSites }
            })
            if (error) throw error
            return data
        },
        // Currently Overdue is live (it ignores the period but follows the sites), counted
        // by the database with the same rule its list uses (MAIN-152).
        refetchInterval: 5 * 60 * 1000
    })
    const overdueCount = Number(stats?.overdue) || 0

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
                            parts={report ? judgedParts(report.completion.all, report.completion.total, {
                                Adhered: 'Adhered', Violated: 'Violated', Pending: 'Pending', NA: 'Not applicable',
                            }, key => ticketsHref({ completion: key })) : null}
                            totalHref={ticketsHref({})}
                            icon={<CheckCircleIcon className="w-5 h-5" />}
                        />
                        <SLAKPICard
                            title="Acceptance SLA Compliance"
                            subtitle={`${dateRange.start} – ${dateRange.end}`}
                            rate={report?.acceptance.percent}
                            parts={report ? judgedParts({
                                Adhered: report.acceptance.adhered, Violated: report.acceptance.violated,
                                NA: report.acceptance.na, Pending: report.acceptance.pending,
                            }, report.acceptance.total, {
                                Adhered: 'On time', Violated: 'Late', NA: 'Not applicable', Pending: 'Awaiting issue',
                            }, key => ticketsHref({ acceptance: key })) : null}
                            totalHref={ticketsHref({})}
                            icon={<ClockIcon className="w-5 h-5" />}
                        />
                        <SLAKPICard
                            title="Currently Overdue"
                            subtitle="Live — open tickets past deadline"
                            count={overdueCount}
                            countHref={analyticsHref('tickets', { sites: selectedSites }, { overdue: 'true' })}
                            icon={<ExclamationTriangleIcon className="w-5 h-5" />}
                        />
                    </div>
                </div>

                {/* Every table's rows add up to its total (MAIN-171). */}
                {report && (
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">

                        <VerticalTable title="Tickets by Status">
                            <Row label="Total" value={report.status.total} bold href={ticketsHref({})} />
                            {report.status.rows.map(r => (
                                <Row key={r.key} label={r.label} value={r.value} color={STATUS_COLORS[r.key]} href={ticketsHref({ status: r.key })} />
                            ))}
                        </VerticalTable>

                        <VerticalTable title="Issues by Job Card Type">
                            {report.jobCardType.rows.map(r => (
                                <Row key={r.key} label={r.label} value={r.value} color={r.key === 'none' ? 'text-gray-500' : undefined} href={issuesHref({ job_card_type: r.key })} />
                            ))}
                            <Row label="Total" value={report.jobCardType.total} bold href={issuesHref({})} />
                        </VerticalTable>

                        {report.severities.map(s => (
                            <VerticalTable key={s.severity} title={`Issues by Severity (${s.severity})`}>
                                <Row label={`${s.severity} Total`} value={s.total} bold href={issuesHref({ severity: s.severity })} />
                                {s.rows.map(r => <Row key={r.key} label={r.label} value={r.value} href={issuesHref({ severity: s.severity, category: r.key })} />)}
                            </VerticalTable>
                        ))}

                        <div className="lg:col-span-2">
                            <CompletionTable completion={report.completion} href={ticketsHref} />
                        </div>

                        <VerticalTable title="Ratings & Feedback">
                            <Row label="Rating Pending" value={report.ratings.pending} color="text-gray-500" href={issuesHref({ rating_pending: 'true' })} />
                            <Row label="Ratings Collected" value={report.ratings.collected} href={issuesHref({ rated: 'true' })} />
                            <Row label="Collection % (Sharan KPI)" value={percentText(report.ratings.collectionPercent)} bold />
                            <Row label="Good" value={report.ratings.good} color="text-green-600" href={issuesHref({ rating: 'Good' })} />
                            <Row label="Ok" value={report.ratings.ok} color="text-yellow-600" href={issuesHref({ rating: 'Ok' })} />
                            <Row label="Bad" value={report.ratings.bad} color="text-red-600" href={issuesHref({ rating: 'Bad' })} />
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
function CompletionTable({ completion, href }) {
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
                                    <td key={c.key} className={`${td} ${RESULT_COLORS[r.key] || 'text-gray-900'}`}>
                                        <DrillLink value={r.values[c.key]} href={href({ completion: r.key, job_card_type: c.key })} />
                                    </td>
                                ))}
                                <td className={`${td} ${RESULT_COLORS[r.key] || 'text-gray-900'}`}>
                                    <DrillLink value={r.all} href={href({ completion: r.key })} />
                                </td>
                            </tr>
                        ))}
                        <tr className="bg-gray-50">
                            <td className="px-4 py-3 text-sm text-gray-900 font-bold">Total</td>
                            {cols.map(c => (
                                <td key={c.key} className={`${td} font-bold text-gray-900`}>
                                    <DrillLink value={completion.totals[c.key]} href={href({ job_card_type: c.key })} />
                                </td>
                            ))}
                            <td className={`${td} font-bold text-gray-900`}><DrillLink value={completion.total} href={href({})} /></td>
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

/**
 * A count that opens its list in a new tab (MAIN-152). Zero, or no address (a percentage),
 * stays plain text.
 */
function DrillLink({ value, href, className = '' }) {
    if (!href || !(Number(value) > 0)) return <span className={className}>{value}</span>
    return (
        <Link
            to={href}
            target="_blank"
            rel="noopener noreferrer"
            title="Open these records in a new tab"
            aria-label={`${value} — open these records in a new tab`}
            className={`underline decoration-dotted underline-offset-4 decoration-current/40 hover:decoration-solid focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 rounded-sm ${className}`}
        >
            {value}
        </Link>
    )
}

function Row({ label, value, color = "text-gray-900", bold = false, href }) {
    return (
        <div className="flex justify-between items-center px-4 py-3 hover:bg-gray-50">
            <span className="text-sm text-gray-600 font-medium">{label}</span>
            <DrillLink value={value} href={href} className={`text-sm ${color} ${bold ? 'font-bold' : ''}`} />
        </div>
    )
}

/**
 * An SLA card's parts, each its own count: the judged ones (Adhered / Violated) with their
 * share of the judged total — the card's percentage — and the rest as counts only.
 */
function judgedParts(counts, total, labels, hrefFor) {
    const n = k => Number(counts?.[k]) || 0
    const judged = n('Adhered') + n('Violated')
    const keys = ['Adhered', 'Violated', 'Pending', 'NA']
    // Any other verdict the database returns still shows, so the parts add up to the total.
    const extra = Object.keys(counts || {}).filter(k => !keys.includes(k))
    return {
        total,
        items: [...keys, ...extra]
            .filter(k => k === 'Adhered' || k === 'Violated' || n(k) > 0)
            .map(k => ({
                key: k,
                label: labels[k] || k,
                value: n(k),
                percent: k === 'Adhered' || k === 'Violated' ? percent(n(k), judged) : null,
                href: hrefFor(k),
            })),
    }
}

function SLAKPICard({ title, subtitle, rate, parts, totalHref, count, countHref, icon }) {
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
                <DrillLink value={count} href={countHref} className={`text-4xl font-bold ${countColor}`} />
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
                {parts && (
                    <p className="text-xs text-gray-600 leading-relaxed">
                        {parts.items.map((p, i) => (
                            <span key={p.key}>
                                {i > 0 && <span className="text-gray-400"> · </span>}
                                {p.label} <DrillLink value={p.value} href={p.href} className="font-semibold text-gray-800" />
                                {p.percent !== null && <span className="text-gray-500"> ({percentText(p.percent)})</span>}
                            </span>
                        ))}
                        <span className="text-gray-400"> · </span>
                        of <DrillLink value={parts.total} href={totalHref} className="font-semibold text-gray-800" /> tickets
                    </p>
                )}
                <p className="text-xs text-gray-400">{subtitle}</p>
            </div>
        </div>
    )
}

