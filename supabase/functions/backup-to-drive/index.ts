import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Keep this in sync when a module adds tables. It had already drifted eight tables
// behind (the whole scrap module plus outsource invoices) before this was noticed —
// MAIN-33 replaces it with dynamic discovery so it cannot silently fall behind again.
const TABLES = [
  'sites', 'users', 'user_sites', 'user_settings',
  'vehicles', 'vehicle_sites',
  'tickets', 'issues', 'job_cards', 'issue_parts',
  'parts', 'part_units', 'purchase_invoices', 'purchase_invoice_items',
  'finance_entries', 'sla_rules', 'sla_rules_config', 'sla_events',
  'holidays', 'system_settings', 'suppliers', 'audit_logs',
  // Scrap / salvage
  'scrap_inventory', 'scrap_disposal', 'scrap_disposal_items',
  'scrap_writeoff', 'scrap_writeoff_items', 'scrap_excluded_parts',
  // Outsource invoice payments
  'outsource_invoices', 'outsource_invoice_payments',
  // Workshop locations
  'workshop_locations', 'part_stock', 'stock_transfers', 'stock_transfer_items',
]

const RETENTION_DAYS = 7

Deno.serve(async () => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Dump every table
    const backup: Record<string, unknown[]> = {}
    for (const table of TABLES) {
      const { data, error } = await supabase.from(table).select('*')
      if (error) {
        console.error(`Failed to read ${table}:`, error.message)
        backup[table] = []
      } else {
        backup[table] = data ?? []
      }
    }

    const now = new Date()
    const label = now.toISOString().replace(/[:.]/g, '-')
    const fileName = `nvs-backup-${label}.json`
    const content = JSON.stringify({ backed_up_at: now.toISOString(), tables: backup }, null, 2)

    const accessToken = await getGoogleAccessToken(
      Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL')!,
      Deno.env.get('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY')!.replace(/\\n/g, '\n'),
    )

    const folderId = Deno.env.get('BACKUP_DRIVE_FOLDER_ID')!

    await deleteOldBackups(accessToken, folderId)
    await uploadToDrive(accessToken, folderId, fileName, content)

    console.log(`Backup complete: ${fileName}`)
    return new Response(JSON.stringify({ ok: true, file: fileName }), {
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
