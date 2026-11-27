import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { format, startOfMonth, endOfMonth } from 'date-fns'
import * as XLSX from 'xlsx'
import { ArrowDownTrayIcon } from '@heroicons/react/24/outline'
import { formatAs } from '../utils/datetime'
import { useAllSites } from '../hooks/useSites'
import { useListState, useServerList, fetchAllListRows } from '../hooks/useServerList'
import { useToast } from '../hooks/useFeedback'
import { formatSiteLabel } from '../utils/siteLabel'
import { formatHours } from '../utils/labour'
import { mechanicPath } from '../utils/employeeId'
import {
    TRADE_LABELS, peopleLabel, peopleValueLabel, itemShades,
    PEOPLE_SHORTCUTS, activeShortcut, buildLabourExportRows,
} from '../utils/labourList'
import Navigation from '../components/shared/Navigation'
import DateRangeFilter from '../components/tickets/DateRangeFilter'
import DataTable, { ActiveFilters, AnalyticsOrigin, ColumnsButton, ListSearch } from '../components/shared/table/DataTable'

const RPC = 'get_labour_list'
const KEY = 'labour_list'
const PEOPLE_KEY = 'people_on_item'

/**
 * Labour (MAIN-176): every labour entry, one row per person per work item, plus one
 * "Unattributed" row for a work item's old hours with nobody attached. The same rows
 * Analytics › Labour utilisation adds up, so a figure clicked there opens here with
 * exactly the hours it counted.
 */
