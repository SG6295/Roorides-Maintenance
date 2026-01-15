
import { createClient } from '@supabase/supabase-js'

const SUPABASE_URL = 'https://awbovpblaxwpsuclpiyh.supabase.co'
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF3Ym92cGJsYXh3cHN1Y2xwaXloIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY4MjI5NDgsImV4cCI6MjA4MjM5ODk0OH0.oj6m_Z__bb6v3LXfwx925lPVokRiAIigv24lKz7NkCc'

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY)

async function test() {
    console.log('Authenticating...')
    // 1. Login
    const { data: { session }, error: loginError } = await supabase.auth.signInWithPassword({
        email: 'sg@nvstravelsolutions.in',
        password: 'nvs@1234'
    })

    if (loginError) {
        console.error('Login failed:', loginError)
        process.exit(1)
        return
    }

    console.log('Logged in as:', session.user.email)

    // 2. Prepare mock file
    // Edge function expects 'image/*' types
    const imageBlob = new Blob(['fake image content ' + Date.now()], { type: 'image/jpeg' })

    const formData = new FormData()
    formData.append('file', imageBlob, 'test-automation-image.jpg')

    console.log('Uploading file...')
    // 3. Invoke function
    const { data, error } = await supabase.functions.invoke('upload-to-drive', {
        body: formData,
    })

    if (error) {
        console.error('Function invoke failed (status code likely non-2xx).')
        try {
            if (error.context && typeof error.context.json === 'function') {
                const body = await error.context.json()
                console.error('Error body:', JSON.stringify(body, null, 2))
            } else {
                console.error('Error details:', error)
            }
        } catch (e) {
            console.error('Could not parse error body:', e)
            console.error('Original error:', error)
        }
    } else {
        console.log('Upload success!')
        console.log('File ID:', data.fileId)
        console.log('URL:', data.url)

        // Optional: Log full response for user to see
        console.log('Full JSON:', JSON.stringify(data, null, 2))
    }
}

test()
