import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const ROORIDES_BASE_URL = 'https://api.roorides.com/api'

async function getRooridesToken(): Promise<string> {
  const username = Deno.env.get('ROORIDES_USERNAME')
  const password = Deno.env.get('ROORIDES_PASSWORD')

  if (!username || !password) {
    throw new Error('ROORIDES_USERNAME and ROORIDES_PASSWORD secrets are not set')
  }

  const res = await fetch(`${ROORIDES_BASE_URL}/login/UserLogin`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ UserName: username, Password: password, GrantType: 'Password' }),
  })

  if (!res.ok) throw new Error(`Roorides login failed: ${res.status} ${res.statusText}`)

  const data = await res.json()
  if (!data.accessToken) throw new Error('Roorides login response did not include an accessToken')
  return data.accessToken
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const orgId = Deno.env.get('ROORIDES_ORG_ID') ?? '137'

    // Step 1: authenticate with Roorides
    const token = await getRooridesToken()

    // Step 2: fetch all vehicles
    const res = await fetch(`${ROORIDES_BASE_URL}/Vehicle/GetAllVehicles/${orgId}`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    })

    if (!res.ok) throw new Error(`Roorides GetAllVehicles failed: ${res.status} ${res.statusText}`)

    const raw = await res.json()

    // Step 3: normalise to our vehicles table shape.
    // Field mapping confirmed from Roorides API response:
    //   registerNumber → registration_number
    //   modelName      → model
    //   make           → make
    //   vehicleType    → type
    //   status         → is_active (Active = true)
    //   school         → vehicle_sites (synced separately below)
    // raw_data stores the full payload so future features can access any field.
    const vehicles = (Array.isArray(raw) ? raw : [])
      .map((v: Record<string, unknown>) => ({
        registration_number: (v.registerNumber ?? '') as string,
        make: (v.make ?? null) as string | null,
        model: (v.modelName ?? null) as string | null,
        type: (v.vehicleType ?? null) as string | null,
        is_active: v.status === 'Active',
        raw_data: v,
      }))
      .filter((v: { registration_number: string }) => v.registration_number.trim() !== '')

    // Deduplicate by registration_number — Postgres rejects upserting the same row twice in one batch
    const seen = new Set<string>()
    const uniqueVehicles = vehicles.filter((v: { registration_number: string }) => {
      if (seen.has(v.registration_number)) return false
      seen.add(v.registration_number)
      return true
    })

    if (uniqueVehicles.length === 0) {
      throw new Error('Roorides returned 0 vehicles — aborting to avoid wiping local data')
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // Step 4: upsert sites from school field (add only, never delete existing).
    // school is a single string per vehicle (e.g. "ILB", "MMS") but split by comma
    // just in case future API changes return multiple values.
    const allSiteNames = new Set<string>()
    for (const v of uniqueVehicles) {
      const school = ((v.raw_data as Record<string, unknown>)?.school ?? '') as string
      school.split(',').map(s => s.trim()).filter(s => s.length > 0).forEach(s => allSiteNames.add(s))
    }

    if (allSiteNames.size > 0) {
      // Insert only the name — other columns use DB defaults (is_active defaults to true).
      // ON CONFLICT (name) DO UPDATE SET name = name is effectively a no-op for existing rows,
      // preserving any manual is_active changes made locally.
      const siteRows = [...allSiteNames].map(name => ({ name }))
      const { error: sitesError } = await supabase
        .from('sites')
        .upsert(siteRows, { onConflict: 'name' })
      if (sitesError) throw sitesError
    }

    // Step 5: upsert vehicles into local vehicles table (bypasses RLS via service role).
    // onConflict: 'registration_number' — existing rows updated, new rows inserted.
    const { data: upsertedVehicles, error: vehicleError } = await supabase
      .from('vehicles')
      .upsert(uniqueVehicles, { onConflict: 'registration_number' })
      .select('id, registration_number')

    if (vehicleError) throw vehicleError

    // Step 6: sync vehicle_sites — replace each vehicle's site associations with
    // the current school value from Roorides. This handles reassignments:
    // delete the vehicle's old associations then insert the current ones.
    const regToId = new Map((upsertedVehicles ?? []).map(v => [v.registration_number, v.id]))
    const vehicleSitesRecords: Array<{ vehicle_id: string; site_name: string }> = []

    for (const v of uniqueVehicles) {
      const vehicleId = regToId.get(v.registration_number)
      if (!vehicleId) continue
      const school = ((v.raw_data as Record<string, unknown>)?.school ?? '') as string
      const uniqueSites = [...new Set(school.split(',').map(s => s.trim()).filter(s => s.length > 0))]
      for (const siteName of uniqueSites) {
        vehicleSitesRecords.push({ vehicle_id: vehicleId as string, site_name: siteName })
      }
    }

    // Delete all existing vehicle_sites before re-inserting.
    // We sync the full fleet every time so a full wipe + re-insert is correct
    // and avoids URL-length limits from filtering by 600+ vehicle IDs.
    const { error: deleteError } = await supabase
      .from('vehicle_sites')
      .delete()
      .not('vehicle_id', 'is', null)
    if (deleteError) throw deleteError

    if (vehicleSitesRecords.length > 0) {
      const { error: insertError } = await supabase
        .from('vehicle_sites')
        .insert(vehicleSitesRecords)
      if (insertError) throw insertError
    }

    console.log(`sync-roorides-vehicles: synced ${uniqueVehicles.length} vehicles, ${allSiteNames.size} sites, ${vehicleSitesRecords.length} vehicle-site associations`)

    return new Response(
      JSON.stringify({ success: true, synced: uniqueVehicles.length, sites: allSiteNames.size }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : (typeof error === 'object' && error !== null && 'message' in error)
        ? String((error as { message: unknown }).message)
        : String(error)
    console.error('sync-roorides-vehicles error:', error)
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
