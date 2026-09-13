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

/**
 * Short code → full school name, from the corporation mapping endpoint.
 *
 * The per-vehicle `schoolName` field cannot be used for this: it is an empty string on
 * every vehicle, and `school` is comma-separated ("VTS, CSS, TMS, DCTS") so several full
 * names could not be packed into it safely — real school names contain commas.
 *
 * corpShortName is unique across the full 0/0 result and is what the vehicle feed's
 * `school` field contains, so it is the join key. Duplicates are logged rather than
 * silently resolved, since a collision would mean that assumption has stopped holding.
 *
 * Returns an empty map on any failure. The names are cosmetic — failing the whole
 * vehicle sync, and with it the is_active bookkeeping, over a display lookup would do
 * far more damage than showing bare short codes for another day.
 */
async function fetchCorporations(token: string): Promise<Map<string, { name: string; corpId: number | null }>> {
  const byShortName = new Map<string, { name: string; corpId: number | null }>()

  try {
    const res = await fetch(`${ROORIDES_BASE_URL}/ManageCorp/GetAllCorporation/0/0`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    })

    if (!res.ok) {
      console.warn(`GetAllCorporation failed: ${res.status} ${res.statusText} — site names left unchanged`)
      return byShortName
    }

    const raw = await res.json()
    const rows = Array.isArray(raw) ? raw : []

    for (const c of rows as Array<Record<string, unknown>>) {
      const shortName = String(c.corpShortName ?? '').trim()
      const corpName = String(c.corpName ?? '').trim()
      if (!shortName || !corpName) continue

      // Keyed uppercase so an upstream casing change (the Agrata → AGRATA rename that
      // caused MAIN-48) does not silently drop the school's name. Safe to normalise
      // here because nothing downstream matches on this — it is display text only.
      const key = shortName.toUpperCase()
      if (byShortName.has(key)) {
        console.warn(`Duplicate corpShortName "${shortName}" — keeping the first; the join key is no longer unique`)
        continue
      }

      const corpId = Number(c.corpId)
      byShortName.set(key, { name: corpName, corpId: Number.isFinite(corpId) ? corpId : null })
    }

    console.log(`fetched ${byShortName.size} corporations for site naming`)
  } catch (err) {
    console.warn('GetAllCorporation errored — site names left unchanged:', err)
  }

  return byShortName
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // No fallback on purpose. This used to default to '137' while the real org is 126, so
    // removing the secret would have quietly synced a *different organisation's* vehicles,
    // rebuilt vehicle_sites from them and reported success. Matches how ROORIDES_USERNAME
    // and ROORIDES_PASSWORD already behave.
    const orgId = Deno.env.get('ROORIDES_ORG_ID')
    if (!orgId) throw new Error('ROORIDES_ORG_ID secret is not set')

    // Step 1: authenticate with Roorides
    const token = await getRooridesToken()

    // Short code → full school name. Same bearer token; never fatal (see the helper).
    const corporations = await fetchCorporations(token)

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
    //   plateNo        → registration_number (falls back to skip if null)
    //   modelName      → model
    //   make           → make
    //   vehicleType    → type
    //   status         → is_active (Active = true)
    //   school         → vehicle_sites (synced separately below)
    // raw_data stores the full payload so future features can access any field.
    const vehicles = (Array.isArray(raw) ? raw : [])
      .map((v: Record<string, unknown>) => ({
        registration_number: (v.plateNo ?? '') as string,
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
      // so a site's row is never rewritten once created. is_active is set below instead.
      const siteRows = [...allSiteNames].map(name => ({ name }))
      const { error: sitesError } = await supabase
        .from('sites')
        .upsert(siteRows, { onConflict: 'name' })
      if (sitesError) throw sitesError
    }

    // Step 4b: attach the full school name and corp id to each site.
    //
    // Done as targeted updates rather than folded into the upsert above, so a site with
    // no matching corporation keeps whatever name it already had instead of being reset
    // to null. corpName is written through as-is — DCTS really does come back as
    // "Demo Corp" because Roorides test against that record on their live site, and NVS
    // logs real work against it anyway (decision 2026-08-26: show it, don't build an
    // override layer).
    let namedCount = 0
    for (const siteName of allSiteNames) {
      const corp = corporations.get(siteName.toUpperCase())
      if (!corp) continue

      const { error: nameError } = await supabase
        .from('sites')
        .update({ display_name: corp.name, corp_id: corp.corpId })
        .eq('name', siteName)
      if (nameError) throw nameError
      namedCount++
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

    // Step 7: a site is active exactly when this feed still places a vehicle at it.
    //
    // Sites are never deleted — tickets, job cards and user_sites reference them, and a
    // school that leaves still has history worth keeping. So departure is expressed as
    // is_active = false, which hides the site from the New Ticket form without touching
    // anything that points at it.
    //
    // This is deliberately two-way and fully machine-owned: there is no UI for toggling a
    // site, so nothing here can overwrite a human decision, and a partial feed that wrongly
    // deactivates a site is corrected by the next good sync. The empty-response guard above
    // means a total outage can never deactivate everything.
    const { data: existingSites, error: readSitesError } = await supabase
      .from('sites')
      .select('id, name, is_active')
    if (readSitesError) throw readSitesError

    const toActivate = (existingSites ?? [])
      .filter(s => allSiteNames.has(s.name) && !s.is_active)
      .map(s => s.id)
    const toDeactivate = (existingSites ?? [])
      .filter(s => !allSiteNames.has(s.name) && s.is_active)
      .map(s => s.id)

    if (toActivate.length > 0) {
      const { error } = await supabase
        .from('sites').update({ is_active: true }).in('id', toActivate)
      if (error) throw error
    }
    if (toDeactivate.length > 0) {
      const { error } = await supabase
        .from('sites').update({ is_active: false }).in('id', toDeactivate)
      if (error) throw error
    }

    // Step 8: a vehicle is active exactly when this feed still returns it — the same rule
    // Step 7 applies to sites, for the same reason.
    //
    // A vehicle that left the feed used to keep is_active = true forever while Step 6
    // stripped its vehicle_sites rows, leaving a row no supervisor could see (their vehicle
    // list is site-filtered) but every exec could still pick (a blank Site field means an
    // unfiltered list). 69 of those had accumulated in prod by Sep 2026. See MAIN-69.
    //
    // Rows are never deleted: tickets and job cards hold vehicle_number as free text so
    // history survives either way, and a vehicle that comes back must keep its id.
    //
    // Reactivation needs no code here — a vehicle back in the feed is in uniqueVehicles and
    // Step 5's upsert already writes is_active from its upstream status. So the rule is
    // two-way, upstream status stays authoritative, and a partial feed that wrongly
    // deactivates a vehicle is corrected by the next good run. The zero-vehicle abort above
    // means a Roorides outage can never deactivate the fleet.
    //
    // Unlike sites, vehicles have a UI (Vehicles page → Add Vehicle), so this is restricted
    // to feed-owned rows. A hand-created vehicle has no feed entry to be absent from, and
    // deactivating it would be discarding someone's work on a technicality. MAIN-68 decides
    // whether that manual path should exist at all; if it goes, this filter goes with it.
    const feedRegs = new Set(uniqueVehicles.map((v: { registration_number: string }) => v.registration_number))

    // raw_data is selected against, never selected — pulling 800+ full payloads back to
    // read one boolean is the one thing that would make this step expensive.
    const { data: feedVehicles, error: readVehiclesError } = await supabase
      .from('vehicles')
      .select('id, registration_number, is_active')
      .not('raw_data', 'is', null)
    if (readVehiclesError) throw readVehiclesError

    const vehiclesToDeactivate = (feedVehicles ?? [])
      .filter(v => v.is_active && !feedRegs.has(v.registration_number))
      .map(v => v.id)

    // Chunked so the id list cannot blow the request URL length — the same constraint that
    // makes Step 6 wipe the whole table rather than filter by 600+ ids.
    for (let i = 0; i < vehiclesToDeactivate.length; i += 100) {
      const { error } = await supabase
        .from('vehicles')
        .update({ is_active: false })
        .in('id', vehiclesToDeactivate.slice(i, i + 100))
      if (error) throw error
    }

    console.log(`sync-roorides-vehicles: synced ${uniqueVehicles.length} vehicles, ${allSiteNames.size} sites, ${vehicleSitesRecords.length} vehicle-site associations, ${namedCount} sites named, ${toActivate.length} sites reactivated, ${toDeactivate.length} deactivated, ${vehiclesToDeactivate.length} vehicles deactivated`)

    return new Response(
      JSON.stringify({
        success: true,
        synced: uniqueVehicles.length,
        sites: allSiteNames.size,
        sitesNamed: namedCount,
        sitesActivated: toActivate.length,
        sitesDeactivated: toDeactivate.length,
        vehiclesDeactivated: vehiclesToDeactivate.length,
      }),
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
