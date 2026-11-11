import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Keep this in sync when a module adds OR drops a table. It has drifted twice: eight
// tables behind (the whole scrap module plus outsource invoices), and later a phantom
// `sla_rules` left over after MAIN-47 dropped it. A table missing from here is still
// left out quietly, and that direction costs real data; a phantom now fails the run.
// MAIN-33 would replace this with dynamic discovery; until it lands, this list is manual.
const TABLES = [
  'sites', 'users', 'user_sites', 'user_settings', 'user_audit_logs',
  'vehicles', 'vehicle_sites',
  'tickets', 'issues', 'job_cards', 'issue_parts', 'issue_labour',
  'parts', 'part_units', 'purchase_invoices', 'purchase_invoice_items',
  'finance_entries', 'sla_rules_config', 'sla_events',
  'holidays', 'system_settings', 'suppliers', 'audit_logs',
  // Scrap / salvage
  'scrap_inventory', 'scrap_disposal', 'scrap_disposal_items',
  'scrap_writeoff', 'scrap_writeoff_items', 'scrap_excluded_parts',
  'scrap_refurbishments', 'refurbished_part_links',
  // Outsource invoices (per-invoice payments went in MAIN-118) and the supplier ledger (MAIN-119)
  'outsource_invoices', 'supplier_payments', 'supplier_ledger_adjustments', 'advance_repayments',
  // Multi-vehicle outsource invoices (MAIN-99)
  'batch_services', 'batch_service_vehicles',
  // Workshop locations
  'workshop_locations', 'site_workshops', 'part_stock', 'stock_transfers', 'stock_transfer_items',
  // Stock audits
  'stock_audits', 'stock_audit_items', 'stock_audit_item_reasons',
]

// Batches are ordered by primary key, so each table not keyed on `id` must be listed here.
const PRIMARY_KEYS: Record<string, string[]> = {
  part_stock: ['part_id', 'location_id'],
  refurbished_part_links: ['refurbished_part_id'],
  site_workshops: ['site_id'],
  system_settings: ['key'],
  user_settings: ['user_id'],
  vehicle_sites: ['vehicle_id', 'site_name'],
}

// Must not exceed the API's Max rows: a short batch is read as the end of the table.
const PAGE_SIZE = 1000
const RETENTION_DAYS = 7

// One request returns at most Max rows and says nothing about the rest, so read in batches.
// A row inserted mid-read shifts the next batch by one, hence the de-duplication.
async function readAllRows(
  supabase: ReturnType<typeof createClient>,
  table: string,
): Promise<Record<string, unknown>[]> {
  const keys = PRIMARY_KEYS[table] ?? ['id']
  const rows = new Map<string, Record<string, unknown>>()

  for (let from = 0; ; from += PAGE_SIZE) {
    let query = supabase.from(table).select('*')
    for (const key of keys) query = query.order(key)

    const { data, error } = await query.range(from, from + PAGE_SIZE - 1)
    if (error) throw new Error(error.message)

    for (const row of (data ?? []) as Record<string, unknown>[]) {
      rows.set(keys.map(key => row[key]).join('|'), row)
    }
    if (!data || data.length < PAGE_SIZE) return [...rows.values()]
  }
}

Deno.serve(async () => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Dump every table
    const backup: Record<string, unknown[]> = {}
    const failedTables: Record<string, string> = {}
    for (const table of TABLES) {
      try {
        backup[table] = await readAllRows(supabase, table)
      } catch (err) {
        console.error(`Failed to read ${table}:`, String(err))
        failedTables[table] = String(err)
      }
    }

    const now = new Date()
    const label = now.toISOString().replace(/[:.]/g, '-')
    const fileName = `nvs-backup-${label}.json`
    const content = JSON.stringify(
      { backed_up_at: now.toISOString(), tables: backup, failed_tables: failedTables },
      null,
      2,
    )

    const accessToken = await getGoogleAccessToken(
      Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL')!,
      Deno.env.get('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY')!.replace(/\\n/g, '\n'),
    )

    const folderId = Deno.env.get('BACKUP_DRIVE_FOLDER_ID')!

    await deleteOldBackups(accessToken, folderId)
    await uploadToDrive(accessToken, folderId, fileName, content)

    // A partial backup is still uploaded, since it beats none, but the run reports failure.
    const ok = Object.keys(failedTables).length === 0
    const rows = Object.fromEntries(Object.entries(backup).map(([table, r]) => [table, r.length]))
    console.log(`Backup ${ok ? 'complete' : 'incomplete'}: ${fileName} (${content.length} chars)`)
    return new Response(JSON.stringify({ ok, file: fileName, rows, failed_tables: failedTables }), {
      status: ok ? 200 : 500,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('Backup failed:', err)
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})

// ── Google auth ───────────────────────────────────────────────────────────────

function pemToBytes(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '')
  return Uint8Array.from(atob(b64), c => c.charCodeAt(0))
}

function b64url(s: string): string {
  return btoa(s).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

async function getGoogleAccessToken(email: string, pem: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header  = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = b64url(JSON.stringify({
    iss: email,
    scope: 'https://www.googleapis.com/auth/drive',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }))

  const key = await crypto.subtle.importKey(
    'pkcs8', pemToBytes(pem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false, ['sign'],
  )
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5', key,
    new TextEncoder().encode(`${header}.${payload}`),
  )
  const jwt = `${header}.${payload}.${b64url(String.fromCharCode(...new Uint8Array(sig)))}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  })
  const { access_token } = await res.json()
  return access_token
}

// ── Drive operations ──────────────────────────────────────────────────────────

async function deleteOldBackups(token: string, folderId: string) {
  const cutoff = new Date(Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000).toISOString()
  const q = encodeURIComponent(
    `'${folderId}' in parents and trashed = false and createdTime < '${cutoff}'`
  )
  const res = await fetch(
    `https://www.googleapis.com/drive/v3/files?q=${q}&fields=files(id,name)&supportsAllDrives=true&includeItemsFromAllDrives=true`,
    { headers: { Authorization: `Bearer ${token}` } },
  )
  const { files = [] } = await res.json()
  for (const file of files) {
    await fetch(`https://www.googleapis.com/drive/v3/files/${file.id}?supportsAllDrives=true`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${token}` },
    })
    console.log(`Deleted old backup: ${file.name}`)
  }
}

async function uploadToDrive(token: string, folderId: string, name: string, content: string) {
  const boundary = 'nvs_backup_boundary'
  const body = [
    `--${boundary}`,
    'Content-Type: application/json; charset=UTF-8',
    '',
    JSON.stringify({ name, parents: [folderId], mimeType: 'application/json' }),
    `--${boundary}`,
    'Content-Type: application/json',
    '',
    content,
    `--${boundary}--`,
  ].join('\r\n')

  const res = await fetch(
    'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true',
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': `multipart/related; boundary="${boundary}"`,
      },
      body,
    },
  )
  if (!res.ok) throw new Error(`Drive upload failed: ${await res.text()}`)
}
