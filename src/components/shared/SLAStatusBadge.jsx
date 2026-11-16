import { formatDateTime } from '../../utils/datetime'
import { SLA_STATUS_LABELS, SLA_STATUS_STYLES } from '../../utils/slaStatus'

/**
 * An issue's own SLA status as stored by refresh_ticket_sla (MAIN-135), with its deadline
 * in the tooltip.
 */
export default function SLAStatusBadge({ status, deadline, className = '' }) {
    if (!status) return null
    return (
        <span
            title={deadline ? `Deadline ${formatDateTime(deadline)}` : undefined}
            className={`inline-block text-xs font-medium px-2 py-0.5 rounded border whitespace-nowrap ${SLA_STATUS_STYLES[status] || SLA_STATUS_STYLES.NA} ${className}`}
        >
            {status === 'NA' ? SLA_STATUS_LABELS.NA : `SLA ${SLA_STATUS_LABELS[status] || status}`}
        </span>
    )
}
