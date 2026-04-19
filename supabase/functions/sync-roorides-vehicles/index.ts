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
    // We deliberately exclude 'site' so local site assignments are never overwritten.
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

    if (vehicles.length === 0) {
      throw new Error('Roorides returned 0 vehicles — aborting to avoid wiping local data')
    }

    // Step 4: upsert into local vehicles table using service role (bypasses RLS).
    // onConflict: 'registration_number' means existing rows are updated, new rows inserted.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { error } = await supabase
      .from('vehicles')
      .upsert(vehicles, { onConflict: 'registration_number' })

    if (error) throw error

    console.log(`sync-roorides-vehicles: synced ${vehicles.length} vehicles`)

    return new Response(
      JSON.stringify({ success: true, synced: vehicles.length }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('sync-roorides-vehicles error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
