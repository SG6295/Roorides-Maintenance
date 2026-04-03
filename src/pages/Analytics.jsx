import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { format, subMonths, endOfMonth } from 'date-fns'
import Navigation from '../components/shared/Navigation'
import { useSites } from '../hooks/useTickets'
import DateRangeFilter from '../components/tickets/DateRangeFilter'
import { ArrowDownTrayIcon } from '@heroicons/react/24/outline'

export default function Analytics() {
    const { data: sites = [] } = useSites()
    const [selectedSite, setSelectedSite] = useState('')
    const [dateRange, setDateRange] = useState({
        start: format(subMonths(new Date(), 11), 'yyyy-MM-01'), // Default last 12 months
        end: format(endOfMonth(new Date()), 'yyyy-MM-dd')
    })

    // Fetch Stats using RPC
    const { data: stats = [], isLoading } = useQuery({
        queryKey: ['analytics', dateRange, selectedSite],
        queryFn: async () => {
            const { data, error } = await supabase
                .rpc('get_maintenance_stats', {
                    start_date_input: dateRange.start,
                    end_date_input: dateRange.end,
                    site_filter: selectedSite || null
                })

            if (error) throw error
            return data
        }
    })

    // Aggregates for KPI Cards & Tables
    const aggregates = useMemo(() => {
        if (!stats.length) return null

        const sums = stats.reduce((acc, curr) => ({
            total_tickets: acc.total_tickets + curr.total_tickets,
            status_pending: acc.status_pending + curr.status_pending,
            status_assigned: acc.status_assigned + curr.status_assigned,
            status_completed: acc.status_completed + curr.status_completed,
            status_rejected: acc.status_rejected + curr.status_rejected,

            major_total: acc.major_total + curr.major_total,
            major_electrical: acc.major_electrical + curr.major_electrical,
            major_mechanical: acc.major_mechanical + curr.major_mechanical,
            major_body: acc.major_body + curr.major_body,
            major_tyre: acc.major_tyre + curr.major_tyre,

            minor_total: acc.minor_total + curr.minor_total,
            minor_electrical: acc.minor_electrical + curr.minor_electrical,
            minor_mechanical: acc.minor_mechanical + curr.minor_mechanical,
            minor_body: acc.minor_body + curr.minor_body,
            minor_tyre: acc.minor_tyre + curr.minor_tyre,

            type_in_house: acc.type_in_house + curr.type_in_house,
            type_outsource: acc.type_outsource + curr.type_outsource,

            assign_unassigned_within: acc.assign_unassigned_within + curr.assign_unassigned_within,
            assign_adhered: acc.assign_adhered + curr.assign_adhered,
            assign_violated: acc.assign_violated + curr.assign_violated,

            comp_in_wip_within: acc.comp_in_wip_within + curr.comp_in_wip_within,
            comp_in_adhered: acc.comp_in_adhered + curr.comp_in_adhered,
            comp_in_violated: acc.comp_in_violated + curr.comp_in_violated,

            comp_out_wip_within: acc.comp_out_wip_within + curr.comp_out_wip_within,
            comp_out_adhered: acc.comp_out_adhered + curr.comp_out_adhered,
            comp_out_violated: acc.comp_out_violated + curr.comp_out_violated,

            rating_pending: acc.rating_pending + curr.rating_pending,
            rating_collected: acc.rating_collected + curr.rating_collected,
            rating_good: acc.rating_good + curr.rating_good,
            rating_ok: acc.rating_ok + curr.rating_ok,
            rating_bad: acc.rating_bad + curr.rating_bad,

            csat_score_sum: acc.csat_score_sum + curr.csat_score_sum,
            total_completed_tickets: acc.total_completed_tickets + curr.total_completed_tickets
        }), {
            total_tickets: 0, status_pending: 0, status_assigned: 0, status_completed: 0, status_rejected: 0,
            major_total: 0, major_electrical: 0, major_mechanical: 0, major_body: 0, major_tyre: 0,
            minor_total: 0, minor_electrical: 0, minor_mechanical: 0, minor_body: 0, minor_tyre: 0,
            type_in_house: 0, type_outsource: 0,
            assign_unassigned_within: 0, assign_adhered: 0, assign_violated: 0,
            comp_in_wip_within: 0, comp_in_adhered: 0, comp_in_violated: 0,
            comp_out_wip_within: 0, comp_out_adhered: 0, comp_out_violated: 0,
            rating_pending: 0, rating_collected: 0, rating_good: 0, rating_ok: 0, rating_bad: 0,
            csat_score_sum: 0, total_completed_tickets: 0
        })

        // Helper for % calc
        const calcPerc = (num, den) => den > 0 ? Math.round((num / den) * 100) + '%' : '-'

        return {
            ...sums,
            assign_sla_perc: calcPerc(sums.assign_adhered, sums.assign_adhered + sums.assign_violated),
            comp_in_sla_perc: calcPerc(sums.comp_in_adhered, sums.comp_in_adhered + sums.comp_in_violated),
            comp_out_sla_perc: calcPerc(sums.comp_out_adhered, sums.comp_out_adhered + sums.comp_out_violated),
            collection_perc: calcPerc(sums.rating_collected, sums.rating_pending + sums.rating_collected),
            csat_perc: calcPerc(sums.csat_score_sum, sums.rating_collected * 2)
        }
    }, [stats])

    const downloadCSV = () => {
        if (!stats.length) return

        // Headers matching ticket_metrics.md sections
        const headers = [
            'Month',
            // 1. By Status
            'Total Tickets', 'Pending', 'Team Assigned', 'Completed', 'Rejected',
            // 2. By Work Type (Major)
            'Major (Total)', 'Major (Elec)', 'Major (Mech)', 'Major (Body)', 'Major (Tyre)',
            // 3. By Work Type (Minor)
            'Minor (Total)', 'Minor (Elec)', 'Minor (Mech)', 'Minor (Body)', 'Minor (Tyre)',
            // 4. In House / Outsource
            'In House', 'Outsource',
            // 5. Assignment SLA
            'Assign (Unassigned/Within)', 'Assign (Adhered)', 'Assign (Violated)', 'Assignment SLA % (Sharan KPI)',
            // 6. Completion SLA (In House)
            'Comp In (WIP Within)', 'Comp In (Adhered)', 'Comp In (Violated)', 'Comp In SLA % (Sharan KPI)',
            // 7. Completion SLA (Outsourced)
            'Comp Out (WIP Within)', 'Comp Out (Adhered)', 'Comp Out (Violated)', 'Comp Out SLA % (Manjunath KPI)',
            // 8. Ratings
            'Rating Pending', 'Ratings Collected', 'Collection % (Sharan KPI)',
            'Good', 'Ok', 'Bad', 'CSAT % (Manjunath KPI)'
        ]

        const csvRows = [headers.join(',')]

        stats.forEach(row => {
            // Helper for % calc
            const calcPerc = (num, den) => den > 0 ? ((num / den) * 100).toFixed(1) + '%' : '-'

            // Assignment SLA %
            const assignTotal = row.assign_adhered + row.assign_violated
            const assignSLA = calcPerc(row.assign_adhered, assignTotal)

            // Completion In-House SLA %
            const compInTotal = row.comp_in_adhered + row.comp_in_violated
            const compInSLA = calcPerc(row.comp_in_adhered, compInTotal)

            // Completion Outsource SLA %
            const compOutTotal = row.comp_out_adhered + row.comp_out_violated
            const compOutSLA = calcPerc(row.comp_out_adhered, compOutTotal)

            // Collection %
            const collectionPerc = calcPerc(row.rating_collected, (row.rating_pending + row.rating_collected))

            // CSAT % (Formula: Score Sum / (Ratings Collected * 2))
            const csatDenom = row.rating_collected * 2
            const csatPerc = calcPerc(row.csat_score_sum, csatDenom)

            csvRows.push([
                row.month_label,
                // Status
                row.total_tickets, row.status_pending, row.status_assigned, row.status_completed, row.status_rejected,
                // Major
                row.major_total, row.major_electrical, row.major_mechanical, row.major_body, row.major_tyre,
                // Minor
                row.minor_total, row.minor_electrical, row.minor_mechanical, row.minor_body, row.minor_tyre,
                // Type
                row.type_in_house, row.type_outsource,
                // Assign SLA
                row.assign_unassigned_within, row.assign_adhered, row.assign_violated, assignSLA,
                // Comp In SLA
                row.comp_in_wip_within, row.comp_in_adhered, row.comp_in_violated, compInSLA,
                // Comp Out SLA
                row.comp_out_wip_within, row.comp_out_adhered, row.comp_out_violated, compOutSLA,
                // Ratings
                row.rating_pending, row.rating_collected, collectionPerc,
                row.rating_good, row.rating_ok, row.rating_bad, csatPerc
            ].join(','))
        })

        const blob = new Blob([csvRows.join('\n')], { type: 'text/csv' })
        const url = window.URL.createObjectURL(blob)
        const a = document.createElement('a')
        a.href = url
        a.download = `detailed_maintenance_stats_${format(new Date(), 'yyyyMMdd')}.csv`
        a.click()
    }

    return (
        <div className="min-h-screen bg-gray-50 pb-12">
            <Navigation breadcrumbs={[{ label: 'Analytics' }]} />

            {/* Header & Filters */}
            <div className="bg-white border-b sticky top-0 z-10">
                <div className="max-w-7xl mx-auto px-4 sm:px-6 py-4">
                    <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                        <h1 className="text-2xl font-bold text-gray-900 mb-4 sm:mb-0">Dashboard</h1>

                        <div className="flex flex-wrap items-center gap-3 w-full sm:w-auto">
                            {/* Date Filter */}
                            <DateRangeFilter dateRange={dateRange} onDateRangeChange={setDateRange} />

                            {/* Site Filter */}
                            <select
                                value={selectedSite}
                                onChange={(e) => setSelectedSite(e.target.value)}
                                className="block w-full sm:w-40 pl-3 pr-10 py-2.5 text-sm border-gray-300 focus:outline-none focus:ring-blue-500 focus:border-blue-500 rounded-lg"
                            >
                                <option value="">All Sites</option>
                                {sites.map(site => (
                                    <option key={site.id} value={site.name}>{site.name}</option>
                                ))}
                            </select>

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

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8 space-y-10">
                {/* KPI Cards (Aggregated) */}
                {aggregates && (
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
                        <KPICard title="Total Tickets" value={aggregates.total_tickets} color="bg-blue-600" />
                        <KPICard title="Completed" value={aggregates.status_completed} color="bg-green-600" />
                        <KPICard title="Pending" value={aggregates.status_pending} color="bg-yellow-500" />
                        <KPICard
                            title="Feedback Collected"
                            value={aggregates.rating_collected}
                            color="bg-purple-600"
                        />
                    </div>
                )}

                {/* --- TRANSPOSED VERTICAL TABLES SECTION --- */}
                {aggregates && (
                    <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">

                        {/* 1. Status */}
                        <VerticalTable title="Tickets by Status">
                            <Row label="Total" value={aggregates.total_tickets} bold />
                            <Row label="Pending" value={aggregates.status_pending} color="text-yellow-600" />
                            <Row label="Team Assigned" value={aggregates.status_assigned} color="text-blue-600" />
                            <Row label="Completed" value={aggregates.status_completed} color="text-green-600" />
                            <Row label="Rejected" value={aggregates.status_rejected} color="text-red-600" />
                        </VerticalTable>

                        {/* 4. In House / Outsource */}
                        <VerticalTable title="Tickets by Source">
                            <Row label="In House" value={aggregates.type_in_house} />
                            <Row label="Outsource" value={aggregates.type_outsource} />
                        </VerticalTable>

                        {/* 2. Major */}
                        <VerticalTable title="Tickets by Work Type (Major)">
                            <Row label="Major Total" value={aggregates.major_total} bold />
                            <Row label="Electrical" value={aggregates.major_electrical} />
                            <Row label="Mechanical" value={aggregates.major_mechanical} />
                            <Row label="Body" value={aggregates.major_body} />
                            <Row label="Tyre" value={aggregates.major_tyre} />
                        </VerticalTable>

                        {/* 3. Minor */}
                        <VerticalTable title="Tickets by Work Type (Minor)">
                            <Row label="Minor Total" value={aggregates.minor_total} bold />
                            <Row label="Electrical" value={aggregates.minor_electrical} />
                            <Row label="Mechanical" value={aggregates.minor_mechanical} />
                            <Row label="Body" value={aggregates.minor_body} />
                            <Row label="Tyre" value={aggregates.minor_tyre} />
                        </VerticalTable>

                        {/* 5. Assignment SLA */}
                        <VerticalTable title="Assignment SLA">
                            <Row label="Unassigned / Within SLA" value={aggregates.assign_unassigned_within} />
                            <Row label="Adhered" value={aggregates.assign_adhered} color="text-green-600" />
                            <Row label="Violated" value={aggregates.assign_violated} color="text-red-600" />
                            <Row label="SLA % (Sharan KPI)" value={aggregates.assign_sla_perc} bold />
                        </VerticalTable>

                        {/* 6. Completion SLA (In House) */}
                        <VerticalTable title="Completion SLA (In House)">
                            <Row label="Work In Progress (Within)" value={aggregates.comp_in_wip_within} />
                            <Row label="Adhered" value={aggregates.comp_in_adhered} color="text-green-600" />
                            <Row label="Violated" value={aggregates.comp_in_violated} color="text-red-600" />
                            <Row label="SLA % (Sharan KPI)" value={aggregates.comp_in_sla_perc} bold />
                        </VerticalTable>

                        {/* 7. Completion SLA (Outsourced) */}
                        <VerticalTable title="Completion SLA (Outsourced)">
                            <Row label="Work In Progress (Within)" value={aggregates.comp_out_wip_within} />
                            <Row label="Adhered" value={aggregates.comp_out_adhered} color="text-green-600" />
                            <Row label="Violated" value={aggregates.comp_out_violated} color="text-red-600" />
                            <Row label="SLA % (Manjunath KPI)" value={aggregates.comp_out_sla_perc} bold />
                        </VerticalTable>

                        {/* 8. Ratings */}
                        <VerticalTable title="Ratings & Feedback">
                            <Row label="Rating Pending" value={aggregates.rating_pending} color="text-gray-500" />
                            <Row label="Ratings Collected" value={aggregates.rating_collected} />
                            <Row label="Collection % (Sharan KPI)" value={aggregates.collection_perc} bold />
                            <Row label="Good" value={aggregates.rating_good} color="text-green-600" />
                            <Row label="Ok" value={aggregates.rating_ok} color="text-yellow-600" />
                            <Row label="Bad" value={aggregates.rating_bad} color="text-red-600" />
                            <Row label="CSAT % (Manjunath KPI)" value={aggregates.csat_perc} bold />
                        </VerticalTable>

                    </div>
                )}
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

function KPICard({ title, value, color }) {
    return (
        <div className="bg-white overflow-hidden rounded-lg shadow">
            <div className="p-5">
                <div className="flex items-center">
                    <div className="flex-shrink-0">
                        <div className={`rounded-md p-3 ${color} bg-opacity-10`}>
                            {/* Icon placeholder */}
                            <div className={`h-6 w-6 ${color.replace('bg-', 'text-')}`} />
                        </div>
                    </div>
                    <div className="ml-5 w-0 flex-1">
                        <dl>
                            <dt className="text-sm font-medium text-gray-600 truncate">{title}</dt>
                            <dd className="text-lg font-medium text-gray-900">{value}</dd>
                        </dl>
                    </div>
                </div>
            </div>
        </div>
    )
}