export default function Labour() {
    const toast = useToast()
    const { data: sites = [] } = useAllSites()
    const siteByName = useMemo(() => Object.fromEntries(sites.map(s => [s.name, s])), [sites])

    const defaults = useMemo(() => ({
        sort: 'completed_on',
        dir: 'desc',
        from: format(startOfMonth(new Date()), 'yyyy-MM-dd'),
        to: format(endOfMonth(new Date()), 'yyyy-MM-dd'),
    }), [])
    const list = { ...useListState(defaults), rpc: RPC, keyBase: KEY }
    const { data, isLoading, isPlaceholderData, error } = useServerList(RPC, KEY, list.state)
    const rows = useMemo(() => data?.rows || [], [data])
    const total = data?.total ?? 0
    const summary = data?.summary
    const shades = useMemo(() => itemShades(rows), [rows])

    // The "From Analytics" strip names a clicked technician; every row then is theirs.
    const technicianNames = useMemo(() => {
        const byId = {}
        for (const r of rows) if (r.technician_id) byId[r.technician_id] = r.technician
        return { technician_id: byId }
    }, [rows])

    const columns = useMemo(() => [
        {
            key: 'completed_on', label: 'Activity complete', sortKey: 'completed_on', filter: 'date',
            formatValue: v => formatAs(v, 'd MMM yyyy'),
            render: r => r.completed_on
                ? <span className="text-gray-600">{formatAs(r.completed_on, 'd MMM yyyy')}</span>
                : <span className="text-amber-800">Not yet done</span>,
        },
        {
            key: 'technician', label: 'Technician', sortKey: 'technician', filter: 'values',
            render: r => !r.attributed
                ? <span className="italic text-gray-600">Unattributed</span>
                : r.technician_employee_id
                    ? <Link to={mechanicPath(r.technician_employee_id)} className="font-medium text-blue-600 hover:underline">{r.technician}</Link>
                    : <span className="font-medium text-gray-900">{r.technician}</span>,
        },
        {
            key: 'trade', label: 'Trade', sortKey: 'trade', filter: 'values',
            formatValue: v => TRADE_LABELS[v] || v,
            render: r => <span className="text-gray-700">{TRADE_LABELS[r.trade] || '—'}</span>,
        },
        {
            key: 'hours', label: 'Hours', sortKey: 'hours', filter: 'number', align: 'right',
            render: r => <span className="font-semibold tabular-nums">{formatHours(parseFloat(r.hours) || 0)}</span>,
        },
        {
            key: PEOPLE_KEY, label: 'People on item', sortKey: PEOPLE_KEY, filter: 'values',
            sortLabels: ['Fewest people first', 'Most people first'],
            formatValue: peopleValueLabel,
            render: r => {
                const n = Number(r.people_on_item) || 0
                const style = n === 0 ? 'bg-gray-100 text-gray-700' : n === 1 ? 'bg-amber-100 text-amber-900' : 'bg-blue-100 text-blue-800'
                return <span className={`px-2 py-0.5 rounded-full text-xs ${style}`}>{peopleLabel(n, r.item_hours)}</span>
            },
        },
        {
            key: 'work_item', label: 'Work item', sortKey: 'category', filter: 'values', filterKey: 'category',
            cellClassName: 'max-w-xs truncate text-gray-700',
            render: r => {
                const text = [r.category, r.description].filter(Boolean).join(' — ')
                return <span title={`${r.issue_number} · ${text}`}>{text || '—'}</span>
            },
        },
        {
            key: 'issue_number', label: 'Work item no.', sortKey: 'issue_number', hiddenByDefault: true,
            render: r => <span className="text-gray-700">{r.issue_number}</span>,
        },
        {
            key: 'job_card_number', label: 'Job card', sortKey: 'job_card_number', filter: 'number',
            render: r => r.job_card_number
                ? <Link to={`/job-cards/${r.job_card_number}`} className="text-blue-600 hover:underline">#{r.job_card_number}</Link>
                : '—',
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
            render: r => r.site
                ? <span className="bg-gray-100 px-2 py-0.5 rounded text-xs text-gray-700">{r.site}</span>
                : '—',
        },
    ], [siteByName])

    const defaultKeys = useMemo(() => columns.filter(c => !c.hiddenByDefault).map(c => c.key), [columns])
    const [visibleKeys, setVisibleKeys] = useState(null)
    const shown = columns.filter(c => (visibleKeys ?? defaultKeys).includes(c.key))

    const shortcut = activeShortcut(list.state.filters[PEOPLE_KEY])
    const toggleShortcut = which => list.setFilter(PEOPLE_KEY, shortcut === which ? null : PEOPLE_SHORTCUTS[which])

    // Exports every row the view matches, not only the page on screen.
    const [exporting, setExporting] = useState(false)
    const handleExport = async () => {
        setExporting(true)
        try {
            const all = await fetchAllListRows(RPC, list.state)
            const range = list.state.analytics || list.state
            const wb = XLSX.utils.book_new()
            XLSX.utils.book_append_sheet(wb, XLSX.utils.json_to_sheet(buildLabourExportRows(all)), 'Labour')
            XLSX.writeFile(wb, `labour_entries_${range.from || 'all'}_to_${range.to || 'all'}.xlsx`)
        } catch (err) {
            toast.error('Export failed: ' + err.message)
        } finally {
            setExporting(false)
        }
    }

    // The Total row sits under the Hours column, wherever Columns has put it.
    const hoursAt = shown.findIndex(c => c.key === 'hours')
    const footer = summary && hoursAt >= 0 ? (
        <tr className="bg-white">
            {hoursAt > 0 && <td colSpan={hoursAt} className="px-4 py-3 font-bold text-gray-900">Total</td>}
            <td className="px-4 py-3 text-right font-bold tabular-nums">{formatHours(parseFloat(summary.total_hours) || 0)}</td>
            {shown.length - hoursAt - 1 > 0 && <td colSpan={shown.length - hoursAt - 1} className="px-4 py-3 text-xs text-gray-500">
                {total > rows.length ? `all ${total.toLocaleString('en-IN')} entries, not just this page` : ''}
            </td>}
        </tr>
    ) : null

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Labour' }]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8 space-y-4">
                <div>
                    <h1 className="text-2xl font-bold text-gray-900">Labour</h1>
                    <p className="text-sm text-gray-600 mt-1">
                        Every labour entry: one row per person per work item. A work item done by three people shows three rows.
                    </p>
                </div>

                <div className="flex flex-wrap gap-2 items-center">
                    {list.state.analytics
                        ? <AnalyticsOrigin list={list} listName="labour" names={technicianNames} />
                        : <DateRangeFilter dateRange={{ start: list.state.from, end: list.state.to }} onDateRangeChange={list.setDateRange} />}
                    <button
                        type="button"
                        onClick={handleExport}
                        disabled={exporting || total === 0}
                        className="sm:ml-auto inline-flex items-center px-4 min-h-[44px] border border-blue-600 text-sm font-medium rounded-lg text-blue-600 bg-white hover:bg-blue-50 disabled:opacity-50 whitespace-nowrap"
                    >
                        <ArrowDownTrayIcon className="h-5 w-5 mr-2" />
                        {exporting ? 'Exporting…' : 'Export to Excel'}
                    </button>
                </div>

                {error ? (
                    <div className="bg-white rounded-xl border border-red-200 p-6 text-sm text-red-700">
                        Could not load labour: {error.message}
                    </div>
                ) : (
                    <>
                        <Tiles summary={summary} loading={isLoading} shortcut={shortcut} onShortcut={toggleShortcut} />

                        <div className="flex flex-wrap gap-2 items-center">
                            <ListSearch list={list} placeholder="Search technician, vehicle, job card, work item…" />
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
                            rowClassName={(_, i) => (shades[i] ? 'bg-slate-50' : '')}
                            footer={footer}
                            emptyText="No labour entries match these filters."
                        />

                        <p className="text-xs text-gray-600">
                            Rows of the same work item share a shade.
                            {list.state.analytics
                                ? ' Work items not yet Done aren’t in this view: Labour utilisation counts them once they are done.'
                                : ' Work items not yet Done show “Not yet done” and appear whatever the date range.'}
                        </p>
                    </>
                )}
            </div>
        </div>
    )
}

