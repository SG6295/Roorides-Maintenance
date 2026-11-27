import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { format, startOfMonth, endOfMonth } from 'date-fns'
import { formatAs } from '../utils/datetime'
import { useAuth } from '../hooks/useAuth'
import { useAllSites } from '../hooks/useSites'
import { useListState, useServerList } from '../hooks/useServerList'
import { formatSiteLabel } from '../utils/siteLabel'
import { SLA_STATUS_LABELS } from '../utils/slaStatus'
import Navigation from '../components/shared/Navigation'
import SLAStatusBadge from '../components/shared/SLAStatusBadge'
import DateRangeFilter from '../components/tickets/DateRangeFilter'
import DataTable, { ActiveFilters, ColumnsButton, ListSearch } from '../components/shared/table/DataTable'

const RPC = 'get_issue_list'
const KEY = 'issues'

// The job card's own type (MAIN-171); 'None' = the issue has no job card yet.
const JOB_CARD_TYPE_LABELS = { InHouse: 'In-house', Outsource: 'Outsource', None: 'No job card yet' }

export default function Issues() {
    const { userProfile } = useAuth()
    // Supervisors cannot read job cards, so those two columns would only ever be blank.
    const canSeeJobCards = userProfile?.role !== 'supervisor'
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
            key: 'issue_number', label: 'Issue', sortKey: 'issue_order',
            render: r => <span className="font-medium text-gray-900">{r.issue_number}</span>,
        },
        {
            key: 'raised', label: 'Raised', sortKey: 'created_at', filter: 'date', filterKey: 'raised_on',
            formatValue: v => formatAs(v, 'd MMM yyyy'),
            render: r => <span className="text-gray-600">{formatAs(r.created_at, 'd MMM, h:mm a')}</span>,
        },
        {
            key: 'vehicle_number', label: 'Vehicle', sortKey: 'vehicle_number', filter: 'values',
            render: r => <span className="font-medium text-gray-900">{r.vehicle_number}</span>,
        },
        {
            key: 'ticket_number', label: 'Ticket', sortKey: 'ticket_number', filter: 'number',
            render: r => r.ticket_number
                ? <Link to={`/tickets/${r.ticket_number}`} className="text-blue-600 hover:underline">#{r.ticket_number}</Link>
                : '—',
        },
        {
            key: 'site', label: 'Site', sortKey: 'site', filter: 'values',
            formatValue: v => (siteByName[v] ? formatSiteLabel(siteByName[v]) : v),
            render: r => <span className="bg-gray-100 px-2 py-0.5 rounded text-xs text-gray-700">{r.site}</span>,
        },
        {
            key: 'description', label: 'Description', sortKey: 'description',
            cellClassName: 'max-w-xs truncate text-gray-600',
            render: r => <span title={r.description}>{r.description}</span>,
        },
        {
            key: 'category', label: 'Category', sortKey: 'category', filter: 'values',
            render: r => <span className="text-gray-700">{r.category}</span>,
        },
        {
            key: 'severity', label: 'Severity', sortKey: 'severity', filter: 'values',
            render: r => (
                <span className={`px-2 py-0.5 rounded text-xs ${r.severity === 'Major' ? 'bg-orange-100 text-orange-800' : 'bg-gray-100 text-gray-700'}`}>
                    {r.severity}
                </span>
            ),
        },
        {
            key: 'status', label: 'Status', sortKey: 'status', filter: 'values',
            render: r => (
                <span className={`px-2 py-0.5 rounded-full text-xs ${r.status === 'Done' ? 'bg-green-100 text-green-800' : 'bg-blue-100 text-blue-800'}`}>
                    {r.status}
                </span>
            ),
        },
        {
            key: 'sla_status', label: 'SLA', sortKey: 'sla_status', filter: 'values',
            formatValue: v => SLA_STATUS_LABELS[v] || v,
            render: r => <SLAStatusBadge status={r.sla_status} deadline={r.sla_end_date} />,
        },
        {
            key: 'sla_end_date', label: 'SLA Due', sortKey: 'sla_end_date', hiddenByDefault: true,
            render: r => <span className="text-gray-600">{r.sla_end_date ? formatAs(r.sla_end_date, 'd MMM') : '—'}</span>,
        },
        ...(canSeeJobCards ? [
            {
                key: 'job_card_number', label: 'Job Card', sortKey: 'job_card_number',
                render: r => r.job_card_number
                    ? <Link to={`/job-cards/${r.job_card_number}`} className="text-blue-600 hover:underline">#{r.job_card_number}</Link>
                    : '—',
            },
            {
                key: 'job_card_type', label: 'Job card type', sortKey: 'job_card_type', filter: 'values', hiddenByDefault: true,
                formatValue: v => JOB_CARD_TYPE_LABELS[v] || v,
                render: r => <span className="text-gray-700">{JOB_CARD_TYPE_LABELS[r.job_card_type] || '—'}</span>,
            },
        ] : []),
    ], [siteByName, canSeeJobCards])

    // SLA Due (also in the SLA badge's tooltip) and Job card type start hidden, so the table
    // fits a laptop screen; Columns brings them back.
    const defaultKeys = useMemo(() => columns.filter(c => !c.hiddenByDefault).map(c => c.key), [columns])
    const [visibleKeys, setVisibleKeys] = useState(null)
    const shown = columns.filter(c => (visibleKeys ?? defaultKeys).includes(c.key))

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Issues' }]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8 space-y-4">
                <div>
                    <h1 className="text-2xl font-bold text-gray-900">Issues Registry</h1>
                    <p className="text-sm text-gray-600 mt-1">
                        {isLoading ? 'Loading…' : `${total.toLocaleString('en-IN')} issue${total !== 1 ? 's' : ''} found`}
                    </p>
                </div>

                <div className="flex flex-wrap gap-2 items-center">
                    <DateRangeFilter dateRange={{ start: list.state.from, end: list.state.to }} onDateRangeChange={list.setDateRange} />
                    <ListSearch list={list} placeholder="Search issue, description, vehicle, ticket, site…" />
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
                    emptyText="No issues match these filters."
                />
            </div>
        </div>
    )
}
