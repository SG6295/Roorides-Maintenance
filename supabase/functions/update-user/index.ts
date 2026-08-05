
// Edits an existing user, or flips their active status.
//
// Both mutation paths for public.users live here rather than in the browser, for
// two reasons: changing another user's auth email or password is only possible
// with the service-role key, and the "Execs can update users" RLS policy cannot
// distinguish maintenance_exec from super_admin (is_maintenance_exec() returns
// true for both), so role scoping has to be enforced in code.
//
// Known limitation: changing a password does NOT revoke the target's existing
// sessions. supabase-js v2's auth.admin.signOut takes a JWT, not a user id, so
// this function cannot force-logout anyone. The old session stays valid until its
// refresh token expires. The lever for immediate lockout is deactivating the user
// — useAuth signs out deactivated users on their next profile fetch.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const VALID_ROLES = ['super_admin', 'maintenance_exec', 'finance', 'supervisor', 'mechanic', 'electrician']

// Which target roles each caller role may activate/deactivate. Mirrors
// MANAGEABLE_BY in src/pages/Users.jsx. Full profile edits are super_admin-only
// and checked separately.
const MANAGEABLE_BY: Record<string, string[]> = {
    super_admin: ['super_admin', 'maintenance_exec', 'finance', 'supervisor', 'mechanic', 'electrician'],
    maintenance_exec: ['supervisor', 'mechanic', 'electrician'],
}

