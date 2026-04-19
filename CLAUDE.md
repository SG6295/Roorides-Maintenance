# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Working directory**: All commands below should be run from `nvs-maintenance/`.

## Commands

```bash
npm run dev        # Start Vite dev server (http://localhost:5173)
npm run build      # Production build → dist/
npm run lint       # ESLint
npm run preview    # Preview production build locally
npm run gen:types  # Regenerate src/types/database.types.ts from live Supabase schema
```

### Schema change rule
**After every schema change (new migration, renamed column, added table), always run `npm run gen:types` before touching any app code.** This keeps `src/types/database.types.ts` in sync with the DB and makes stale column references visible immediately.

### Edge Functions
```bash
supabase functions deploy <function-name> --no-verify-jwt   # Deploy an edge function
# Functions: create-user, send-email, daily-digest, upload-to-drive, get-roorides-vehicles
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
| `get-roorides-vehicles` | (Superseded) Early prototype — fetches vehicles from Roorides and returns them without persisting. No longer used by the app. |
| `sync-roorides-vehicles` | Authenticates with Roorides, fetches all vehicles for org 137, and upserts them into the local `vehicles` table. Never overwrites the `site` column. Called by pg_cron at midnight UTC daily and also manually via the "Refresh vehicle list" button on the ticket form. Credentials: `ROORIDES_USERNAME`, `ROORIDES_PASSWORD`, `ROORIDES_ORG_ID` secrets. |

### Key Data Model Relationships
- **Ticket** → has many **Issues** (category, severity, SLA tracking)
- **Issue** → optionally linked to a **Job Card** (`job_card_id` nullable)
- **Issue** → has many **issue_parts** (parts consumed during the repair)
- **Job Card** → assigned to a mechanic (InHouse) or vendor (Outsource)
- **Ticket** → has many **audit_logs** (grouped by `record_id = ticket_id`, covers ticket + issue + job card changes)
- **SLA** is calculated by database triggers on issue creation using `sla_rules_config(category, severity, sla_days)`
- **Part** → restocked via `purchase_invoice_items`; a DB trigger updates `parts.quantity_in_stock` on insert
- **purchase_invoices** → has many **purchase_invoice_items** → each references a `parts` row

### SLA System
SLA windows are configured in the `sla_rules_config` table (editable via the SLA Settings page, `maintenance_exec` only). Database triggers auto-calculate `sla_end_date` and `sla_status` (Pending/Adhered/Violated) per issue. Holiday calendar in `holidays` table is used for business-day SLA calculations.

### Inventory Module
`src/pages/Inventory.jsx` (accessible to `maintenance_exec` and `finance`) has three tabs managed via local state:
1. **Parts Catalog** — stock levels, low-stock filter; `useUpdatePart` for inline edits, `useBulkUpload` for CSV import via `BulkUploadModal`
2. **Purchase History** — invoice list (`usePurchaseInvoices`), record new purchase via `PurchaseModal`; DB trigger auto-restocks parts when invoice items are inserted
3. **Consumption History** — `usePartConsumption`, shows parts used per job card/mechanic

All inventory data hooks live in `src/hooks/useInventory.js` (formerly `useParts.js`) and are named exports: `useParts`, `usePurchaseInvoices`, `usePurchaseInvoiceItems`, `useRecordPurchase`, `useUpdatePart`, `usePartConsumption`, `useVehicleHistory`, `useJobCardParts`, `useMechanicProfile`, `useMechanicActivity`, `useCreatePart`, `usePartUnits`, `useAddPartUnit`, `useDeletePartUnit`.

### Vehicle & Mechanic Detail Pages
- `src/pages/VehicleHistory.jsx` — full job-card history for a specific vehicle; uses `useVehicleHistory(vehicleNumber)` and `useJobCardParts(jobCardId)` for lazy-loaded parts per card
- `src/pages/MechanicDetail.jsx` — profile + job card activity + labour hours for a mechanic; uses `useMechanicProfile` + `useMechanicActivity`

### Settings (Nested Routes under `/settings`)
`src/pages/settings/SettingsLayout.jsx` wraps a sidebar + `<Outlet>`. Sub-routes:
- `/settings/notifications` — `NotificationSettings.jsx`, reads/writes `user_settings.notify_daily_digest`
- `/settings/users` — embeds `Users` page with `embedded={true}` prop
- `/settings/sla` — embeds `SLASettings` with `embedded={true}` prop
- `/settings/units` — `PartUnitsSettings.jsx`, CRUD for `part_units` table (unit labels for parts)

### Analytics & Export
`src/pages/Analytics.jsx` uses **recharts** for charts. `xlsx` is available for spreadsheet export (used in inventory/analytics exports).

### Debug Utilities
`window.testResend(email)` is exposed in App.jsx for testing email via the `send-email` edge function from the browser console.

### Migrations
`supabase/migrations/` contains 37 migration files. The schema was built incrementally — `supabase-schema.sql` in the root is the canonical full schema reference. When making schema changes, write a new migration file rather than modifying existing ones.

### Environment Variables
```
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
VITE_GOOGLE_DRIVE_FOLDER_ID
VITE_APP_NAME
VITE_ASSIGNMENT_SLA_DAYS
```
Edge functions use `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`, `RESEND_API_KEY`, `GOOGLE_SERVICE_ACCOUNT_EMAIL`, `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY` — set in the Supabase dashboard under Edge Function secrets.
