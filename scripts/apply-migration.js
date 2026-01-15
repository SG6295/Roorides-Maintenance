
import pg from 'pg'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const { Client } = pg

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load env vars manually since we might not have dotenv loaded in this context if running via node directly
// But for simplicity, we'll assume DATABASE_URL is available or we parse it from .env.local

function getEnvVaR(key) {
    const envFile = fs.readFileSync(path.resolve(__dirname, '../.env.local'), 'utf8');
    const line = envFile.split('\n').find(l => l.startsWith(key + '='));
    return line ? line.split('=')[1] : null;
}

const connectionString = getEnvVaR('DATABASE_URL');

if (!connectionString) {
    console.error('DATABASE_URL not found in .env.local');
    process.exit(1);
}

const client = new Client({
    connectionString: connectionString,
    ssl: { rejectUnauthorized: false } // Required for Supabase in some envs
})

async function runMigration() {
    try {
        await client.connect();
        console.log('Connected to database');

        const sqlFilterPath = path.resolve(__dirname, '../supabase/migrations/update_rls_policies.sql');
        const sql = fs.readFileSync(sqlFilterPath, 'utf8');

        console.log('Applying migration...');
        await client.query(sql);
        console.log('Migration applied successfully!');

    } catch (err) {
        console.error('Migration failed:', err);
    } finally {
        await client.end();
    }
}

runMigration();
