
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

// Mirrors the generated users.employee_key column (MAIN-143): "NVS 1234", "nvs-1234"
// and "NVS1234" are the same employee ID.
const employeeKey = (id: string) => id.toLowerCase().replace(/[\s-]/g, '')

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
            .select('role, name')
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

        // Employee ID is mandatory and unique ignoring case, spaces and hyphens
        // (MAIN-143). Checked before the auth user exists, so a clash leaves nothing behind.
        const employeeId = String(employee_id ?? '').trim()
        if (!employeeId) {
            return new Response(
                JSON.stringify({ error: 'Employee ID is required' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }
        const { data: idClash } = await adminClient
            .from('users')
            .select('id, name')
            .eq('employee_key', employeeKey(employeeId))
            .maybeSingle()
        if (idClash) {
            return new Response(
                JSON.stringify({ error: `Employee ID ${employeeId} is already used by ${idClash.name}` }),
                { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

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
                employee_id: employeeId,
                contact: contact || null,
                is_active: true
            }])

        if (profileError) {
            console.error('Profile creation failed:', profileError)
            // Another save took the same employee ID after the check above: remove the
            // auth user so the address can be retried.
            if (profileError.code === '23505' && /employee_key/.test(profileError.message)) {
                await adminClient.auth.admin.deleteUser(userId)
                return new Response(
                    JSON.stringify({ error: `Employee ID ${employeeId} is already in use` }),
                    { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
                )
            }
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

        // 4. Audit trail — starts the user's history at creation. Never records the
        //    password. A failure here must not undo a successful account creation.
        let siteNames: string[] = []
        if (role === 'supervisor' && sites?.length > 0) {
            const { data: siteRows } = await adminClient
                .from('sites')
                .select('name')
                .in('id', sites)
            siteNames = (siteRows ?? []).map((s: { name: string }) => s.name).sort()
        }

        const { error: auditError } = await adminClient
            .from('user_audit_logs')
            .insert([{
                target_user_id: userId,
                target_name: name,
                target_email: email,
                action: 'CREATE',
                changed_fields: ['name', 'email', 'role', 'employee_id', 'contact', 'sites'],
                old_data: {},
                new_data: {
                    name,
                    email,
                    role,
                    employee_id: employeeId,
                    contact: contact || null,
                    sites: siteNames,
                },
                performed_by: callerUser.id,
                performed_by_name: callerProfile.name ?? '',
            }])

        if (auditError) console.error('Audit log write failed:', auditError)

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
