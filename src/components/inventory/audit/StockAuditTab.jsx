import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { formatAs, formatDate } from '../../../utils/datetime'
import {
    BuildingOffice2Icon,
    ChevronLeftIcon,
    ArrowDownTrayIcon,
    ArrowUpTrayIcon,
    ClipboardDocumentCheckIcon,
} from '@heroicons/react/24/outline'
import { TicketListSkeleton } from '../../shared/LoadingSkeleton'
import { useWorkshopLocations } from '../../../hooks/useWorkshopLocations'
import { useParts } from '../../../hooks/useInventory'
import {
    AUDIT_STATUS_LABELS,
    AUDIT_STATUS_BADGE,
    auditRef,
    useStockAudits,
    useOpenStockAudit,
    useStockAudit,
    useStockAuditItems,
    useStartStockAudit,
    useCancelStockAudit,
} from '../../../hooks/useStockAudits'
import { buildCountSheet } from '../../../utils/auditSheet'
import UploadCountSheetModal from './UploadCountSheetModal'
import AuditReviewTable from './AuditReviewTable'
import AuditSummary from './AuditSummary'

function StatusBadge({ status }) {
    return (
        <span className={`px-2 py-0.5 text-xs rounded-full ${AUDIT_STATUS_BADGE[status] ?? 'bg-gray-100 text-gray-600'}`}>
            {AUDIT_STATUS_LABELS[status] ?? status}
        </span>
    )
}

// ── Level 1: pick a workshop ──────────────────────────────────────────────────

function LocationPicker({ locations, audits, onSelect }) {
    const openByLocation = audits.reduce((acc, a) => {
        if (a.status === 'counting' || a.status === 'review') acc[a.location_id] = a
        return acc
    }, {})

    return (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {locations.map(location => {
                const open = openByLocation[location.id]
                const last = audits.find(a => a.location_id === location.id && a.status === 'completed')
                return (
                    <button
                        key={location.id}
                        onClick={() => onSelect(location.id)}
                        className="text-left bg-white border rounded-lg shadow-sm p-5 hover:border-blue-400 hover:shadow transition-all"
                    >
                        <div className="flex items-start gap-2">
                            <BuildingOffice2Icon className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
                            <div className="min-w-0">
                                <div className="font-semibold text-gray-900 truncate">{location.name}</div>
                                <div className="text-xs text-gray-400 truncate">
                                    {location.address || 'No address recorded'}
                                </div>
                            </div>
                        </div>
                        <div className="mt-4 text-sm">
                            {open ? (
                                <div className="flex items-center gap-2">
                                    <StatusBadge status={open.status} />
                                    <span className="text-xs text-gray-500">
                                        since {formatAs(open.started_at, 'dd MMM')}
                                    </span>
                                </div>
                            ) : last ? (
                                <span className="text-xs text-gray-500">
                                    Last audited {formatDate(last.completed_at)}
                                </span>
                            ) : (
                                <span className="text-xs text-gray-400">Never audited</span>
                            )}
                        </div>
                    </button>
                )
            })}
        </div>
    )
}

// ── Start ─────────────────────────────────────────────────────────────────────

function StartAuditCard({ location, canAudit }) {
    const startAudit = useStartStockAudit()
    const [notes, setNotes] = useState('')
    const [error, setError] = useState(null)

    async function handleStart() {
        setError(null)
        try {
            await startAudit.mutateAsync({ locationId: location.id, notes })
        } catch (err) {
            setError(err.message)
        }
    }

    return (
        <div className="bg-white rounded-lg shadow-sm p-6">
            <div className="flex items-start gap-3">
                <ClipboardDocumentCheckIcon className="w-6 h-6 text-blue-600 flex-shrink-0 mt-0.5" />
                <div className="flex-1 min-w-0">
                    <h3 className="text-sm font-semibold text-gray-900">No audit in progress here</h3>
                    <p className="text-xs text-gray-500 mt-1 max-w-2xl">
                        Starting an audit freezes what the app believes is on the shelves and produces a
                        count sheet to fill in. Stock keeps moving normally while the count is underway —
                        anything used on a job card in the meantime stays used.
                    </p>

                    {canAudit && (
                        <div className="mt-4 flex flex-col sm:flex-row gap-2 sm:items-center">
                            <input
                                type="text"
                                value={notes}
                                onChange={e => setNotes(e.target.value)}
                                placeholder="Note (optional) — e.g. quarterly count, who is counting"
                                className="flex-1 border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500"
                            />
                            <button
                                onClick={handleStart}
                                disabled={startAudit.isPending}
                                className="px-5 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 disabled:opacity-50 whitespace-nowrap"
                            >
                                {startAudit.isPending ? 'Starting…' : 'Start audit'}
                            </button>
                        </div>
                    )}

                    {error && <p className="text-sm text-red-600 mt-3">{error}</p>}
                </div>
            </div>
        </div>
    )
}

// ── Counting ──────────────────────────────────────────────────────────────────

