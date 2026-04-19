import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

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

  if (!res.ok) {
    throw new Error(`Roorides login failed: ${res.status} ${res.statusText}`)
  }

  const data = await res.json()

  if (!data.accessToken) {
    throw new Error('Roorides login response did not include an accessToken')
  }

  return data.accessToken
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const orgId = Deno.env.get('ROORIDES_ORG_ID') ?? '137'

    const token = await getRooridesToken()

    const res = await fetch(`${ROORIDES_BASE_URL}/Vehicle/GetAllVehicles/${orgId}`, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    })

    if (!res.ok) {
      throw new Error(`Roorides GetAllVehicles failed: ${res.status} ${res.statusText}`)
    }

    const raw = await res.json()

    // Normalise to the shape the app uses. Adjust field names if the
    // Roorides API response uses different casing.
    const vehicles = (Array.isArray(raw) ? raw : raw.data ?? raw.vehicles ?? []).map(
      (v: Record<string, unknown>) => ({
        registration_number: v.registrationNumber ?? v.RegistrationNumber ?? v.vehicleNumber ?? v.VehicleNumber ?? '',
        type: v.vehicleType ?? v.VehicleType ?? v.category ?? v.Category ?? null,
        make: v.brandName ?? v.BrandName ?? v.make ?? v.Make ?? null,
        model: v.model ?? v.Model ?? null,
      })
    ).filter((v: { registration_number: unknown }) => !!v.registration_number)

    return new Response(
      JSON.stringify({ vehicles }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('get-roorides-vehicles error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
