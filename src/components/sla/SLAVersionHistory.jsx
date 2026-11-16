import { useState } from 'react'
import { createPortal } from 'react-dom'
import { ChevronDownIcon, ChevronRightIcon, XMarkIcon } from '@heroicons/react/24/outline'
import { useCancelSLAVersion } from '../../hooks/useSLASettings'
import { formatWeeklyOffs, versionTimeline, workingDays } from '../../utils/slaDraft'
import { formatDateTime } from '../../utils/datetime'

const STATE_STYLES = {
    active: 'bg-green-50 text-green-700 border-green-200',
    scheduled: 'bg-blue-50 text-blue-700 border-blue-200',
    ended: 'bg-gray-50 text-gray-600 border-gray-200',
    cancelled: 'bg-red-50 text-red-700 border-red-200',
}
const STATE_LABELS = { active: 'Active', scheduled: 'Scheduled', ended: 'Ended', cancelled: 'Cancelled' }

/**
 * Every SLA version (MAIN-136): values, who, why, active from and to. A scheduled version
 * can be cancelled with a reason until it starts; nothing can be edited.
 */
export default function SLAVersionHistory({ versions, canEdit }) {
    const [open, setOpen] = useState(null)
    const [cancelling, setCancelling] = useState(null)
    const timeline = versionTimeline(versions)

    return (
        <div className="bg-white rounded-lg shadow overflow-hidden">
            <h2 className="text-lg font-medium text-gray-900 px-6 pt-5 pb-3">Version history</h2>
            <ul className="divide-y divide-gray-200 border-t border-gray-200">
                {timeline.map(v => (
                    <li key={v.id} className="px-6 py-4">
                        <div className="flex flex-wrap items-start justify-between gap-3">
                            <button
                                type="button"
                                onClick={() => setOpen(open === v.id ? null : v.id)}
                                className="flex items-start gap-2 text-left"
                                aria-expanded={open === v.id}
                            >
                                {open === v.id
                                    ? <ChevronDownIcon className="w-4 h-4 mt-1 text-gray-500" />
                                    : <ChevronRightIcon className="w-4 h-4 mt-1 text-gray-500" />}
                                <div>
                                    <div className="flex items-center gap-2">
                                        <span className="text-sm font-semibold text-gray-900">Version {v.version_number}</span>
                                        <span className={`px-2 py-0.5 rounded-full border text-xs font-medium ${STATE_STYLES[v.state]}`}>
                                            {STATE_LABELS[v.state]}
                                        </span>
                                    </div>
                                    <p className="text-xs text-gray-600 mt-0.5">
                                        {v.state === 'cancelled'
                                            ? `Was to start ${formatDateTime(v.starts_at)}`
                                            : `${formatDateTime(v.starts_at)} → ${v.ends_at ? formatDateTime(v.ends_at) : 'no end'}`}
                                    </p>
                                </div>
                            </button>
                            {canEdit && v.state === 'scheduled' && (
                                <button
                                    type="button"
                                    onClick={() => setCancelling(v)}
                                    className="text-sm text-red-600 hover:text-red-800"
                                >
                                    Cancel version
                                </button>
                            )}
                        </div>

                        <dl className="mt-2 ml-6 grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1 text-sm">
                            <div className="flex gap-2"><dt className="text-gray-500">Acceptance SLA Threshold</dt><dd className="text-gray-900">{workingDays(v.acceptance_days)}</dd></div>
                            <div className="flex gap-2"><dt className="text-gray-500">Weekly Offs</dt><dd className="text-gray-900">{formatWeeklyOffs(v.weekly_offs)}</dd></div>
                            <div className="flex gap-2 sm:col-span-2"><dt className="text-gray-500">By</dt><dd className="text-gray-900">{v.created_by_name ?? 'System'} on {formatDateTime(v.created_at)}</dd></div>
                            <div className="flex gap-2 sm:col-span-2"><dt className="text-gray-500 shrink-0">Why</dt><dd className="text-gray-900">{v.reason}</dd></div>
                            {v.cancelled_at && (
                                <div className="flex gap-2 sm:col-span-2">
                                    <dt className="text-gray-500 shrink-0">Cancelled</dt>
                                    <dd className="text-gray-900">by {v.cancelled_by_name} on {formatDateTime(v.cancelled_at)}: {v.cancel_reason}</dd>
                                </div>
                            )}
                        </dl>

                        {open === v.id && (
                            <table className="mt-3 ml-6 text-sm">
                                <thead>
                                    <tr className="text-left text-xs text-gray-500 uppercase">
                                        <th className="py-1 pr-6 font-medium">Severity</th>
                                        <th className="py-1 pr-6 font-medium">Category</th>
                                        <th className="py-1 font-medium">Turnaround Time (working days)</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {v.turnaround.map(r => (
                                        <tr key={`${r.severity}-${r.category}`}>
                                            <td className="py-0.5 pr-6 text-gray-700">{r.severity}</td>
                                            <td className="py-0.5 pr-6 text-gray-700">{r.category}</td>
                                            <td className="py-0.5 text-gray-900">{r.sla_days}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        )}
                    </li>
                ))}
            </ul>

            {cancelling && <CancelVersionModal version={cancelling} onClose={() => setCancelling(null)} />}
        </div>
    )
}

function CancelVersionModal({ version, onClose }) {
    const [reason, setReason] = useState('')
    const cancel = useCancelSLAVersion()
    const trimmed = reason.trim()

    return createPortal(
        <div className="fixed inset-0 z-50 overflow-y-auto">
            <div className="fixed inset-0 bg-black bg-opacity-50" onClick={onClose} />
            <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
                <div role="dialog" aria-labelledby="cancel-sla-version-title" className="relative bg-white rounded-t-2xl sm:rounded-2xl shadow-xl w-full max-w-md">
                    <div className="flex items-center justify-between p-5 border-b">
                        <h3 id="cancel-sla-version-title" className="text-lg font-semibold text-gray-900">
                            Cancel Version {version.version_number}
                        </h3>
                        <button type="button" onClick={onClose} aria-label="Close" className="text-gray-500 hover:text-gray-600 p-1">
                            <XMarkIcon className="w-6 h-6" />
                        </button>
                    </div>
                    <div className="p-5 space-y-4">
                        <p className="text-sm text-gray-700">
                            It was to start {formatDateTime(version.starts_at)}. It stays in the history as cancelled,
                            and the current version carries on. To change it, cancel it and save a new one.
                        </p>
                        <div>
                            <label htmlFor="cancel-sla-version-reason" className="block text-sm font-medium text-gray-700 mb-1">
                                Reason <span className="text-red-500">*</span>
                            </label>
                            <textarea
                                id="cancel-sla-version-reason"
                                autoFocus
                                rows={3}
                                value={reason}
                                onChange={e => setReason(e.target.value)}
                                className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-red-500"
                            />
                        </div>
                        {cancel.error && <p className="text-sm text-red-600">{cancel.error.message}</p>}
                    </div>
                    <div className="flex justify-end gap-3 p-5 border-t">
                        <button type="button" onClick={onClose} className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50">
                            Keep it
                        </button>
                        <button
                            type="button"
                            onClick={() => cancel.mutate({ versionId: version.id, reason: trimmed }, { onSuccess: onClose })}
                            disabled={!trimmed || cancel.isPending}
                            className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-lg hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {cancel.isPending ? 'Cancelling…' : 'Cancel version'}
                        </button>
                    </div>
                </div>
            </div>
        </div>,
        document.body,
    )
}
