import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify authentication using JWT from Authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Create Supabase client with the user's JWT token
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    )

    // Verify the user is authenticated
    const { data: { user }, error: authError } = await supabaseClient.auth.getUser()

    if (authError || !user) {
      console.error('Auth error:', authError)
      return new Response(
        JSON.stringify({ error: 'Unauthorized', details: authError?.message }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Get the uploaded file from the request
    const formData = await req.formData()
    const file = formData.get('file') as File

    if (!file) {
      return new Response(
        JSON.stringify({ error: 'No file provided' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Read service account credentials from environment
    const serviceAccountEmail = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL')
    const serviceAccountKey = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY')
    const driveFolderId = Deno.env.get('GOOGLE_DRIVE_FOLDER_ID')

    if (!serviceAccountEmail || !serviceAccountKey || !driveFolderId) {
      return new Response(
        JSON.stringify({ error: 'Missing Google Drive configuration' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Debug: Verify key format
    console.log('Environment check:', {
      hasEmail: !!serviceAccountEmail,
      hasKey: !!serviceAccountKey,
      hasFolderId: !!driveFolderId,
      emailValue: serviceAccountEmail,
      keyPrefix: serviceAccountKey?.substring(0, 30),
      keyHasBegin: serviceAccountKey.includes('BEGIN PRIVATE KEY'),
      keyHasEnd: serviceAccountKey.includes('END PRIVATE KEY'),
      keyLength: serviceAccountKey.length
    })

    // Validate file before processing
    if (file.size > 50 * 1024 * 1024) { // 50MB limit
      return new Response(
        JSON.stringify({ error: 'File too large. Max 50MB.' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/jpg']
    if (!allowedTypes.includes(file.type)) {
      return new Response(
        JSON.stringify({ error: `Invalid file type: ${file.type}. Only images allowed.` }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Get access token using service account
    const jwtToken = await createJWT(serviceAccountEmail, serviceAccountKey)
    const accessToken = await getAccessToken(jwtToken)

    // Read file as ArrayBuffer
    const fileBuffer = await file.arrayBuffer()
    const fileName = `${Date.now()}-${file.name}`

    // Upload to Google Drive using proper binary multipart
    const boundary = '-------314159265358979323846'
    const metadata = {
      name: fileName,
      parents: [driveFolderId],
    }

    // Build multipart body parts
    const encoder = new TextEncoder()

    const metadataPart = [
      `--${boundary}`,
      'Content-Type: application/json; charset=UTF-8',
      '',
      JSON.stringify(metadata),
      ''
    ].join('\r\n')

    const filePart = [
      `--${boundary}`,
      `Content-Type: ${file.type || 'application/octet-stream'}`,
      '',
      ''
    ].join('\r\n')

    const footer = `\r\n--${boundary}--`

    // Combine as binary (handles large files)
    const metadataBytes = encoder.encode(metadataPart)
    const fileHeaderBytes = encoder.encode(filePart)
    const fileBytes = new Uint8Array(fileBuffer)
    const footerBytes = encoder.encode(footer)

    const totalLength = metadataBytes.length + fileHeaderBytes.length + fileBytes.length + footerBytes.length
    const multipartBody = new Uint8Array(totalLength)

    let offset = 0
    multipartBody.set(metadataBytes, offset)
    offset += metadataBytes.length
    multipartBody.set(fileHeaderBytes, offset)
    offset += fileHeaderBytes.length
    multipartBody.set(fileBytes, offset)
    offset += fileBytes.length
    multipartBody.set(footerBytes, offset)

    const uploadResponse = await fetch(
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': `multipart/related; boundary=${boundary}`,
        },
        body: multipartBody, // Binary body, not string
      }
    )

    if (!uploadResponse.ok) {
      const errorText = await uploadResponse.text()
      console.error('Google Drive upload failed:', {
        status: uploadResponse.status,
        statusText: uploadResponse.statusText,
        error: errorText
      })
      return new Response(
        JSON.stringify({
          error: 'Failed to upload to Google Drive',
          details: errorText,
          status: uploadResponse.status
        }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    const uploadResult = await uploadResponse.json()
    const fileId = uploadResult.id

    if (!fileId) {
      console.error('No file ID in upload response:', uploadResult)
      return new Response(
        JSON.stringify({ error: 'Upload succeeded but no file ID returned' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Make file publicly accessible
    const permResponse = await fetch(
      `https://www.googleapis.com/drive/v3/files/${fileId}/permissions`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          role: 'reader',
          type: 'anyone',
        }),
      }
    )

    if (!permResponse.ok) {
      const permError = await permResponse.text()
      console.error('Failed to set file permissions:', {
        status: permResponse.status,
        error: permError
      })
      // Don't fail the upload, but log the warning
      console.warn('File uploaded but permissions not set. File may not be publicly accessible.')
    }

    // Return the shareable link
    const shareableLink = `https://drive.google.com/file/d/${fileId}/view`

    return new Response(
      JSON.stringify({
        success: true,
        fileId,
        url: shareableLink,
        fileName
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }
})

// Helper function to create JWT for service account
async function createJWT(email: string, privateKey: string): Promise<string> {
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: email,
    scope: 'https://www.googleapis.com/auth/drive.file',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }

  // Encode header and payload
  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedPayload = base64UrlEncode(JSON.stringify(payload))
  const signatureInput = `${encodedHeader}.${encodedPayload}`

  // Import private key
  const keyData = privateKey
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\n/g, '')

  const binaryKey = Uint8Array.from(atob(keyData), c => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  )

  // Sign
  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signatureInput)
  )

  const signature = base64UrlEncode(
    String.fromCharCode(...new Uint8Array(signatureBuffer))
  )

  return `${signatureInput}.${signature}`
}

// Helper function to get access token
async function getAccessToken(jwt: string): Promise<string> {
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  const data = await response.json()

  // CRITICAL: Check for errors from Google
  if (!response.ok) {
    console.error('Token exchange failed:', {
      status: response.status,
      error: data.error,
      description: data.error_description,
      fullResponse: data
    })
    throw new Error(`Token exchange failed: ${data.error_description || data.error || 'Unknown error'}`)
  }

  if (!data.access_token) {
    console.error('No access token in response:', data)
    throw new Error('No access token in response from Google')
  }

  return data.access_token
}

// Helper function for base64 URL encoding
function base64UrlEncode(str: string): string {
  return btoa(str)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
}
