
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    // Handle CORS preflight requests
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const { to, subject, html, text } = await req.json()

        if (!to || !subject || (!html && !text)) {
            return new Response(
                JSON.stringify({ error: 'Missing required fields (to, subject, html/text)' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const res = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${Deno.env.get('RESEND_API_KEY')}`
            },
            body: JSON.stringify({
                from: 'NVS Maintenance <onboarding@resend.dev>', // Use default testing domain for now
                to: Array.isArray(to) ? to : [to],
                subject: subject,
                html: html,
                text: text
            })
        })

        const data = await res.json()

        if (!res.ok) {
            console.error('Resend API Error:', data)
            return new Response(
                JSON.stringify({ error: data }),
                { status: res.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        return new Response(
            JSON.stringify(data),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