function CountingCard({ audit, items, parts, canAudit }) {
    const cancelAudit = useCancelStockAudit()
    const [showUpload, setShowUpload] = useState(false)
    const [error, setError] = useState(null)

    async function handleCancel() {
        const reason = window.prompt('Cancelling abandons this count without changing any stock.\n\nWhy is it being cancelled?')
        if (reason === null) return
        setError(null)
        try {
            await cancelAudit.mutateAsync({ auditId: audit.id, reason })
        } catch (err) {
            setError(err.message)
        }
    }

    return (
        <>
            <div className="bg-white rounded-lg shadow-sm p-6">
                <div className="flex items-start justify-between gap-4 flex-wrap">
                    <div>
                        <div className="flex items-center gap-2 flex-wrap">
                            <span className="font-mono text-sm font-semibold text-gray-900">{auditRef(audit)}</span>
                            <StatusBadge status={audit.status} />
                            <span className="text-sm text-gray-500">
                                started {formatDate(audit.started_at)} by {audit.started_by_name || '—'}
                            </span>
                        </div>
                        <p className="text-sm text-gray-700 mt-2">
                            {items.length === 0
                                ? 'This workshop holds no stock yet. Download the sheet and write in whatever is physically on the shelves — that becomes its opening stock.'
                                : `${items.length} part${items.length === 1 ? '' : 's'} to count, plus blank rows for anything found that isn't listed.`}
                        </p>
                        {audit.notes && <p className="text-xs text-gray-500 mt-1">“{audit.notes}”</p>}
                    </div>

                    {canAudit && (
                        <div className="flex gap-2">
                            <button
                                onClick={() => buildCountSheet({ audit, items, locationName: audit.location?.name })}
                                className="flex items-center gap-2 px-3 py-2 text-sm border rounded-lg bg-white text-gray-700 hover:bg-gray-50 shadow-sm"
                            >
                                <ArrowDownTrayIcon className="w-4 h-4" />
                                Download count sheet
                            </button>
                            <button
                                onClick={() => setShowUpload(true)}
                                className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700"
                            >
                                <ArrowUpTrayIcon className="w-4 h-4" />
                                Upload filled sheet
                            </button>
                        </div>
                    )}
                </div>

                {canAudit && (
                    <div className="mt-4 pt-4 border-t flex justify-end">
                        <button
                            onClick={handleCancel}
                            disabled={cancelAudit.isPending}
                            className="text-xs text-gray-500 hover:text-red-600 disabled:opacity-50"
                        >
                            {cancelAudit.isPending ? 'Cancelling…' : 'Cancel this audit'}
                        </button>
                    </div>
                )}

                {error && <p className="text-sm text-red-600 mt-3">{error}</p>}
            </div>

            {showUpload && (
                <UploadCountSheetModal
                    audit={audit}
                    items={items}
                    parts={parts}
                    onClose={() => setShowUpload(false)}
                />
            )}
        </>
    )
}

// ── Level 2: one workshop ─────────────────────────────────────────────────────

