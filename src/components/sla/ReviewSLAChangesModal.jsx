import { useMemo, useState } from 'react'
import { createPortal } from 'react-dom'
import { XMarkIcon } from '@heroicons/react/24/outline'
import { usePreviewSLAChanges, useApplySLAChange } from '../../hooks/useSLASettings'
import { buildChange, holidayChanges, onTimePercent, versionChanges } from '../../utils/slaDraft'
import { SLA_STATUS_LABELS } from '../../utils/slaStatus'
import { formatDate } from '../../utils/datetime'

const KIND_LABELS = { ticket: 'Ticket Turnaround', issue: 'Issue Turnaround', acceptance: 'Acceptance' }

// <input type="datetime-local"> reads and writes the viewer's zone, to the minute.
const localInputValue = (d) => {
    const pad = (n) => String(n).padStart(2, '0')
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/**
 * Review changes (MAIN-136): old and new values, what the holiday changes do to existing
 * deadlines, and the 30/90-day on-time % as it is and as it would have been under the new
 * version. Then a start (versions only), a reason, and Confirm. Nothing is written until
 * Confirm.
 */
export default function ReviewSLAChangesModal({ version, turnaround, holidays, draft, onClose, onSaved }) {
    const [startMode, setStartMode] = useState('now')
    const [startAt, setStartAt] = useState('')
    const [reason, setReason] = useState('')

    const changes = versionChanges(version, turnaround, draft)
    const holidayLines = holidayChanges(holidays, draft)
    const previewChange = useMemo(() => buildChange(version, turnaround, draft), [version, turnaround, draft])
    const preview = usePreviewSLAChanges(previewChange, true)
    const apply = useApplySLAChange()

    const startDate = startAt ? new Date(startAt) : null
    const startValid = startMode === 'now' || (startDate && startDate > new Date())
    const canConfirm = reason.trim() !== '' && startValid && !preview.isLoading && !preview.error && !apply.isPending

    const confirm = () => {
        apply.mutate(
            buildChange(version, turnaround, draft, {
                reason: reason.trim(),
                startsAt: startMode === 'schedule' ? startDate.toISOString() : null,
            }),
            { onSuccess: onSaved },
        )
    }

    return createPortal(
        <div className="fixed inset-0 z-50 overflow-y-auto">
            <div className="fixed inset-0 bg-black bg-opacity-50" onClick={onClose} />

            <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
                <div role="dialog" aria-labelledby="review-sla-title" className="relative bg-white rounded-t-2xl sm:rounded-2xl shadow-xl w-full max-w-2xl">
                    <div className="flex items-center justify-between p-5 border-b">
                        <h3 id="review-sla-title" className="text-lg font-semibold text-gray-900">Review changes</h3>
                        <button type="button" onClick={onClose} aria-label="Close" className="text-gray-500 hover:text-gray-600 p-1">
                            <XMarkIcon className="w-6 h-6" />
                        </button>
                    </div>

                    <div className="p-5 space-y-6">
                        {changes.length > 0 && (
                            <section>
                                <h4 className="text-sm font-semibold text-gray-900 mb-2">New version {version.version_number + 1}</h4>
                                <table className="w-full text-sm">
                                    <thead>
                                        <tr className="text-left text-xs text-gray-500 uppercase">
                                            <th className="py-1 pr-3 font-medium">Setting</th>
                                            <th className="py-1 pr-3 font-medium">Now (Version {version.version_number})</th>
                                            <th className="py-1 font-medium">New</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-100">
                                        {changes.map(c => (
                                            <tr key={c.label}>
                                                <td className="py-1.5 pr-3 text-gray-700">{c.label}</td>
                                                <td className="py-1.5 pr-3 text-gray-500">{c.from}</td>
                                                <td className="py-1.5 font-medium text-gray-900">{c.to}</td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </section>
                        )}

                        {holidayLines.length > 0 && (
                            <section>
                                <h4 className="text-sm font-semibold text-gray-900 mb-2">Holidays</h4>
                                <ul className="text-sm space-y-1">
                                    {holidayLines.map(h => (
                                        <li key={`${h.action}-${h.date}`} className="flex gap-2">
                                            <span className={`font-medium ${h.action === 'add' ? 'text-green-700' : 'text-red-700'}`}>
                                                {h.action === 'add' ? 'Add' : 'Remove'}
                                            </span>
                                            <span className="text-gray-900">{formatDate(h.date)}</span>
                                            {h.description && <span className="text-gray-500">{h.description}</span>}
                                        </li>
                                    ))}
                                </ul>
                            </section>
                        )}

                        {preview.isLoading && <p className="text-sm text-gray-500">Working out the effect…</p>}
                        {preview.error && <p className="text-sm text-red-600">{preview.error.message}</p>}

                        {preview.data?.holidays && <HolidayEffects effects={preview.data.holidays} />}
                        {preview.data?.on_time && <OnTimeWhatIf rows={preview.data.on_time} />}

                        {changes.length > 0 && (
                            <section>
                                <h4 className="text-sm font-semibold text-gray-900 mb-2">Version {version.version_number + 1} starts</h4>
                                <div className="flex flex-wrap items-center gap-4 text-sm">
                                    <label className="inline-flex items-center gap-2">
                                        <input type="radio" name="sla-start" checked={startMode === 'now'} onChange={() => setStartMode('now')} />
                                        Now
                                    </label>
                                    <label className="inline-flex items-center gap-2">
                                        <input type="radio" name="sla-start" checked={startMode === 'schedule'} onChange={() => setStartMode('schedule')} />
                                        On
                                    </label>
                                    <input
                                        type="datetime-local"
                                        aria-label="Start date and time"
                                        value={startAt}
                                        min={localInputValue(new Date())}
                                        onChange={e => { setStartAt(e.target.value); setStartMode('schedule') }}
                                        className="rounded-md border-gray-300 shadow-sm sm:text-sm focus:border-blue-500 focus:ring-blue-500"
                                    />
                                </div>
                                <p className="text-xs text-gray-500 mt-1">
                                    It applies to tickets raised, and issues added, from then on. Existing tickets and issues keep their version.
                                </p>
                                {startMode === 'schedule' && !startValid && (
                                    <p className="text-xs text-red-600 mt-1">Pick a date and time in the future.</p>
                                )}
                            </section>
                        )}

                        <section>
                            <label htmlFor="sla-change-reason" className="block text-sm font-semibold text-gray-900 mb-1">
                                Reason <span className="text-red-500">*</span>
                            </label>
                            <textarea
                                id="sla-change-reason"
                                rows={3}
                                value={reason}
                                onChange={e => setReason(e.target.value)}
                                className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                            />
                            <p className="text-xs text-gray-500 mt-1">Recorded with every change above.</p>
                        </section>

                        {apply.error && <p className="text-sm text-red-600">{apply.error.message}</p>}
                    </div>

                    <div className="flex justify-end gap-3 p-5 border-t">
                        <button type="button" onClick={onClose} className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50">
                            Back to editing
                        </button>
                        <button
                            type="button"
                            onClick={confirm}
                            disabled={!canConfirm}
                            className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {apply.isPending ? 'Saving…' : 'Confirm'}
                        </button>
                    </div>
                </div>
            </div>
        </div>,
        document.body,
    )
}

function HolidayEffects({ effects }) {
    const { tickets_moved: tickets, issues_moved: issues, status_changes: moves } = effects
    return (
        <section>
            <h4 className="text-sm font-semibold text-gray-900 mb-1">Effect of the holiday changes</h4>
            <p className="text-sm text-gray-700">
                {tickets === 0
                    ? 'No ticket or issue gets a new deadline.'
                    : `${tickets} ticket${tickets === 1 ? '' : 's'} and ${issues} issue${issues === 1 ? '' : 's'} get a new deadline.`}
            </p>
            {moves.length > 0 ? (
                <ul className="text-sm text-gray-700 mt-2 space-y-0.5">
                    {moves.map(m => (
                        <li key={`${m.kind}-${m.from}-${m.to}`}>
                            {KIND_LABELS[m.kind]}: {m.count} from {SLA_STATUS_LABELS[m.from] ?? m.from} to {SLA_STATUS_LABELS[m.to] ?? m.to}
                        </li>
                    ))}
                </ul>
            ) : tickets > 0 && (
                <p className="text-sm text-gray-500 mt-1">No SLA status changes.</p>
            )}
        </section>
    )
}

function OnTimeWhatIf({ rows }) {
    const slas = ['Turnaround', 'Acceptance']
    const cell = (sla, days, which) => {
        const r = rows.find(x => x.sla === sla && x.window_days === days)
        return r ? onTimePercent(r[`${which}_adhered`], r[`${which}_judged`]) : '—'
    }
    return (
        <section>
            <h4 className="text-sm font-semibold text-gray-900 mb-1">On-time %</h4>
            <p className="text-xs text-gray-500 mb-2">
                What-if: as it is, and as it would have been under the new version. Existing tickets are not affected.
            </p>
            <table className="w-full text-sm">
                <thead>
                    <tr className="text-left text-xs text-gray-500 uppercase">
                        <th className="py-1 pr-3 font-medium">SLA</th>
                        <th className="py-1 pr-3 font-medium">Last 30 days</th>
                        <th className="py-1 font-medium">Last 90 days</th>
                    </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                    {slas.map(sla => (
                        <tr key={sla}>
                            <td className="py-1.5 pr-3 text-gray-700">{sla}</td>
                            {[30, 90].map(days => (
                                <td key={days} className="py-1.5 pr-3">
                                    <span className="text-gray-500">{cell(sla, days, 'as_is')}</span>
                                    <span className="text-gray-400"> → </span>
                                    <span className="font-medium text-gray-900">{cell(sla, days, 'would_be')}</span>
                                </td>
                            ))}
                        </tr>
                    ))}
                </tbody>
            </table>
        </section>
    )
}
