
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Roles a given creator role is allowed to create
const CREATABLE_ROLES: Record<string, string[]> = {
    super_admin: ['super_admin', 'maintenance_exec', 'finance', 'supervisor', 'mechanic', 'electrician'],
    maintenance_exec: ['supervisor', 'mechanic', 'electrician'],
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const authHeader = req.headers.get('Authorization')
        if (!authHeader) {
            return new Response(
                JSON.stringify({ error: 'Missing authorization header' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Identify caller
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

        if (callerProfileError || !callerProfile) {
            return new Response(
                JSON.stringify({ error: 'Unauthorized' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const callerRole = callerProfile.role as string
        const allowedToCreate = CREATABLE_ROLES[callerRole]

        if (!allowedToCreate) {
            return new Response(
                JSON.stringify({ error: 'Forbidden: your role cannot create users' }),
                { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const { email, password, name, role, sites, employee_id, contact } = await req.json()

        if (!email || !password || !name || !role) {
            return new Response(
                JSON.stringify({ error: 'Missing required fields' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        if (!allowedToCreate.includes(role)) {
            return new Response(
                JSON.stringify({ error: `Forbidden: ${callerRole} cannot create a ${role}` }),
                { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        if (role === 'supervisor' && (!sites || sites.length === 0)) {
            return new Response(
                JSON.stringify({ error: 'Supervisor must have at least one site assigned' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const adminClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // 1. Create auth user
        const { data: newUser, error: createError } = await adminClient.auth.admin.createUser({
            email,
            password,
            email_confirm: true,
            user_metadata: { name, role }
        })

        if (createError) throw createError

        const userId = newUser.user.id

        // 2. Create public.users profile (site column left null — user_sites is authoritative)
        const { error: profileError } = await adminClient
            .from('users')
            .insert([{
                id: userId,
                email,
                name,
                role,
                site: null,
                employee_id: employee_id || null,
                contact: contact || null,
                is_active: true
            }])

        if (profileError) {
            console.error('Profile creation failed:', profileError)
            return new Response(
                JSON.stringify({ error: 'User created but profile sync failed', details: profileError }),
                { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // 3. Insert site assignments for supervisors
        if (role === 'supervisor' && sites?.length > 0) {
            const { error: sitesError } = await adminClient
                .from('user_sites')
                .insert(sites.map((siteId: string) => ({ user_id: userId, site_id: siteId })))

            if (sitesError) {
                console.error('Site assignment failed:', sitesError)
                return new Response(
                    JSON.stringify({ error: 'User created but site assignment failed', details: sitesError }),
                    { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                )
            }
        }

        return new Response(
            JSON.stringify({ user: newUser.user, message: 'User created successfully' }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
