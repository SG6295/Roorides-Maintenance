
import { useState, useMemo } from 'react'
import { ClockIcon } from '@heroicons/react/24/outline'
import { useUserAuditLogs } from '../../hooks/useUserAuditLogs'
import { ROLE_LABELS } from '../../constants/userRoles'

const PAGE_SIZE = 20

const FIELD_LABELS = {
    name: 'name',
    email: 'email',
    role: 'role',
    employee_id: 'employee ID',
    contact: 'contact',
    is_active: 'status',
}

function relativeTime(iso) {
    const then = new Date(iso)
    const seconds = Math.floor((Date.now() - then.getTime()) / 1000)
    if (seconds < 60) return 'just now'
    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return `${minutes} minute${minutes > 1 ? 's' : ''} ago`
    const hours = Math.floor(minutes / 60)
    if (hours < 24) return `${hours} hour${hours > 1 ? 's' : ''} ago`
    const days = Math.floor(hours / 24)
    if (days === 1) return 'yesterday'
    if (days < 30) return `${days} days ago`
    return then.toLocaleDateString()
}

const displayValue = (field, value) => {
    if (value === null || value === undefined || value === '') return 'empty'
    if (field === 'role') return ROLE_LABELS[value] || value
    return String(value)
}

/** Turns one changed field into a readable phrase. */
function describeChange(field, oldData, newData) {
    if (field === 'password') {
        return <>reset their <span className="font-medium">password</span></>
    }

    if (field === 'sites') {
        const before = oldData?.sites ?? []
        const after = newData?.sites ?? []
        const added = after.filter(s => !before.includes(s))
        const removed = before.filter(s => !after.includes(s))
        const parts = []
        if (added.length) parts.push(`+${added.join(', +')}`)
        if (removed.length) parts.push(`−${removed.join(', −')}`)
        return <>changed their <span className="font-medium">sites</span>: {parts.join('  ') || 'no net change'}</>
    }

    if (field === 'is_active') {
        return newData?.is_active ? 'reactivated the account' : 'deactivated the account'
    }

    const label = FIELD_LABELS[field] || field
    const emphasis = field === 'role' ? 'text-purple-700 font-medium' : 'font-medium'
    return (
        <>
            changed their <span className="font-medium">{label}</span> from{' '}
            <span className={emphasis}>{displayValue(field, oldData?.[field])}</span> to{' '}
            <span className={emphasis}>{displayValue(field, newData?.[field])}</span>
        </>
    )
}

function EntryName({ name, id, liveIds }) {
    const deleted = id && liveIds.size > 0 && !liveIds.has(id)
    return (
        <>
            <span className="font-semibold text-gray-900">{name || 'Unknown'}</span>
            {deleted && <span className="text-gray-400 font-normal"> (deleted)</span>}
        </>
    )
}

/**
 * Super-admin-only history of user-management changes, newest first.
 *
 * `users` is the list the page already loaded — it is only used to mark entries
 * whose subject or actor no longer exists, so no extra query is needed.
 */
export default function UserAuditLog({ users = [], enabled = true }) {
    const [page, setPage] = useState(0)
    const { data, isLoading, isError } = useUserAuditLogs({ page, pageSize: PAGE_SIZE, enabled })

    const liveIds = useMemo(() => new Set(users.map(u => u.id)), [users])

    const entries = data?.entries ?? []
    const total = data?.total ?? 0
    const from = total === 0 ? 0 : page * PAGE_SIZE + 1
    const to = Math.min((page + 1) * PAGE_SIZE, total)
    const hasPrev = page > 0
    const hasNext = to < total

    return (
        <div className="mt-8">
            <div className="flex items-center gap-2 mb-3">
                <ClockIcon className="h-5 w-5 text-gray-500" />
                <h3 className="text-lg font-medium text-gray-900">Change History</h3>
            </div>

            <div className="bg-white shadow overflow-hidden sm:rounded-md border border-gray-300">
                {isLoading ? (
                    <p className="px-6 py-8 text-center text-gray-600 text-sm">Loading history...</p>
                ) : isError ? (
                    <p className="px-6 py-8 text-center text-gray-600 text-sm">Could not load the change history.</p>
                ) : entries.length === 0 ? (
                    <p className="px-6 py-8 text-center text-gray-600 text-sm">No user changes recorded yet.</p>
                ) : (
                    <ul role="list" className="divide-y divide-gray-200">
                        {entries.map(entry => (
                            <li key={entry.id} className="px-4 py-3 sm:px-6">
                                <div className="flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-1">
                                    <div className="text-sm text-gray-700 space-y-0.5">
                                        {entry.action === 'CREATE' ? (
                                            <p>
                                                <EntryName name={entry.performed_by_name} id={entry.performed_by} liveIds={liveIds} />
                                                {' created '}
                                                <EntryName name={entry.target_name} id={entry.target_user_id} liveIds={liveIds} />
                                                {entry.new_data?.role && (
                                                    <> as <span className="font-medium">{ROLE_LABELS[entry.new_data.role] || entry.new_data.role}</span></>
                                                )}
                                            </p>
                                        ) : (
                                            (entry.changed_fields ?? []).map(field => (
                                                <p key={field}>
                                                    <EntryName name={entry.performed_by_name} id={entry.performed_by} liveIds={liveIds} />
                                                    {' '}
                                                    {describeChange(field, entry.old_data, entry.new_data)}
                                                    {' for '}
                                                    <EntryName name={entry.target_name} id={entry.target_user_id} liveIds={liveIds} />
                                                </p>
                                            ))
                                        )}
                                    </div>
                                    <span
                                        className="text-xs text-gray-500 whitespace-nowrap flex-shrink-0"
                                        title={new Date(entry.performed_at).toLocaleString()}
                                    >
                                        {relativeTime(entry.performed_at)}
                                    </span>
                                </div>
                            </li>
                        ))}
                    </ul>
                )}

                {total > PAGE_SIZE && (
                    <div className="flex items-center justify-between border-t border-gray-200 bg-gray-50 px-4 py-3 sm:px-6">
                        <p className="text-xs text-gray-600">
                            Showing {from}–{to} of {total}
                        </p>
                        <div className="flex gap-2">
                            <button
                                type="button"
                                onClick={() => setPage(p => Math.max(0, p - 1))}
                                disabled={!hasPrev}
                                className="px-3 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
                            >
                                Previous
                            </button>
                            <button
                                type="button"
                                onClick={() => setPage(p => p + 1)}
                                disabled={!hasNext}
                                className="px-3 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
                            >
                                Next
                            </button>
                        </div>
                    </div>
                )}
            </div>
        </div>
    )
}