function Tiles({ summary, loading, shortcut, onShortcut }) {
    const s = summary || {}
    const n = v => (loading || !summary ? '…' : Number(v || 0).toLocaleString('en-IN'))
    const h = v => (loading || !summary ? '…' : `${formatHours(parseFloat(v) || 0)} h`)
    const plural = (v, word) => (loading || !summary ? '…' : `${Number(v || 0).toLocaleString('en-IN')} ${word}${Number(v) === 1 ? '' : 's'}`)

    return (
        <section aria-label="Totals for this view" className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3">
            <div className="bg-white border border-gray-200 rounded-xl px-4 py-3.5">
                <p className="text-xs text-gray-600">Total hours</p>
                <p className="text-2xl font-bold text-gray-900 mt-0.5 tabular-nums">{h(s.total_hours)}</p>
                <p className="text-xs text-gray-500 mt-0.5">every row in this view</p>
            </div>
            <div className="bg-white border border-gray-200 rounded-xl px-4 py-3.5">
                <p className="text-xs text-gray-600">Entries</p>
                <p className="text-2xl font-bold text-gray-900 mt-0.5 tabular-nums">{n(s.entries)}</p>
                <p className="text-xs text-gray-500 mt-0.5">on {plural(s.work_items, 'work item')}</p>
            </div>
            <ShortcutTile
                label="Work items with 2+ people" value={n(s.items_2plus)} note="Show only these"
                active={shortcut === 'many'} onClick={() => onShortcut('many')}
            />
            <ShortcutTile
                label="Work items with one person" value={n(s.items_one)} note="Check whether a helper was left out"
                active={shortcut === 'one'} onClick={() => onShortcut('one')} warn
            />
            <ShortcutTile
                label="Unattributed" value={h(s.unattributed_hours)}
                note={`${plural(s.unattributed_items, 'work item')}, nobody recorded`}
                active={shortcut === 'nobody'} onClick={() => onShortcut('nobody')}
            />
        </section>
    )
}

function ShortcutTile({ label, value, note, active, onClick, warn = false }) {
    const base = warn ? 'bg-amber-50 border-amber-300' : 'bg-white border-gray-200'
    return (
        <button
            type="button"
            onClick={onClick}
            aria-pressed={active}
            className={`text-left border rounded-xl px-4 py-3.5 hover:shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500 ${base} ${active ? 'ring-2 ring-blue-600' : ''}`}
        >
            <p className={`text-xs ${warn ? 'text-amber-900' : 'text-gray-600'}`}>{label}</p>
            <p className={`text-2xl font-bold mt-0.5 tabular-nums ${warn ? 'text-amber-900' : 'text-gray-900'}`}>{value}</p>
            <p className={`text-xs mt-0.5 ${warn ? 'text-amber-800' : 'text-blue-700'}`}>{active ? 'Showing only these · click to show all' : note}</p>
        </button>
    )
}
