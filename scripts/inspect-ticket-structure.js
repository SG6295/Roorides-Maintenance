
import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'
dotenv.config()

const supabaseUrl = process.env.VITE_SUPABASE_URL
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY

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
        if (data && data.length > 0) {
            console.log('Ticket keys:', Object.keys(data[0]))
            console.log('Sample ticket:', data[0])
        } else {
            console.log('No tickets found to inspect.')
        }
    }
}

inspectTickets()
