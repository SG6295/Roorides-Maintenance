import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const TEST_PASSWORD = 'NVSStaging2025!'
const BATCH_SIZE = 500

// Returns tables in parent-before-child order for safe inserts
function topoSort(tables: string[], deps: Map<string, Set<string>>): string[] {
    const visited = new Set<string>()
    const result: string[] = []

    function visit(table: string) {
        if (visited.has(table)) return
        visited.add(table)
        for (const parent of deps.get(table) ?? []) {
            if (tables.includes(parent)) visit(parent)
        }
        result.push(table)
    }

    for (const table of tables) visit(table)
    return result
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

        // Verify caller is super_admin
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

        if (callerProfileError || !callerProfile || callerProfile.role !== 'super_admin') {
            return new Response(
                JSON.stringify({ error: 'Forbidden: only super_admin can seed staging' }),
                { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        const stagingAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const prodAdmin = createClient(
            Deno.env.get('PROD_SUPABASE_URL') ?? '',
            Deno.env.get('PROD_SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        const startTime = Date.now()

        // Order matters (MAIN-139):
        //   1. read prod's logins
        //   2. empty staging's public tables — 29 FKs to public.users (and user_settings → auth.users)
        //      have no delete action, so a login with history can't be deleted before this
        //   3. delete staging logins, 4. recreate prod's, both skipping the caller
        //   5. copy the tables through seed_insert_rows, which keeps rows exactly as prod has them
        //      (no triggers, identities kept) — plain inserts re-derived stock, SLA and numbers
        const failures: { phase: string; item: string; error: string }[] = []

        // ── Phase A: read prod logins ────────────────────────────────────────

        const prodUsers: any[] = []
        let page = 1
        while (true) {
            const { data, error } = await prodAdmin.auth.admin.listUsers({ page, perPage: 1000 })
            if (error) throw new Error(`Failed to list prod users: ${error.message}`)
            prodUsers.push(...data.users)
            if (data.users.length < 1000) break
            page++
        }

        // ── Phase B: staging metadata, then empty the public tables ──────────

        const { data: stagingColRows, error: stagingColErr } = await stagingAdmin.rpc('seed_get_table_columns')
        if (stagingColErr) throw new Error(`Failed to get staging columns: ${stagingColErr.message}`)

        const stagingTables = new Set<string>()
        for (const { table_name } of stagingColRows ?? []) stagingTables.add(table_name)

        const { data: fkRows, error: fkErr } = await stagingAdmin.rpc('seed_get_fk_deps')
        if (fkErr) throw new Error(`Failed to get FK deps: ${fkErr.message}`)

        const fkDeps = new Map<string, Set<string>>()
        for (const { child_table, parent_table } of fkRows ?? []) {
            if (!fkDeps.has(child_table)) fkDeps.set(child_table, new Set())
            fkDeps.get(child_table)!.add(parent_table)
        }

        const { data: pkRows, error: pkErr } = await stagingAdmin.rpc('seed_get_primary_keys')
        if (pkErr) throw new Error(`Failed to get primary keys: ${pkErr.message}`)

        const primaryKeys = new Map<string, string[]>()
        for (const { table_name, column_name } of pkRows ?? []) {
            if (!primaryKeys.has(table_name)) primaryKeys.set(table_name, [])
            primaryKeys.get(table_name)!.push(column_name)
        }

        const orderedTables = topoSort([...stagingTables], fkDeps)

        // Refuses unless this database is marked as staging (seed_assert_staging)
        const { error: truncateErr } = await stagingAdmin.rpc('seed_truncate_public_tables')
        if (truncateErr) throw new Error(`Truncate failed: ${truncateErr.message}`)

        // ── Phase C: replace staging logins ──────────────────────────────────

        const stagingUsers: any[] = []
        page = 1
        while (true) {
            const { data, error } = await stagingAdmin.auth.admin.listUsers({ page, perPage: 1000 })
            if (error) throw new Error(`Failed to list staging users: ${error.message}`)
            stagingUsers.push(...data.users)
            if (data.users.length < 1000) break
            page++
        }

        for (const user of stagingUsers) {
            // Skip the caller — deleting their account would invalidate their session
            if (user.id === callerUser.id) continue
            const { error } = await stagingAdmin.auth.admin.deleteUser(user.id)
            if (error) failures.push({ phase: 'login delete', item: user.email ?? user.id, error: error.message })
        }

        let usersCreated = 0
        for (const user of prodUsers) {
            // Skip the caller — their account already exists and session is active
            if (user.id === callerUser.id) continue
            const { error } = await stagingAdmin.auth.admin.createUser({
                id: user.id,
                email: user.email ?? '',
                password: TEST_PASSWORD,
                email_confirm: true,
                user_metadata: user.user_metadata ?? {},
            })
            if (error) {
                failures.push({ phase: 'login create', item: user.email ?? user.id, error: error.message })
            } else {
                usersCreated++
            }
        }

        // ── Phase D: copy public tables ──────────────────────────────────────

        // Parent-before-child order is kept even though seed_insert_rows skips FK checks,
        // so a half-finished copy never leaves orphans behind.
        const tableResults: { table: string; rows_copied: number; status: string; error?: string }[] = []
        let totalRows = 0

        for (const table of orderedTables) {
            let copied = 0
            try {
                let offset = 0
                while (true) {
                    // Ordered by primary key — paging an unordered read can skip or repeat rows
                    let query = prodAdmin.from(table).select('*')
                    for (const col of primaryKeys.get(table) ?? []) query = query.order(col, { ascending: true })
                    const { data, error } = await query.range(offset, offset + BATCH_SIZE - 1)

                    if (error) throw new Error(error.message)
                    if (!data || data.length === 0) break

                    // seed_insert_rows drops columns staging lacks and generated columns itself
                    const { data: inserted, error: insertErr } = await stagingAdmin.rpc('seed_insert_rows', {
                        p_table: table,
                        p_rows: data,
                    })
                    if (insertErr) throw new Error(insertErr.message)
                    copied += inserted ?? 0

                    if (data.length < BATCH_SIZE) break
                    offset += BATCH_SIZE
                }

                tableResults.push({ table, rows_copied: copied, status: 'ok' })
                totalRows += copied
            } catch (err) {
                tableResults.push({ table, rows_copied: copied, status: 'error', error: err.message })
                failures.push({ phase: 'table', item: table, error: err.message })
            }
        }

        return new Response(
            JSON.stringify({
                auth: {
                    users_found_in_prod: prodUsers.length,
                    users_copied: usersCreated,
                    test_password: TEST_PASSWORD,
                },
                public: tableResults,
                failures,
                summary: {
                    tables_ok: tableResults.filter(t => t.status === 'ok').length,
                    tables_failed: tableResults.filter(t => t.status === 'error').length,
                    total_rows_copied: totalRows,
                    duration_ms: Date.now() - startTime,
                },
            }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
