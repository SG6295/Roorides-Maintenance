# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm run dev        # Start Vite dev server (http://localhost:5173)
npm run build      # Production build → dist/
npm run lint       # ESLint
npm run preview    # Preview production build locally
```

### Edge Functions
```bash
supabase functions deploy <function-name> --no-verify-jwt   # Deploy an edge function
# Functions: create-user, send-email, daily-digest, upload-to-drive
```

> All edge functions must be deployed with `--no-verify-jwt` — this project uses caller-identity checks inside the function code instead of gateway-level JWT verification.

## Architecture

### Stack
- **Frontend**: React 19, Vite 7, React Router 7, TanStack Query 5, Tailwind CSS 3
- **Backend**: Supabase (Postgres + Auth + Edge Functions)
- **Email**: Resend API (via `send-email` edge function)
- **File Storage**: Google Drive (via `upload-to-drive` edge function + service account)
- **Deployment**: Vercel (SPA, all routes rewrite to `/index.html`)

### What this app does
A fleet maintenance ticketing system for NVS Travel Solutions. Supervisors submit tickets → maintenance exec assigns and manages work via job cards → mechanics complete jobs → finance tracks costs.

### State Management
- **Auth state**: React Context via `useAuth()` hook (`src/hooks/useAuth.js`) — exposes `user`, `userProfile`, `loading`
- **Server state**: TanStack Query via custom hooks (`useTickets`, `useIssues`, `useJobCards`, etc.) — these are the single source of truth; mutations invalidate related query keys on success
- No Redux or Zustand

### Auth & Role Enforcement (two-tier)
1. **Database level**: Every table has RLS policies enforced by Postgres. Supervisors are scoped to their `site`; `maintenance_exec` has global access.
2. **React level**: `ProtectedRoute` in `src/App.jsx` checks `userProfile.role` against `allowedRoles`. Deactivated users (`is_active = false`) are forcibly signed out on profile fetch.

Roles: `supervisor` (site-specific), `maintenance_exec` (global admin), `mechanic` (job cards only), `finance` (finance entries only).

### Edge Functions (`supabase/functions/`)
All written in Deno/TypeScript. Each function uses `SUPABASE_SERVICE_ROLE_KEY` for admin operations (auto-provided by Supabase runtime). `create-user` additionally verifies the caller is a `maintenance_exec` by checking their profile via the anon key + caller JWT before proceeding.

| Function | Purpose |
|---|---|
| `create-user` | Provisions new users (auth + public.users profile). Requires `maintenance_exec` role. |
| `send-email` | Thin wrapper around Resend API for transactional emails |
| `daily-digest` | Reads `user_settings.notify_daily_digest` and sends personalised summaries via Resend |
| `upload-to-drive` | Uploads images to a specific Google Drive folder via service account JWT |

### Key Data Model Relationships
- **Ticket** → has many **Issues** (category, severity, SLA tracking)
- **Issue** → optionally linked to a **Job Card** (`job_card_id` nullable)
- **Job Card** → assigned to a mechanic (InHouse) or vendor (Outsource)
- **Ticket** → has many **audit_logs** (grouped by `record_id = ticket_id`, covers ticket + issue + job card changes)
- **SLA** is calculated by database triggers on issue creation using `sla_rules_config(category, severity, sla_days)`

### SLA System
SLA windows are configured in the `sla_rules_config` table (editable via the SLA Settings page, `maintenance_exec` only). Database triggers auto-calculate `sla_end_date` and `sla_status` (Pending/Adhered/Violated) per issue. Holiday calendar in `holidays` table is used for business-day SLA calculations.

### Migrations
`supabase/migrations/` contains ~26 migration files. The schema was built incrementally — `supabase-schema.sql` in the root is the canonical full schema reference. When making schema changes, write a new migration file rather than modifying existing ones.

### Environment Variables
```
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
VITE_GOOGLE_DRIVE_FOLDER_ID
VITE_APP_NAME
VITE_ASSIGNMENT_SLA_DAYS
```
Edge functions use `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`, `RESEND_API_KEY`, `GOOGLE_SERVICE_ACCOUNT_EMAIL`, `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY` — set in the Supabase dashboard under Edge Function secrets.
