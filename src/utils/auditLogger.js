import { supabase } from '../lib/supabase'

/**
 * Logs an audit event to the audit_logs table.
 * @param {string} recordId - The ID of the record being modified.
 * @param {string} tableName - The name of the table (e.g., 'tickets').
 * @param {string} action - 'INSERT', 'UPDATE', or 'DELETE'.
 * @param {string} performedBy - UUID of the user performing the action.
 * @param {object} changes - Object containing oldData, newData, and changedFields.
 * @param {object} changes.oldData - The previous state of the record.
 * @param {object} changes.newData - The new state of the record.
 * @param {string[]} changes.changedFields - Array of field names that changed.
 */
export async function logAuditEvent(recordId, tableName, action, performedBy, { oldData, newData, changedFields }) {
    if (!performedBy) {
        console.error('Audit Log Error: performedBy (user ID) is required.')
        return
    }

    try {
        const { error } = await supabase
            .from('audit_logs')
            .insert([
                {
                    record_id: recordId,
                    table_name: tableName,
                    action: action,
                    performed_by: performedBy,
                    old_data: oldData,
                    new_data: newData,
                    changed_fields: changedFields
                }
            ])

        if (error) {
            console.error('Error logging audit event:', error)
        }
    } catch (err) {
        console.error('Unexpected error logging audit event:', err)
    }
}