const MIN_PASSWORD_LENGTH = 8

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    const json = (body: unknown, status = 200) => new Response(
        JSON.stringify(body),
        { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

    try {
        // 1. Caller must present a token
        const authHeader = req.headers.get('Authorization')
        if (!authHeader) {
            return json({ error: 'Missing authorization header' }, 401)
        }

        const callerClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            { global: { headers: { Authorization: authHeader } } }
        )

        // 2. Identify the caller
        const { data: { user: callerUser }, error: callerAuthError } = await callerClient.auth.getUser()
        if (callerAuthError || !callerUser) {
            return json({ error: 'Unauthorized' }, 401)
        }

        // 3. Load the caller's profile (name is needed for the audit trail)
        const { data: callerProfile, error: callerProfileError } = await callerClient
            .from('users')
            .select('role, is_active, name')
            .eq('id', callerUser.id)
            .single()

        if (callerProfileError || !callerProfile) {
            return json({ error: 'Unauthorized' }, 401)
        }
        if (callerProfile.is_active === false) {
            return json({ error: 'Forbidden: your account is deactivated', code: 'FORBIDDEN' }, 403)
        }

        const callerRole = callerProfile.role as string

        // 4. Parse and sanity-check the request
        const body = await req.json()
        const { action, user_id } = body

        if (action !== 'update' && action !== 'set_active') {
            return json({ error: "action must be 'update' or 'set_active'", code: 'VALIDATION' }, 400)
        }
        if (!user_id) {
            return json({ error: 'Missing required fields', code: 'VALIDATION' }, 400)
        }

        // 5. Nobody edits themselves here — Profile.jsx covers own name/email/password
        if (user_id === callerUser.id) {
            return json({ error: 'You cannot edit your own account. Use the Profile page.', code: 'FORBIDDEN' }, 403)
        }

        const adminClient = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // 6. Load the target BEFORE authorising — set_active authorises against
        //    the target's current role, and the audit diff needs the old values.
        const { data: target, error: targetError } = await adminClient
            .from('users')
            .select('id, email, name, role, employee_id, contact, is_active')
            .eq('id', user_id)
            .maybeSingle()

        if (targetError || !target) {
            return json({ error: 'User not found', code: 'NOT_FOUND' }, 404)
        }

        // Writes one audit row. Never throws — a missing log line must not undo a
        // successful user change, but it does get surfaced in the function logs.
        const writeAuditLog = async (
            auditAction: string,
            changedFields: string[],
            oldData: Record<string, unknown>,
            newData: Record<string, unknown>,
        ) => {
            if (changedFields.length === 0) return
            const { error } = await adminClient.from('user_audit_logs').insert([{
                target_user_id: target.id,
                target_name: target.name ?? '',
                target_email: target.email ?? '',
                action: auditAction,
                changed_fields: changedFields,
                old_data: oldData,
                new_data: newData,
                performed_by: callerUser.id,
                performed_by_name: callerProfile.name ?? '',
            }])
            if (error) console.error('Audit log write failed:', error)
        }

        // 7. Authorise by mode
        if (action === 'set_active') {
            const manageable = MANAGEABLE_BY[callerRole] ?? []
            if (!manageable.includes(target.role)) {
                return json({ error: `Forbidden: ${callerRole} cannot manage a ${target.role}`, code: 'FORBIDDEN' }, 403)
            }

            const nextActive = body.is_active
            if (typeof nextActive !== 'boolean') {
                return json({ error: 'is_active must be a boolean', code: 'VALIDATION' }, 400)
            }

            const { error: toggleError } = await adminClient
                .from('users')
                .update({ is_active: nextActive })
                .eq('id', user_id)

            if (toggleError) {
                return json({ error: toggleError.message, code: 'PROFILE_UPDATE_FAILED' }, 500)
            }

            if (target.is_active !== nextActive) {
                await writeAuditLog(
                    nextActive ? 'ACTIVATE' : 'DEACTIVATE',
                    ['is_active'],
                    { is_active: target.is_active },
                    { is_active: nextActive },
                )
            }

            return json({ ok: true, user_id, is_active: nextActive })
        }

        // --- action === 'update' from here on: super_admin only ---
        if (callerRole !== 'super_admin') {
            return json({ error: 'Forbidden: only a super admin can edit users', code: 'FORBIDDEN' }, 403)
        }

        const { name, email, role, employee_id, contact, sites, password } = body

        // 8. Required fields
        if (!name || !email || !role) {
            return json({ error: 'Missing required fields', code: 'VALIDATION' }, 400)
        }

        // 9. Role must be one the DB constraint accepts. A super admin may assign
        //    any of them, including promoting to and demoting from super_admin —
        //    the self-edit block above guarantees one super admin always survives.
        if (!VALID_ROLES.includes(role)) {
            return json({ error: `Invalid role: ${role}`, code: 'VALIDATION' }, 400)
        }

        // 10. Supervisors are RLS-scoped through user_sites, so they need at least one
        if (role === 'supervisor' && (!Array.isArray(sites) || sites.length === 0)) {
            return json({ error: 'Supervisor must have at least one site assigned', code: 'VALIDATION' }, 400)
        }
        const nextSites: string[] = role === 'supervisor' ? [...new Set(sites as string[])] : []

        // 11. Password is optional; absent/empty means "leave it alone"
        const nextPassword = typeof password === 'string' && password.length > 0 ? password : null
        if (nextPassword && nextPassword.length < MIN_PASSWORD_LENGTH) {
            return json({ error: `Password must be at least ${MIN_PASSWORD_LENGTH} characters`, code: 'VALIDATION' }, 400)
        }

        // 12. Cheap pre-flight on email collisions. auth.users is the authoritative
        //     uniqueness store, so step A still handles the conflict it can't see.
        const nextEmail = String(email).trim().toLowerCase()
        const emailChanged = nextEmail !== String(target.email ?? '').toLowerCase()

        if (emailChanged) {
            const { data: clash } = await adminClient
                .from('users')
                .select('id')
                .eq('email', nextEmail)
                .neq('id', user_id)
                .maybeSingle()

            if (clash) {
                return json({ error: 'That email is already in use', code: 'EMAIL_TAKEN' }, 409)
            }
        }

        // A. Auth — only send what actually changed
        const authPayload: Record<string, unknown> = {}
        if (emailChanged) {
            // email_confirm is required: without it updateUserById stores a pending
            // new_email and mails a confirmation instead of changing the login.
            authPayload.email = nextEmail
            authPayload.email_confirm = true
        }
        if (nextPassword) {
            authPayload.password = nextPassword
        }
        if (name !== target.name || role !== target.role) {
            authPayload.user_metadata = { name, role }
        }

        if (Object.keys(authPayload).length > 0) {
            const { error: authUpdateError } = await adminClient.auth.admin.updateUserById(user_id, authPayload)
            if (authUpdateError) {
                if (/already been registered|already exists|duplicate/i.test(authUpdateError.message)) {
                    return json({ error: 'That email is already in use', code: 'EMAIL_TAKEN' }, 409)
                }
                return json({ error: authUpdateError.message, code: 'VALIDATION' }, 400)
            }
        }

        // B. Profile — is_active belongs to set_active, site is legacy and stays null
        const { error: profileError } = await adminClient
            .from('users')
            .update({
                email: nextEmail,
                name,
                role,
                employee_id: employee_id || null,
                contact: contact || null,
            })
            .eq('id', user_id)

        if (profileError) {
            console.error('Profile update failed:', profileError)
            // Put the auth email back so the login address and the profile agree.
            // A password change can't be undone (the old hash is gone), but since
            // it isn't mirrored in public.users the account stays self-consistent —
            // report it so the admin knows the new password is already live.
            if (emailChanged) {
                await adminClient.auth.admin.updateUserById(user_id, {
                    email: target.email,
                    email_confirm: true,
                })
            }
            return json({
                error: emailChanged
                    ? 'Profile update failed; the email change was rolled back'
                    : 'Profile update failed',
                code: 'PROFILE_UPDATE_FAILED',
                details: profileError,
                applied: { password_changed: !!nextPassword },
            }, 500)
        }

        // C. Sites — delete-then-insert. The unconditional delete is what clears
        //    stale rows when a supervisor is demoted to another role.
        const { data: previousSiteRows } = await adminClient
            .from('user_sites')
            .select('site_id, sites(name)')
            .eq('user_id', user_id)

        const { error: deleteSitesError } = await adminClient
            .from('user_sites')
            .delete()
            .eq('user_id', user_id)

        if (deleteSitesError) {
            console.error('Clearing site assignments failed:', deleteSitesError)
            return json({
                error: 'Profile updated but site assignment failed — reopen and re-assign sites',
                code: 'SITES_SYNC_FAILED',
                details: deleteSitesError,
            }, 500)
        }

        if (nextSites.length > 0) {
            const { error: sitesError } = await adminClient
                .from('user_sites')
                .insert(nextSites.map((siteId: string) => ({ user_id, site_id: siteId })))

            if (sitesError) {
                console.error('Site assignment failed:', sitesError)
                return json({
                    error: 'Profile updated but site assignment failed — reopen and re-assign sites',
                    code: 'SITES_SYNC_FAILED',
                    details: sitesError,
                }, 500)
            }
        }

        // D. Audit — site names rather than UUIDs so the UI renders without joins
        const oldSiteNames: string[] = (previousSiteRows ?? [])
            .map((row: { sites: { name: string } | null }) => row.sites?.name)
            .filter(Boolean)
            .sort()

        let newSiteNames: string[] = []
        if (nextSites.length > 0) {
            const { data: siteRows } = await adminClient
                .from('sites')
                .select('name')
                .in('id', nextSites)
            newSiteNames = (siteRows ?? []).map((s: { name: string }) => s.name).sort()
        }

        const changedFields: string[] = []
        const oldData: Record<string, unknown> = {}
        const newData: Record<string, unknown> = {}

        const track = (field: string, before: unknown, after: unknown) => {
            if (before === after) return
            changedFields.push(field)
            oldData[field] = before
            newData[field] = after
        }

        track('name', target.name, name)
        track('email', target.email, nextEmail)
        track('role', target.role, role)
        track('employee_id', target.employee_id ?? null, employee_id || null)
        track('contact', target.contact ?? null, contact || null)

        if (oldSiteNames.join('|') !== newSiteNames.join('|')) {
            changedFields.push('sites')
            oldData.sites = oldSiteNames
            newData.sites = newSiteNames
        }

        // The password itself is never stored — only the fact that it was reset.
        if (nextPassword) {
            changedFields.push('password')
        }

        await writeAuditLog('UPDATE', changedFields, oldData, newData)

        return json({
            ok: true,
            user_id,
            email_changed: emailChanged,
            password_changed: !!nextPassword,
            sites_changed: oldSiteNames.join('|') !== newSiteNames.join('|'),
        })

    } catch (error) {
        return json({ error: error.message }, 400)
    }
})
