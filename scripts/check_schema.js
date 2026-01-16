
import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'
dotenv.config()

const supabaseUrl = process.env.VITE_SUPABASE_URL
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY // Use service role to bypass RLS for inspection

if (!supabaseUrl || !supabaseKey) {
    console.error('Missing env vars')
    process.exit(1)
}

const supabase = createClient(supabaseUrl, supabaseKey)

async function inspectTickets() {
    const { data, error } = await supabase
        .from('tickets')
        .select('*')
        .limit(1)

    if (error) {
        console.error('Error:', error)
    } else {
        // If no rows, we can't see columns easily via select * result keys, but error would tell us if col missing if we selected it.
        // Better: try to select the 'rating' column explicitly.
        const { error: ratingError } = await supabase.from('tickets').select('rating').limit(1)
        if (ratingError) {
            console.log('Rating column likely MISSING:', ratingError.message)
        } else {
            console.log('Rating column EXISTS')
        }
    }
}

inspectTickets()
