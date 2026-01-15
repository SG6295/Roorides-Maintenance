
import pg from 'pg'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const { Client } = pg

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function getEnvVaR(key) {
    const envFile = fs.readFileSync(path.resolve(__dirname, '../.env.local'), 'utf8');
    const line = envFile.split('\n').find(l => l.startsWith(key + '='));
    return line ? line.split('=')[1] : null;
}

const connectionString = getEnvVaR('DATABASE_URL');

const client = new Client({
    connectionString: connectionString,
    ssl: { rejectUnauthorized: false }
})

async function inspectTable() {
    try {
        await client.connect();
        console.log('Connected to database');

        const res = await client.query(`
            SELECT column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'users';
        `);

        console.log('Columns in public.users:');
        console.table(res.rows);

    } catch (err) {
        console.error('Database error:', err);
    } finally {
        await client.end();
    }
}

inspectTable();
