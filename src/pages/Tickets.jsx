import { useState, useMemo, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { format, startOfMonth, endOfMonth } from 'date-fns'
import { ArrowDownTrayIcon } from '@heroicons/react/24/outline'
import { useAuth } from '../hooks/useAuth'
import { useAllSites } from '../hooks/useSites'
import { useListState, useServerList, fetchAllListRows } from '../hooks/useServerList'
import { formatSiteLabel } from '../utils/siteLabel'
import { formatAs, toDate } from '../utils/datetime'
import { exportTicketsToExcel } from '../utils/ticketExport'
import { useToast } from '../hooks/useFeedback'
import Navigation from '../components/shared/Navigation'
import DateRangeFilter from '../components/tickets/DateRangeFilter'
import TicketCard, { SLABadge, StatusBadge } from '../components/tickets/TicketCard'
import StatusShortcuts from '../components/tickets/StatusShortcuts'
import DataTable, { ActiveFilters, ColumnsButton, ListSearch, Pagination } from '../components/shared/table/DataTable'
import ColumnMenu from '../components/shared/table/ColumnMenu'

const RPC = 'get_ticket_list'
const KEY = 'tickets'

// The ticket's own SLA badge — the same component the cards use (MAIN-45, MAIN-134).
function TicketSla({ row, now }) {
    const acceptanceDeadline = row.status === 'New' ? toDate(row.acceptance_sla_end_date) : null
    return <SLABadge ticket={row} currentDate={now} acceptanceDeadline={acceptanceDeadline} />
}

/** A minute clock, aligned to the minute, for the SLA countdowns. */
function useMinuteClock() {
    const [now, setNow] = useState(new Date())
    useEffect(() => {
        let interval
        const timeout = setTimeout(() => {
            setNow(new Date())
            interval = setInterval(() => setNow(new Date()), 60000)
        }, 60000 - (Date.now() % 60000))
        return () => { clearTimeout(timeout); if (interval) clearInterval(interval) }
    }, [])
    return now
}

export default function Tickets() {
    const toast = useToast()
    const { userProfile } = useAuth()
    const canExport = ['maintenance_exec', 'super_admin'].includes(userProfile?.role)
    const [exporting, setExporting] = useState(false)
    const now = useMinuteClock()

    // All sites, not just active — a departed school's past tickets must stay filterable.
    const { data: sites = [] } = useAllSites()
    const siteByName = useMemo(() => Object.fromEntries(sites.map(s => [s.name, s])), [sites])

    // The current month, unless the address says otherwise (MAIN-151).
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
            key: 'ticket_number', label: 'Ticket', sortKey: 'ticket_number', filter: 'number',
            render: r => <Link to={`/tickets/${r.ticket_number}`} className="text-blue-600 font-semibold hover:underline">#{r.ticket_number}</Link>,
        },
        {
            key: 'raised', label: 'Raised', sortKey: 'created_at', filter: 'date', filterKey: 'raised_on',
            formatValue: v => formatAs(v, 'd MMM yyyy'),
            render: r => <span className="text-gray-600">{formatAs(r.created_at, 'd MMM, h:mm a')}</span>,
        },
        {
            key: 'vehicle_number', label: 'Vehicle', sortKey: 'vehicle_number', filter: 'values',
            render: r => <span className="font-semibold text-gray-900">{r.vehicle_number}</span>,
        },
        {
            key: 'site', label: 'Site', sortKey: 'site', filter: 'values',
            formatValue: v => (siteByName[v] ? formatSiteLabel(siteByName[v]) : v),
            render: r => <span className="bg-gray-100 px-2 py-0.5 rounded text-xs text-gray-700">{r.site}</span>,
        },
        {
            key: 'status', label: 'Status', sortKey: 'status', filter: 'values',
            render: r => <StatusBadge status={r.status} />,
        },
        {
            key: 'remarks', label: 'Remarks', sortKey: 'remarks',
            cellClassName: 'max-w-xs truncate text-gray-600',
            render: r => <span title={r.remarks}>{r.remarks || '—'}</span>,
        },
        {
            key: 'supervisor_name', label: 'Supervisor', sortKey: 'supervisor_name', filter: 'values',
            render: r => <span className="text-gray-700">{r.supervisor_name}</span>,
        },
        {
            key: 'sla', label: 'SLA', sortKey: 'sla_due', filter: 'values', filterKey: 'sla_state',
            render: r => <TicketSla row={r} now={now} />,
        },
    ], [siteByName, now])

    const defaultKeys = useMemo(() => columns.map(c => c.key), [columns])
    const [visibleKeys, setVisibleKeys] = useState(null)
    const shown = columns.filter(c => (visibleKeys ?? defaultKeys).includes(c.key))

    // Exports every ticket the filters match, not only the page on screen (MAIN-84).
    const handleExport = async () => {
        setExporting(true)
        try {
            const all = await fetchAllListRows(RPC, list.state)
            await exportTicketsToExcel(all, { start: list.state.from || 'all', end: list.state.to || 'all' })
        } catch (err) {
            toast.error('Export failed: ' + err.message)
        } finally {
            setExporting(false)
        }
    }

    const dateRange = { start: list.state.from, end: list.state.to }

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Tickets' }]} />

            <div className="bg-white border-b">
                <div className="max-w-7xl mx-auto px-4 sm:px-6 py-4 flex justify-between items-center gap-3">
                    <div className="min-w-0">
                        <h1 className="text-2xl font-bold text-gray-900">Tickets</h1>
                        <p className="text-sm text-gray-600 mt-1">
                            {isLoading ? 'Loading…' : `${total.toLocaleString('en-IN')} ticket${total !== 1 ? 's' : ''} found`}
                        </p>
                    </div>
                    <div className="flex items-center gap-2">
                        {canExport && (
                            <button
                                onClick={handleExport}
                                disabled={exporting || isLoading || isPlaceholderData || total === 0}
                                className="hidden sm:flex items-center gap-2 px-4 py-2.5 border border-gray-300 rounded-lg bg-white text-gray-700 font-medium hover:bg-gray-50 disabled:opacity-40 min-h-[48px] whitespace-nowrap shadow-sm"
                            >
                                <ArrowDownTrayIcon className="w-5 h-5" />
                                {exporting ? 'Exporting…' : 'Export'}
                            </button>
                        )}
                        <Link
                            to="/tickets/new"
                            className="bg-blue-600 text-white px-5 py-2.5 rounded-lg font-medium hover:bg-blue-700 active:bg-blue-800 min-h-[48px] flex items-center whitespace-nowrap shadow-sm"
                        >
                            + New
                        </Link>
                    </div>
                </div>
            </div>

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-5 space-y-4">
                <div className="flex flex-wrap gap-2 items-center">
                    <DateRangeFilter dateRange={dateRange} onDateRangeChange={list.setDateRange} />
                    <ListSearch list={list} placeholder="Search ticket no., vehicle, remarks, supervisor…" />
                    <div className="hidden md:block md:ml-auto">
                        <ColumnsButton columns={columns} visibleKeys={visibleKeys ?? defaultKeys} onChange={setVisibleKeys} defaultKeys={defaultKeys} />
                    </div>
                    <div className="md:hidden w-full">
                        <MobileSortFilter columns={columns} list={list} />
                    </div>
                </div>

                <StatusShortcuts list={list} />

                <ActiveFilters list={list} columns={columns} defaults={defaults} />

                {/* Desktop: the table. */}
                <div className="hidden md:block">
                    <DataTable
                        list={list}
                        columns={shown}
                        rows={rows}
                        total={total}
                        loading={isLoading}
                        stale={isPlaceholderData}
                        emptyText="No tickets match these filters."
                    />
                </div>

                {/* Phone: the same rows as cards, with the same filters (MAIN-151 design). */}
                <div className="md:hidden space-y-3">
                    {isLoading && <div className="py-12 text-center text-gray-600">Loading tickets…</div>}
                    {!isLoading && rows.length === 0 && (
                        <div className="bg-white rounded-lg shadow p-10 text-center text-gray-600">No tickets match these filters.</div>
                    )}
                    <div className={`space-y-3 ${isPlaceholderData ? 'opacity-60' : ''}`}>
                        {rows.map(r => (
                            <TicketCard key={r.id} ticket={{ ...r, initial_remarks: r.remarks }} currentDate={now} />
                        ))}
                    </div>
                    <div className="bg-white rounded-lg border border-gray-200">
                        <Pagination page={list.state.page} pageSize={50} total={total} onPage={list.setPage} />
                    </div>
                </div>
            </div>
        </div>
    )
}

/** Phone: one "Sort & filter" button, listing every column's menu. */
function MobileSortFilter({ columns, list }) {
    const [open, setOpen] = useState(false)
    const active = Object.keys(list.state.filters).length
    return (
        <div>
            <button
                type="button"
                onClick={() => setOpen(o => !o)}
                aria-expanded={open}
                className={`w-full flex items-center justify-center gap-2 min-h-[44px] rounded-lg border text-sm font-semibold ${active ? 'border-blue-500 bg-blue-50 text-blue-800' : 'border-gray-300 bg-white text-gray-700'}`}
            >
                Sort &amp; filter{active ? ` · ${active}` : ''}
            </button>
            {open && (
                <div className="mt-2 p-2 bg-white rounded-lg border border-gray-200 space-y-2">
                    {columns.filter(c => c.sortKey || c.filter).map(c => (
                        <ColumnMenu key={c.key} column={c} list={list} onSort={list.setSort} onFilter={list.setFilter} trigger="row" />
                    ))}
                </div>
            )}
        </div>
    )
}
