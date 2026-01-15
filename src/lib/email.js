
import { supabase } from './supabase'

/**
 * Sends an email using the 'send-email' Edge Function (Resend).
 * @param {Object} params
 * @param {string|string[]} params.to - Recipient email(s)
 * @param {string} params.subject - Email subject
 * @param {string} params.html - HTML content (optional)
 * @param {string} params.text - Text content (optional)
 * @returns {Promise<{success: boolean, data?: any, error?: any}>}
 */
export async function sendEmail({ to, subject, html, text }) {
    try {
        const { data, error } = await supabase.functions.invoke('send-email', {
            body: { to, subject, html, text }
        })

        if (error) throw error
        return { success: true, data }

    } catch (err) {
        console.error('Failed to send email:', err)
        return { success: false, error: err }
    }
}
