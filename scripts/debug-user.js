
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

async function checkUser() {
    try {
        await client.connect();
        console.log('Connected to database');

        const email = 'sg@nvstravelsolutions.in';
        console.log(`Checking for user: ${email}`);

        // Check public.users
        const res = await client.query('SELECT * FROM public.users WHERE email = $1', [email]);

        if (res.rows.length === 0) {
            console.log('❌ User NOT FOUND in public.users table!');

            // If not found in public, checking auth (we can't easily check auth.users via pg without superuser, 
            // but we can assume auth exists if they logged in).
            // We should insert the profile if missing.
            console.log('Attempting to fix: Creating missing profile...');

            // We need the auth.uid. We can try to query it from auth.users if we have permissions, 
            // or we might need the user to provide it? 
            // the postgres user in connection string usually has access to auth schema in supabase?
            // Let's try.
            try {
                const authRes = await client.query('SELECT id FROM auth.users WHERE email = $1', [email]);
                if (authRes.rows.length > 0) {
                    const uid = authRes.rows[0].id;
                    console.log(`Found auth.uid: ${uid}`);

                    await client.query(`
                        INSERT INTO public.users (id, email, name, role, is_active)
                        VALUES ($1, $2, 'Maintenance Admin', 'maintenance_exec', true)
                    `, [uid, email]);
                    console.log('✅ Created missing profile in public.users');
                } else {
                    console.log('❌ Could not find user in auth.users either. This is strange if they logged in.');
                }
            } catch (err) {
                console.error('Error querying auth.users:', err.message);
            }

        } else {
            console.log('✅ User FOUND in public.users:', res.rows[0]);

            // Check if role is correct
            if (res.rows[0].role !== 'maintenance_exec') {
                console.log(`⚠️ Role is '${res.rows[0].role}', expected 'maintenance_exec'. Updating...`);
                await client.query("UPDATE public.users SET role = 'maintenance_exec' WHERE email = $1", [email]);
                console.log('✅ Role updated.');
            }
        }

    } catch (err) {
        console.error('Database error:', err);
    } finally {
        await client.end();
    }
}

checkUser();
