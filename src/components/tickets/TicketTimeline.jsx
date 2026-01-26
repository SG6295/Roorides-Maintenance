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
        // Audit - check if it's an issue-related event
        const actionType = event.old_data?._actionType

        switch (actionType) {
            case 'issue_linked_to_job_card': return 'bg-purple-500'
            case 'issue_unlinked_from_job_card': return 'bg-orange-400'
            default:
                // Check action type for issues
                if (event.table_name === 'issues') {
                    switch (event.action) {
                        case 'INSERT': return 'bg-green-400'
                        case 'DELETE': return 'bg-red-400'
                        default: return 'bg-blue-300'
                    }
                }
                return 'bg-gray-300'
        }
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
        // Audit - check if it's an issue-related event
        const actionType = event.old_data?._actionType

        switch (actionType) {
            case 'issue_linked_to_job_card': return '🔗'
            case 'issue_unlinked_from_job_card': return '🔓'
            default:
                // Check action type for issues
                if (event.table_name === 'issues') {
                    switch (event.action) {
                        case 'INSERT': return '🔧'
                        case 'DELETE': return '🗑️'
                        default: return '✏️'
                    }
                }
                return '✏️' // Default for ticket edits
        }
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
        // Audit - check if it's an issue-related event
        const actionType = event.old_data?._actionType

        switch (actionType) {
            case 'issue_linked_to_job_card': return 'Issue linked to Job Card by'
            case 'issue_unlinked_from_job_card': return 'Issue unlinked from Job Card by'
            default:
                // Check action type for issues
                if (event.table_name === 'issues') {
                    switch (event.action) {
                        case 'INSERT': return 'Issue created by'
                        case 'DELETE': return 'Issue deleted by'
                        default: return 'Issue edited by'
                    }
                }
                return 'Edited by'
        }
    }
}

function formatMetadata(event) {
    if (event.type === 'SLA') {
        if (event.event_type === 'STATUS_CHANGE' && event.metadata?.oldStatus && event.metadata?.newStatus) {
            return `${event.metadata.oldStatus} → ${event.metadata.newStatus}`
        }
    } else {
        // Audit Log
        const actionType = event.old_data?._actionType

        // Handle issue-specific events
        if (event.table_name === 'issues') {
            const issueNumber = event.new_data?.issue_number || event.old_data?.issue_number
            const description = event.new_data?.description || event.old_data?.description
            const truncatedDesc = description ? (description.length > 40 ? description.substring(0, 40) + '...' : description) : ''

            switch (actionType) {
                case 'issue_linked_to_job_card': {
                    const jobCardNumber = event.old_data?._jobCardNumber
                    return `${issueNumber ? issueNumber + ': ' : ''}${truncatedDesc}${jobCardNumber ? `\n→ Job Card #${jobCardNumber}` : ''}`
                }
                case 'issue_unlinked_from_job_card': {
                    const jobCardNumber = event.old_data?._jobCardNumber
                    return `${issueNumber ? issueNumber + ': ' : ''}${truncatedDesc}${jobCardNumber ? `\n← Removed from Job Card #${jobCardNumber}` : ''}`
                }
                default:
                    if (event.action === 'INSERT') {
                        return `${issueNumber ? issueNumber + ': ' : ''}${truncatedDesc}`
                    }
                    if (event.action === 'DELETE') {
                        return `${issueNumber ? issueNumber + ': ' : ''}${truncatedDesc}`
                    }
                    // For updates, show changed fields
                    if (event.changed_fields && event.changed_fields.length > 0) {
                        const fieldsToShow = event.changed_fields.filter(f => !f.startsWith('_'))
                        if (fieldsToShow.length > 0) {
                            return `${issueNumber ? issueNumber + ': ' : ''}${fieldsToShow.map(field => {
                                const oldVal = event.old_data?.[field]
                                const newVal = event.new_data?.[field]
                                const formatVal = (v) => {
                                    if (v === null || v === undefined) return 'Empty'
                                    const s = String(v)
                                    return s.length > 20 ? s.substring(0, 20) + '...' : s
                                }
                                return `${formatFieldName(field)}: ${formatVal(oldVal)} → ${formatVal(newVal)}`
                            }).join('\n')}`
                        }
                    }
                    return truncatedDesc
            }
        }

        // Default ticket audit formatting
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
