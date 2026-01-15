
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const supabase = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // 1. Get users who desire the digest
        const { data: userSettings, error: settingsError } = await supabase
            .from('user_settings')
            .select('user_id, digest_preferences')
            .eq('notify_daily_digest', true)

        if (settingsError) throw settingsError

        const { data: users, error: usersError } = await supabase
            .from('users') // active users to get email
            .select('id, email, name')
            .in('id', userSettings.map(s => s.user_id))

        if (usersError) throw usersError

        const results = []

        // 2. Loop and generate report for each user
        for (const user of users) {
            const settings = userSettings.find(s => s.user_id === user.id)
            const prefs = settings.digest_preferences || {}
            let htmlContent = `<h2>Daily Maintenance Digest for ${user.name}</h2>`
            let hasContent = false

            // A. Expiring SLA
            if (prefs.sla_expiring) {
                const tomorrow = new Date()
                tomorrow.setDate(tomorrow.getDate() + 1)

                const { data: expiring } = await supabase
                    .from('tickets')
                    .select('id, title, sla_due_at, status')
                    .or('status.eq.open,status.eq.pending')
                    .lt('sla_due_at', tomorrow.toISOString())
                    .gt('sla_due_at', new Date().toISOString())

                if (expiring && expiring.length > 0) {
                    hasContent = true
                    htmlContent += `<h3>⚠️ SLA Expiring in 24h</h3><ul>`
                    expiring.forEach(t => {
                        htmlContent += `<li><strong>#${t.id} ${t.title}</strong> - Due: ${new Date(t.sla_due_at).toLocaleString()}</li>`
                    })
                    htmlContent += `</ul>`
                }
            }

            // B. Rejected in last 24h
            if (prefs.rejected_24h) {
                const yesterday = new Date(Date.now() - 86400000).toISOString()
                const { data: rejected } = await supabase
                    .from('tickets')
                    .select('id, title, updated_at')
                    .eq('status', 'rejected')
                    .gt('updated_at', yesterday)

                if (rejected && rejected.length > 0) {
                    hasContent = true
                    htmlContent += `<h3>❌ Rejected Tickets (Last 24h)</h3><ul>`
                    rejected.forEach(t => {
                        htmlContent += `<li><strong>#${t.id} ${t.title}</strong></li>`
                    })
                    htmlContent += `</ul>`
                }
            }

            // C. Created in last 24h
            if (prefs.created_24h) {
                const yesterday = new Date(Date.now() - 86400000).toISOString()
                const { data: created } = await supabase
                    .from('tickets')
                    .select('id, title, created_at')
                    .gt('created_at', yesterday)

                if (created && created.length > 0) {
                    hasContent = true
                    htmlContent += `<h3>🆕 New Tickets (Last 24h)</h3><ul>`
                    created.forEach(t => {
                        htmlContent += `<li><strong>#${t.id} ${t.title}</strong></li>`
                    })
                    htmlContent += `</ul>`
                }
            }

            // Send Email if there is content
            if (hasContent) {
                const res = await fetch('https://api.resend.com/emails', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`
                    },
                    body: JSON.stringify({
                        from: 'NVS Maintenance <onboarding@resend.dev>', // Update this to verified domain if available
                        to: [user.email],
                        subject: `Daily Digest - ${new Date().toLocaleDateString()}`,
                        html: htmlContent
                    })
                })
                results.push({ email: user.email, status: res.status })
            } else {
                results.push({ email: user.email, status: 'No content' })
            }
        }

        return new Response(
            JSON.stringify({ success: true, results }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
