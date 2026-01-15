import { supabase } from '../lib/supabase'

export const SLA_EVENTS = {
    CREATED: 'CREATED',
    ASSIGNED: 'ASSIGNED',
    COMPLETED: 'COMPLETED',
    STATUS_CHANGE: 'STATUS_CHANGE',
    REJECTED: 'REJECTED'
}

/**
 * Logs an SLA event to the database
 * @param {string} ticketId - UUID of the ticket
 * @param {string} eventType - One of SLA_EVENTS
 * @param {string} userId - UUID of the user performing the action
 * @param {object} metadata - Optional metadata (e.g. { oldStatus, newStatus, remarks })
 */
export async function logSLAEvent(ticketId, eventType, userId, metadata = {}) {
    try {
        const { error } = await supabase
            .from('sla_events')
            .insert({
                ticket_id: ticketId,
                event_type: eventType,
                created_by: userId,
                metadata
            })

        if (error) throw error
        return true
    } catch (err) {
        console.error('Failed to log SLA event:', err)
        // Non-blocking error - we don't want to stop the main action if logging fails
        return false
    }
}
