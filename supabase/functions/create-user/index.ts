
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

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
        // Verify the caller is a maintenance_exec
        const authHeader = req.headers.get('Authorization')
        if (!authHeader) {
            return new Response(
                JSON.stringify({ error: 'Missing authorization header' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const callerClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            { global: { headers: { Authorization: authHeader } } }
        )

        const { data: { user: callerUser }, error: callerAuthError } = await callerClient.auth.getUser()
        if (callerAuthError || !callerUser) {
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const { data: callerProfile, error: callerProfileError } = await callerClient
            .from('users')
            .select('role')
            .eq('id', callerUser.id)
            .single()

        if (callerProfileError || callerProfile?.role !== 'maintenance_exec') {
            return new Response(
                JSON.stringify({ error: 'Forbidden: only maintenance_exec can create users' }),
                { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const supabaseClient = createClient(
            // Supabase API URL - env var automatically populated by Supabase
            Deno.env.get('SUPABASE_URL') ?? '',
            // Supabase Service Role Key - env var automatically populated by Supabase
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // Get the request body
        const { email, password, name, role, site, employee_id, contact } = await req.json()

        // Validate inputs
        if (!email || !password || !name || !role) {
            return new Response(
                JSON.stringify({ error: 'Missing required fields' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // 1. Create the user in Supabase Auth
        const { data: user, error: createError } = await supabaseClient.auth.admin.createUser({
            email,
            password,
            email_confirm: true, // Auto-confirm email
            user_metadata: { name, role, site }
        })

        if (createError) throw createError

        // 2. Create the user profile in public.users table (if not handled by triggers)
        // We do this explicitly to ensure all fields are set correctly immediately
        const { error: profileError } = await supabaseClient
            .from('users')
            .insert([
                {
                    id: user.user.id,
                    email,
                    name,
                    role,
                    site: site || null, // specific site for supervisors, null for mechanic/exec/finance
                    employee_id,
                    contact,
                    is_active: true
                }
            ])

        if (profileError) {
            // Rollback: delete the auth user if profile creation fails? 
            // ideally yes, but for now just report error
            console.error('Profile creation failed:', profileError)
            return new Response(
                JSON.stringify({ error: 'User created but profile sync failed', details: profileError }),
                { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        return new Response(
            JSON.stringify({ user: user.user, message: 'User created successfully' }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
