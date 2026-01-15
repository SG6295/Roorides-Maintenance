import { formatDistanceToNow } from 'date-fns'
import { useSLAEvents } from '../../hooks/useSLA'
import { useAuditLogs } from '../../hooks/useAuditLogs'

export default function TicketTimeline({ ticketId }) {
    const { data: slaEvents, isLoading: loadingSLA } = useSLAEvents(ticketId)
    const { data: auditLogs, isLoading: loadingAudit } = useAuditLogs(ticketId)

    if (loadingSLA || loadingAudit) return <div className="text-sm text-gray-500">Loading history...</div>

    // Merge and sort events
    const combinedEvents = [
        ...(slaEvents || []).map(e => ({ ...e, type: 'SLA' })),
        ...(auditLogs || []).map(e => ({ ...e, type: 'AUDIT' }))
    ].sort((a, b) => {
        const dateA = new Date(a.created_at || a.performed_at)
        const dateB = new Date(b.created_at || b.performed_at)
        return dateB - dateA // Descending
    })

    if (combinedEvents.length === 0) return <div className="text-sm text-gray-500 italic">No history recorded</div>

    return (
        <div className="flow-root">
            <ul role="list" className="-mb-8">
                {combinedEvents.map((event, eventIdx) => {
                    const isSLA = event.type === 'SLA'
                    const date = event.created_at || event.performed_at
                    const user = isSLA ? event.created_by_user : event.performed_by_user

                    return (
                        <li key={event.id}>
                            <div className="relative pb-8">
                                {eventIdx !== combinedEvents.length - 1 ? (
                                    <span className="absolute top-4 left-4 -ml-px h-full w-0.5 bg-gray-200" aria-hidden="true" />
                                ) : null}
                                <div className="relative flex space-x-3">
                                    <div>
                                        <span className={`h-8 w-8 rounded-full flex items-center justify-center ring-8 ring-white ${getEventColor(event)}`}>
                                            {getEventIcon(event)}
                                        </span>
                                    </div>
                                    <div className="flex min-w-0 flex-1 justify-between space-x-4 pt-1.5">
                                        <div>
                                            <p className="text-sm text-gray-500">
                                                {getEventLabel(event)}{' '}
                                                <span className="font-medium text-gray-900">
                                                    {user?.name || 'Unknown User'}
                                                </span>
                                            </p>
                                            <p className="text-xs text-gray-400 mt-0.5 whitespace-pre-wrap">
                                                {formatMetadata(event)}
                                            </p>
                                        </div>
                                        <div className="whitespace-nowrap text-right text-sm text-gray-500">
                                            <time dateTime={date} title={new Date(date).toLocaleString()}>
                                                {formatDistanceToNow(new Date(date), { addSuffix: true })}
                                            </time>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </li>
                    )
                })}
            </ul>
        </div>
    )
}

function getEventColor(event) {
    if (event.type === 'SLA') {
        switch (event.event_type) {
            case 'CREATED': return 'bg-gray-400'
            case 'ASSIGNED': return 'bg-blue-500'
            case 'COMPLETED': return 'bg-green-500'
            case 'REJECTED': return 'bg-red-500'
            default: return 'bg-blue-300' // STATUS_CHANGE
        }
    } else {
        // Audit
        return 'bg-gray-300'
    }
}

function getEventIcon(event) {
    if (event.type === 'SLA') {
        switch (event.event_type) {
            case 'CREATED': return '📝'
            case 'ASSIGNED': return '👤'
            case 'COMPLETED': return '✅'
            case 'REJECTED': return '❌'
            default: return '🔄'
        }
    } else {
        return '✏️' // Audit Edit
    }
}

function getEventLabel(event) {
    if (event.type === 'SLA') {
        switch (event.event_type) {
            case 'CREATED': return 'Created by'
            case 'ASSIGNED': return 'Assigned by'
            case 'COMPLETED': return 'Completed by'
            case 'REJECTED': return 'Rejected by'
            case 'STATUS_CHANGE': return 'Status updated by'
            default: return 'Updated by'
        }
    } else {
        return 'Edited by'
    }
}

function formatMetadata(event) {
    if (event.type === 'SLA') {
        if (event.event_type === 'STATUS_CHANGE' && event.metadata.oldStatus && event.metadata.newStatus) {
            return `${event.metadata.oldStatus} → ${event.metadata.newStatus}`
        }
    } else {
        // Audit Log
        if (event.changed_fields && event.changed_fields.length > 0) {
            return event.changed_fields.map(field => {
                const oldVal = event.old_data?.[field]
                const newVal = event.new_data?.[field]
                // Truncate long values
                const formatVal = (v) => {
                    if (v === null || v === undefined) return 'Empty'
                    const s = String(v)
                    return s.length > 30 ? s.substring(0, 30) + '...' : s
                }
                return `${formatFieldName(field)}: ${formatVal(oldVal)} → ${formatVal(newVal)}`
            }).join('\n')
        }
    }
    return ''
}

function formatFieldName(field) {
    return field
        .replace(/_/g, ' ')
        .replace(/\b\w/g, l => l.toUpperCase())
}
