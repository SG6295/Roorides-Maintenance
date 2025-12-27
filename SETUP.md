# Setup Guide - NVS Maintenance System

## 1. Supabase Setup

### Create Supabase Project
1. Go to [supabase.com](https://supabase.com)
2. Click "New Project"
3. Fill in:
   - **Name**: NVS Maintenance
   - **Database Password**: (save this securely)
   - **Region**: Choose closest to your location
4. Wait for project to initialize (~2 minutes)

### Run Database Schema
1. In Supabase Dashboard, go to **SQL Editor**
2. Click **New Query**
3. Copy entire contents of `supabase-schema.sql`
4. Paste and click **Run**
5. Verify tables created: Go to **Table Editor** - you should see:
   - sites
   - vehicles
   - users
   - tickets
   - finance_entries

### Get API Credentials
1. Go to **Settings** > **API**
2. Copy:
   - **Project URL** (looks like `https://xxxxx.supabase.co`)
   - **anon/public key** (long string starting with `eyJ...`)

## 2. Environment Variables

### Create `.env.local`
```bash
cp .env.local.example .env.local
```

### Edit `.env.local`
```env
VITE_SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOi...YOUR_ANON_KEY
VITE_GOOGLE_DRIVE_FOLDER_ID=
VITE_APP_NAME=NVS Maintenance
VITE_ASSIGNMENT_SLA_DAYS=1
```

## 3. Create First User

### In Supabase Dashboard
1. Go to **Authentication** > **Users**
2. Click **Add user** > **Create new user**
3. Fill in:
   - **Email**: your-email@example.com
   - **Password**: (create a secure password)
4. Click **Create user**

### Add User Profile
1. Go to **Table Editor** > **users** table
2. Click **Insert** > **Insert row**
3. Fill in:
   - **id**: Copy the UUID from auth.users (from step above)
   - **email**: Same email as above
   - **name**: Your Name
   - **employee_id**: EMP001
   - **contact**: Your phone number
   - **role**: `maintenance_exec` (for testing - gives full access)
   - **site**: Leave NULL (maintenance exec sees all sites)
   - **is_active**: true
4. Click **Save**

## 4. Add Sample Data (Optional)

### Add Sites
Go to **Table Editor** > **sites** > **Insert rows**

```
name: "Chennai - Site A"
name: "Bangalore - Site B"
name: "Mumbai - Site C"
... add your 60+ sites
```

### Add Vehicles
Go to **Table Editor** > **vehicles** > **Insert rows**

```
number: "KA-01-AB-1234"
site: "Bangalore - Site B"
type: "SWARAJ MAZDA (20+1)"

number: "TN-09-XY-5678"
site: "Chennai - Site A"
type: "TATA LPT 1618"
... add your vehicles
```

## 5. Run the Application

```bash
npm run dev
```

Open [http://localhost:5173](http://localhost:5173)

### Test Login
- **Email**: The email you created in step 3
- **Password**: The password you set

You should see the dashboard with your name and role.

## 6. Verify RLS (Row Level Security)

### Test as Maintenance Exec
- Should see dashboard
- Should be able to create test tickets
- Should see all tickets across all sites

### Create Supervisor User (for testing)
1. Create another user in Supabase Auth
2. Add to users table with:
   - **role**: `supervisor`
   - **site**: "Chennai - Site A" (specific site)
3. Login as supervisor
4. Should only see tickets from their assigned site

## 7. Next Steps

Once verified:
1. ✅ Auth working
2. ✅ RLS policies working
3. ✅ Database schema complete

**Start building Phase 1 features:**
- Ticket submission form (mobile-first)
- Ticket list with filters
- Ticket detail view
- Ticket management (assign, update status)

## Troubleshooting

### Can't connect to Supabase
- Check `.env.local` has correct URL and key
- Verify project is not paused (free tier pauses after 7 days of inactivity)

### User can't log in
- Verify user exists in both `auth.users` AND `users` table
- Check `is_active = true` in users table
- Verify email confirmation (disable in Auth settings for development)

### RLS errors "permission denied"
- Check user has entry in `users` table with correct role
- Verify RLS policies are enabled
- Check `auth.uid()` matches user.id

### Database schema errors
- Drop all tables and re-run schema
- Check for typos in table names
- Verify UUID extension is enabled

## Support

For issues, check:
- [Supabase Documentation](https://supabase.com/docs)
- [PRD Document](../NVS-MAINTENANCE-PRD.md)