function LocationAudit({ location, canAudit, onViewAudit }) {
    const { data: openAudit, isLoading: loadingOpen } = useOpenStockAudit(location.id)
    const { data: items = [], isLoading: loadingItems } = useStockAuditItems(openAudit?.id)
    const { data: parts = [] } = useParts()
    const { data: history = [] } = useStockAudits({ locationId: location.id })

    if (loadingOpen) return <TicketListSkeleton />

    const past = history.filter(a => a.status === 'completed' || a.status === 'cancelled')

    return (
        <div className="space-y-6">
            {!openAudit && <StartAuditCard location={location} canAudit={canAudit} />}

            {openAudit && loadingItems && <TicketListSkeleton />}

            {openAudit && !loadingItems && openAudit.status === 'counting' && (
                <CountingCard audit={openAudit} items={items} parts={parts} canAudit={canAudit} />
            )}

            {openAudit && !loadingItems && openAudit.status === 'review' && (
                <div className="space-y-4">
                    <div className="bg-white rounded-lg shadow-sm p-4 flex items-center gap-3 flex-wrap">
                        <span className="font-mono text-sm font-semibold text-gray-900">{auditRef(openAudit)}</span>
                        <StatusBadge status={openAudit.status} />
                        <span className="text-sm text-gray-500">
                            counted {openAudit.counts_uploaded_at
                                ? formatDate(openAudit.counts_uploaded_at)
                                : ''} by {openAudit.counts_uploaded_by_name || '—'}
                        </span>
                    </div>
                    {canAudit ? (
                        <AuditReviewTable audit={openAudit} items={items} />
                    ) : (
                        <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                            A count is under review by finance.
                        </div>
                    )}
                </div>
            )}

            {past.length > 0 && (
                <div>
                    <h3 className="text-sm font-semibold text-gray-700 mb-3">Past audits</h3>
                    <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                        <table className="min-w-full divide-y divide-gray-100 text-sm">
                            <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                                <tr>
                                    <th className="px-4 py-3 text-left">Ref</th>
                                    <th className="px-4 py-3 text-left">Date</th>
                                    <th className="px-4 py-3 text-left">Status</th>
                                    <th className="px-4 py-3 text-right">Counted</th>
                                    <th className="px-4 py-3 text-right">Mismatches</th>
                                    <th className="px-4 py-3 text-right">Net units</th>
                                    <th className="px-4 py-3 text-left">By</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-50">
                                {past.map(a => (
                                    <tr
                                        key={a.id}
                                        onClick={() => a.status === 'completed' && onViewAudit(a.id)}
                                        className={`hover:bg-gray-50 ${a.status === 'completed' ? 'cursor-pointer' : ''}`}
                                    >
                                        <td className="px-4 py-3 font-mono text-xs text-gray-900">
                                            {auditRef(a)}
                                        </td>
                                        <td className="px-4 py-3 text-gray-900">
                                            {formatDate(a.completed_at || a.cancelled_at || a.started_at)}
                                        </td>
                                        <td className="px-4 py-3"><StatusBadge status={a.status} /></td>
                                        <td className="px-4 py-3 text-right text-gray-600">
                                            {a.status === 'completed' ? a.total_parts : '—'}
                                        </td>
                                        <td className="px-4 py-3 text-right text-gray-600">
                                            {a.status === 'completed' ? a.variance_parts : '—'}
                                        </td>
                                        <td className={`px-4 py-3 text-right font-medium ${
                                            Number(a.net_units) < 0 ? 'text-red-600' : Number(a.net_units) > 0 ? 'text-green-700' : 'text-gray-400'
                                        }`}>
                                            {a.status === 'completed'
                                                ? (Number(a.net_units) > 0 ? `+${a.net_units}` : a.net_units)
                                                : '—'}
                                        </td>
                                        <td className="px-4 py-3 text-gray-600">
                                            {a.completed_by_name || a.cancelled_by_name || a.started_by_name || '—'}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>
            )}
        </div>
    )
}

// ── Tab ───────────────────────────────────────────────────────────────────────

/**
 * Stock Audit tab: pick a workshop, then run or review its count.
 *
 * @param {object} props
 * @param {boolean} props.canAudit  finance and super_admin run audits; everyone else who
 *                                  can see Inventory gets the read-only view.
 */
export default function StockAuditTab({ canAudit }) {
    const { data: locations = [], isLoading } = useWorkshopLocations()
    const { data: audits = [] } = useStockAudits()
    const [selectedId, setSelectedId] = useState(null)

    // Which audit is open lives in the URL, so a Consumption History row can link
    // straight to the audit that explains it.
    const [searchParams, setSearchParams] = useSearchParams()
    const viewingAuditId = searchParams.get('audit')
    const setViewingAuditId = id =>
        setSearchParams(id ? { tab: 'audit', audit: id } : { tab: 'audit' })
    const { data: viewingAudit } = useStockAudit(viewingAuditId)

    if (isLoading) return <TicketListSkeleton />

    if (viewingAuditId) {
        return (
            <div className="space-y-4">
                <button
                    onClick={() => setViewingAuditId(null)}
                    className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-900"
                >
                    <ChevronLeftIcon className="w-4 h-4" />
                    Back
                </button>
                {viewingAudit ? (
                    <>
                        <div>
                            <h2 className="text-lg font-semibold text-gray-900">
                                <span className="font-mono">{auditRef(viewingAudit)}</span>
                                {' — '}{viewingAudit.location?.name}
                            </h2>
                            <p className="text-xs text-gray-500">
                                {AUDIT_STATUS_LABELS[viewingAudit.status] ?? viewingAudit.status}
                                {viewingAudit.completed_at &&
                                    ` · ${formatDate(viewingAudit.completed_at)}`}
                            </p>
                        </div>
                        <AuditSummary audit={viewingAudit} />
                    </>
                ) : (
                    <TicketListSkeleton />
                )}
            </div>
        )
    }

    // A single workshop makes the drill-down pure ceremony.
    const effectiveId = selectedId || (locations.length === 1 ? locations[0].id : null)

    if (!effectiveId) {
        return <LocationPicker locations={locations} audits={audits} onSelect={setSelectedId} />
    }

    const location = locations.find(l => l.id === effectiveId)
    if (!location) return null

    return (
        <div className="space-y-4">
            {locations.length > 1 && (
                <button
                    onClick={() => setSelectedId(null)}
                    className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-900"
                >
                    <ChevronLeftIcon className="w-4 h-4" />
                    All workshops
                </button>
            )}

            <div>
                <h2 className="text-lg font-semibold text-gray-900">{location.name}</h2>
                <p className="text-xs text-gray-500">{location.address || 'No address recorded'}</p>
            </div>

            <LocationAudit
                location={location}
                canAudit={canAudit}
                onViewAudit={setViewingAuditId}
            />
        </div>
    )
}
