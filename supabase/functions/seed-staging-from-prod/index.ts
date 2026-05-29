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

        // ── Phase A: Auth Users ──────────────────────────────────────────────

        const prodUsers: any[] = []
        let page = 1
        while (true) {
            const { data, error } = await prodAdmin.auth.admin.listUsers({ page, perPage: 1000 })
            if (error) throw new Error(`Failed to list prod users: ${error.message}`)
            prodUsers.push(...data.users)
            if (data.users.length < 1000) break
            page++
        }

        const { data: stagingUsersData, error: listError } = await stagingAdmin.auth.admin.listUsers({ perPage: 1000 })
        if (listError) throw new Error(`Failed to list staging users: ${listError.message}`)

        const deleteErrors: { id: string; email: string; error: string }[] = []
        for (const user of stagingUsersData.users) {
            // Skip the caller — deleting their account would invalidate their session
            if (user.id === callerUser.id) continue
            const { error } = await stagingAdmin.auth.admin.deleteUser(user.id)
            if (error) deleteErrors.push({ id: user.id, email: user.email ?? '', error: error.message })
        }

        const createErrors: { id: string; email: string; error: string }[] = []
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
                createErrors.push({ id: user.id, email: user.email ?? '', error: error.message })
            } else {
                usersCreated++
            }
        }

        // ── Phase B: Public Tables ───────────────────────────────────────────

        // 1. Get staging column map and FK deps via helper RPCs (staging only)
        const { data: stagingColRows, error: stagingColErr } = await stagingAdmin.rpc('seed_get_table_columns')
        if (stagingColErr) throw new Error(`Failed to get staging columns: ${stagingColErr.message}`)

        const stagingColMap = new Map<string, Set<string>>()
        for (const { table_name, column_name } of stagingColRows ?? []) {
            if (!stagingColMap.has(table_name)) stagingColMap.set(table_name, new Set())
            stagingColMap.get(table_name)!.add(column_name)
        }

        const { data: fkRows, error: fkErr } = await stagingAdmin.rpc('seed_get_fk_deps')
        if (fkErr) throw new Error(`Failed to get FK deps: ${fkErr.message}`)

        const fkDeps = new Map<string, Set<string>>()
        for (const { child_table, parent_table } of fkRows ?? []) {
            if (!fkDeps.has(child_table)) fkDeps.set(child_table, new Set())
            fkDeps.get(child_table)!.add(parent_table)
        }

        const allStagingTables = [...stagingColMap.keys()]
        const orderedTables = topoSort(allStagingTables, fkDeps)

        // 2. Truncate all staging public tables
        const { error: truncateErr } = await stagingAdmin.rpc('seed_truncate_public_tables')
        if (truncateErr) throw new Error(`Truncate failed: ${truncateErr.message}`)

        // 3. Insert prod data table by table in FK-safe order.
        //    select('*') from prod and filter to staging columns client-side —
        //    this way no helper functions are needed on prod.
        const tableResults: { table: string; rows_copied: number; status: string; error?: string }[] = []
        let totalRows = 0

        for (const table of orderedTables) {
            const stagingColumns = stagingColMap.get(table)!

            try {
                const allRows: any[] = []
                let offset = 0
                while (true) {
                    const { data, error } = await prodAdmin
                        .from(table)
                        .select('*')
                        .range(offset, offset + BATCH_SIZE - 1)

                    if (error) throw new Error(error.message)
                    if (!data || data.length === 0) break

                    // Filter each row to only columns that exist in staging
                    const filtered = data.map((row: any) =>
                        Object.fromEntries(
                            Object.entries(row).filter(([col]) => stagingColumns.has(col))
                        )
                    )
                    allRows.push(...filtered)
                    if (data.length < BATCH_SIZE) break
                    offset += BATCH_SIZE
                }

                for (let i = 0; i < allRows.length; i += BATCH_SIZE) {
                    const { error } = await stagingAdmin.from(table).insert(allRows.slice(i, i + BATCH_SIZE))
                    if (error) throw new Error(error.message)
                }

                tableResults.push({ table, rows_copied: allRows.length, status: 'ok' })
                totalRows += allRows.length
            } catch (err) {
                tableResults.push({ table, rows_copied: 0, status: 'error', error: err.message })
            }
        }

        return new Response(
            JSON.stringify({
                auth: {
                    users_found_in_prod: prodUsers.length,
                    users_copied: usersCreated,
                    test_password: TEST_PASSWORD,
                    errors: [...deleteErrors, ...createErrors],
                },
                public: tableResults,
                summary: {
                    tables_ok: tableResults.filter(t => t.status === 'ok').length,
                    tables_skipped: tableResults.filter(t => t.status === 'skipped').length,
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
