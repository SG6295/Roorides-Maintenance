import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { format, startOfMonth, endOfMonth } from 'date-fns'
import { formatAs } from '../utils/datetime'
import { canSeeCosts, jobCardValueLabel, jobCardValueBasis } from '../utils/jobCardValue'
import { useAuth } from '../hooks/useAuth'
import { useAllSites } from '../hooks/useSites'
import { useListState, useServerList } from '../hooks/useServerList'
import { formatSiteLabel } from '../utils/siteLabel'
import Navigation from '../components/shared/Navigation'
import DateRangeFilter from '../components/tickets/DateRangeFilter'
import DataTable, { ActiveFilters, ColumnsButton, ListSearch } from '../components/shared/table/DataTable'

const RPC = 'get_job_card_list'
const KEY = 'job_cards'

const TYPE_LABELS = { InHouse: 'In House', Outsource: 'Outsource' }
const STATUS_LABELS = { 'Completed - Invoice Pending': 'Invoice Pending' }

export default function JobCards() {
    const navigate = useNavigate()
    const { userProfile } = useAuth()
    const canCreateBatch = ['maintenance_exec', 'super_admin'].includes(userProfile?.role)
    // MAIN-158: the job card's value, for the people who see the money.
    const showValue = canSeeCosts(userProfile?.role)
    const { data: sites = [] } = useAllSites()
    const siteByName = useMemo(() => Object.fromEntries(sites.map(s => [s.name, s])), [sites])

    const defaults = useMemo(() => ({
        sort: 'created_at',
        dir: 'desc',
        from: format(startOfMonth(new Date()), 'yyyy-MM-dd'),
        to: format(endOfMonth(new Date()), 'yyyy-MM-dd'),
    }), [])
    const list = { ...useListState(defaults), rpc: RPC, keyBase: KEY }
    const { data, isLoading, isPlaceholderData } = useServerList(RPC, KEY, list.state)
    const rows = data?.rows || []
    const total = data?.total ?? 0

    const columns = useMemo(() => [
        {
            key: 'job_card_number', label: 'Job Card', sortKey: 'job_card_number', filter: 'number',
            render: r => <span className="text-blue-600 font-medium hover:underline">#{r.job_card_number}</span>,
        },
        {
            key: 'created', label: 'Created', sortKey: 'created_at', filter: 'date', filterKey: 'raised_on',
            formatValue: v => formatAs(v, 'd MMM yyyy'),
            render: r => <span className="text-gray-600">{formatAs(r.created_at, 'd MMM yyyy')}</span>,
        },
        {
            key: 'vehicle_number', label: 'Vehicle', sortKey: 'vehicle_number', filter: 'values',
            render: r => <span className="text-gray-900 font-medium">{r.vehicle_number}</span>,
        },
        {
            key: 'site', label: 'Site', sortKey: 'site', filter: 'values',
            formatValue: v => (siteByName[v] ? formatSiteLabel(siteByName[v]) : v),
            render: r => <span className="bg-gray-100 px-2 py-0.5 rounded text-xs text-gray-700">{r.site}</span>,
        },
        {
            key: 'type', label: 'Type', sortKey: 'type', filter: 'values',
            formatValue: v => TYPE_LABELS[v] || v,
            render: r => r.type === 'InHouse'
                ? <span className="bg-purple-100 text-purple-800 px-2 py-0.5 rounded text-xs font-medium">In House</span>
                : <span className="bg-orange-100 text-orange-800 px-2 py-0.5 rounded text-xs font-medium">Outsource</span>,
        },
        {
            key: 'assignee', label: 'Assignee', sortKey: 'assignee', filter: 'values',
            cellClassName: 'max-w-[220px] truncate text-gray-600',
            render: r => <span title={r.assignee}>{r.assignee || (r.type === 'InHouse' ? 'No labour yet' : '—')}</span>,
        },
        {
            key: 'workshop', label: 'Workshop', sortKey: 'workshop', filter: 'values',
            render: r => <span className="text-gray-700">{r.workshop || '—'}</span>,
        },
        {
            key: 'status', label: 'Status', sortKey: 'status', filter: 'values',
            formatValue: v => STATUS_LABELS[v] || v,
            render: r => (
                <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${
                    r.status === 'Completed' ? 'bg-green-100 text-green-800'
                        : r.status === 'Completed - Invoice Pending' ? 'bg-amber-100 text-amber-800'
                            : 'bg-blue-100 text-blue-800'}`}
                >
                    {STATUS_LABELS[r.status] || r.status}
                </span>
            ),
        },
        {
            key: 'open_issues', label: 'Open Issues', sortKey: 'open_issues', filter: 'number',
            render: r => r.open_issues > 0
                ? <span className="text-red-600 font-medium">{r.open_issues} Open</span>
                : <span className="text-green-600">All Done</span>,
        },
        ...(showValue ? [{
            key: 'value', label: 'Value', sortKey: 'value', filter: 'number', align: 'right',
            formatValue: v => `₹${Number(v).toLocaleString('en-IN')}`,
            render: r => {
                const v = jobCardValueLabel(r)
                return (
                    <span className={v.muted ? 'text-gray-500 italic' : 'text-gray-900 tabular-nums'} title={jobCardValueBasis(r)}>
                        {v.text}
                    </span>
                )
            },
        }] : []),
    ], [siteByName, showValue])

    const defaultKeys = useMemo(() => columns.map(c => c.key), [columns])
    const [visibleKeys, setVisibleKeys] = useState(null)
    const shown = columns.filter(c => (visibleKeys ?? defaultKeys).includes(c.key))

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Job Cards' }]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8 space-y-4">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                    <div>
                        <h1 className="text-2xl font-bold text-gray-900">Job Cards</h1>
                        <p className="text-sm text-gray-600 mt-1">
                            {isLoading ? 'Loading…' : `${total.toLocaleString('en-IN')} job card${total !== 1 ? 's' : ''} found`}
                        </p>
                    </div>
                    {/* One invoice for work on many vehicles, without a job card each (MAIN-99). */}
                    {canCreateBatch && (
                        <Link
                            to="/multi-vehicle-invoices/new"
                            className="text-sm px-3 py-2 text-white bg-blue-600 rounded-lg hover:bg-blue-700 whitespace-nowrap self-start sm:self-auto"
                        >
                            + Multi-vehicle invoice
                        </Link>
                    )}
                </div>

                <div className="flex flex-wrap gap-2 items-center">
                    <DateRangeFilter dateRange={{ start: list.state.from, end: list.state.to }} onDateRangeChange={list.setDateRange} />
                    <ListSearch list={list} placeholder="Search job card, vehicle, site, assignee…" />
                    <div className="sm:ml-auto">
                        <ColumnsButton columns={columns} visibleKeys={visibleKeys ?? defaultKeys} onChange={setVisibleKeys} defaultKeys={defaultKeys} />
                    </div>
                </div>

                <ActiveFilters list={list} columns={columns} defaults={defaults} />

                <DataTable
                    list={list}
                    columns={shown}
                    rows={rows}
                    total={total}
                    loading={isLoading}
                    stale={isPlaceholderData}
                    onRowClick={r => navigate(`/job-cards/${r.job_card_number}`)}
                    emptyText="No job cards match these filters."
                />
            </div>
        </div>
    )
}
