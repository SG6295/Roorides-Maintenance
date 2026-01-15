
import { createClient } from '@supabase/supabase-js'
import fs from 'fs'
import path from 'path'
import dotenv from 'dotenv'
import { fileURLToPath } from 'url'

// Helper for ESM directory
const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

// Load env
const envConfig = dotenv.config({ path: path.join(__dirname, '../.env.local') })
const SUPABASE_URL = process.env.VITE_SUPABASE_URL
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY // Use service key for admin tasks if available, or just use anon for now if policy allows, but DDL needs admin usually. 
// Actually, applying raw SQL usually requires the Service Key or direct PG connection. 
// Since I don't have the Service Key in env (it's in the edge function secrets usually), I'll stick to the `pg` client approach I used before which worked well.

// Re-using the PG client approach is better for migrations.
import pg from 'pg'
const { Client } = pg

const dbUrl = process.env.DATABASE_URL

if (!dbUrl) {
    console.error('DATABASE_URL is not set in .env.local')
    process.exit(1)
}

const client = new Client({
    connectionString: dbUrl,
    ssl: { rejectUnauthorized: false }
})

async function apply() {
    try {
        await client.connect()
        const sql = fs.readFileSync(path.join(__dirname, '../supabase/migrations/create_user_settings.sql'), 'utf8')
        await client.query(sql)
        console.log('Migration applied successfully!')
    } catch (err) {
        console.error('Migration failed:', err)
    } finally {
        await client.end()
    }
}

apply()
