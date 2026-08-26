# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Working directory**: All commands below should be run from `nvs-maintenance/`.

## Commands

```bash
npm run dev        # Start Vite dev server (http://localhost:5173)
npm run build      # Production build → dist/
npm run lint       # ESLint
npm run preview    # Preview production build locally
npm run schema:dump  # Regenerate docs/schema.sql and src/types/database.types.ts
```

### DB change workflow (follow this every time, in order)
1. **Write the migration file** in `supabase/migrations/` — this is the source of truth and goes to git.
2. **Preview via MCP `execute_sql`** using a `BEGIN; ...; ROLLBACK;` wrapper — Claude verifies the output before anything is permanently applied. Raise it with the user only if something looks risky.
3. **Apply via MCP `apply_migration`** with the clean SQL (no BEGIN/ROLLBACK) — recorded in migration history, atomic.
4. **Regenerate** with `npm run schema:dump` — keeps `docs/schema.sql` and `src/types/database.types.ts` in sync.

> **`execute_sql` is never used to make schema changes directly** — always go through `apply_migration` so the change is tracked. `execute_sql` is for queries, data fixes, and previews only.

### Edge Functions
```bash
supabase functions deploy <function-name> --no-verify-jwt   # Deploy an edge function
# Functions: create-user, update-user, send-email, daily-digest, upload-to-drive, sync-roorides-vehicles, backup-to-drive
```

> All edge functions must be deployed with `--no-verify-jwt` — this project uses caller-identity checks inside the function code instead of gateway-level JWT verification.

## Architecture

### Stack
- **Frontend**: React 19, Vite 7, React Router 7, TanStack Query 5, Tailwind CSS 3, React Hook Form 7 — app source is `.jsx`, not TypeScript (only `src/types/database.types.ts` is auto-generated)
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
1. **Database level**: Every table has RLS policies enforced by Postgres. Supervisors are scoped via `user_sites` junction table; `maintenance_exec` and `super_admin` have global access (the `is_maintenance_exec()` DB function covers both).
2. **React level**: `ProtectedRoute` in `src/App.jsx` checks `userProfile.role` against `allowedRoles`. Deactivated users (`is_active = false`) are forcibly signed out on profile fetch.

Roles:
| Role | Access |
|---|---|
| `supervisor` | Site-specific tickets/issues (multi-site via `user_sites`) |
| `maintenance_exec` | Global admin — job cards, issues, most settings |
| `super_admin` | Everything `maintenance_exec` can do + SLA rules, system_settings, holidays |
| `mechanic` | Assigned job cards only |
| `electrician` | Same scope as `mechanic` (job cards only) |
| `finance` | Finance entries, inventory, purchase invoices, vehicles |

**When adding a new role**, update: (1) `users_role_check` constraint in a migration, (2) relevant RLS policies / DB helper functions, (3) `ProtectedRoute allowedRoles` arrays in `src/App.jsx`, (4) `MANAGEABLE_BY` + `ROLE_LABELS` + `ROLE_COLORS` in `src/constants/userRoles.js`, (5) the role matrices in the `create-user` and `update-user` edge functions, (6) any role-conditional UI in pages/components.

### User Management (`/settings/users`)
`src/pages/Users.jsx` lists users with search + role filter. Creation goes through `AddUserModal`; `super_admin` additionally gets an Edit button per row (`EditUserModal`) covering name, email, role, employee ID, contact, assigned sites and an optional password reset. Both modals share `src/constants/userRoles.js` (role matrix, labels, colours, and `generatePassword()` — which produces readable `Mango-River-47` style passwords from `src/constants/wordlist.js`) and `SiteCheckboxList`.

Neither the edit nor the activate/deactivate toggle writes to `public.users` from the browser — both call the `update-user` edge function, so every change is role-checked server-side and recorded in `user_audit_logs`. That table is **super_admin-read-only with no INSERT policy** (only the service-role edge functions write to it), and is surfaced by the paginated `UserAuditLog` panel below the user list. Its `target_user_id` / `performed_by` columns are deliberately **not** foreign keys, and it snapshots names and emails, so history survives a user being deleted or renamed.

### user_sites & vehicle_sites Junction Tables
- `public.user_sites (user_id, site_id)` — supervisors may be assigned to multiple sites. The old `users.site` text column still exists for backwards compatibility but is no longer authoritative — RLS policies join through `user_sites`.
- `public.vehicle_sites (vehicle_id, site_name)` — vehicles may be assigned to multiple sites, surfaced on the Vehicles page.

### The `sites` table is machine-owned — do not add a UI for it
`sites` is not maintained by hand. It is a by-product of the Roorides vehicle feed: `sync-roorides-vehicles` splits each vehicle's `school` field and creates a row per distinct value.

**Rows are never deleted.** `tickets.site`, `job_cards.site` and `finance_entries.site` are free text with no foreign key, and `user_sites.site_id` has one, so deleting a site orphans history and breaks supervisor assignments. Departure is expressed as `is_active = false` instead.

**The sync owns `is_active` and rewrites it on every run** — a site is active exactly when the current feed still places a vehicle at it. The rule is two-way, so a site that regains vehicles reactivates itself, and a partial feed that wrongly deactivates one is corrected by the next run. Any UI that writes `is_active` would be silently overwritten within 24 hours, which is why there is deliberately no Sites settings page. `sites` also has no INSERT/UPDATE/DELETE RLS policy, so a browser client cannot write to it at all.

**`display_name` and `corp_id` are sync-owned too** — filled from `GET /api/ManageCorp/GetAllCorporation/0/0`, joined on `corpShortName`. They are display-only (`formatSiteLabel()` in `src/utils/siteLabel.js` renders `CODE — Full Name — corpId` for every site picker) and nothing matches on them, so that join is case-insensitive even though `name` is not. Both stay NULL when no corporation matches, and an unmatched site keeps its existing name rather than being reset. `DCTS` legitimately reads "Demo Corp" upstream; it is shown as-is by decision, not by bug.

Consequences worth knowing before touching site code:
- A site name is matched **exactly**, including case. The supervisor `SELECT` policy on `tickets` compares `tickets.site` against site names joined through `user_sites`, so a casing mismatch silently hides a supervisor's own tickets. In Aug 2026 an upstream rename (`Agrata` → `AGRATA`) left duplicate rows and cost a manual repointing of 7 assignments, 19 tickets and 17 job cards.
- Renaming a site means updating every one of those free-text columns **and** `user_sites` in the same transaction.
- Active-only is correct for *creating* a ticket and wrong for *filtering history* — a deactivated site's past tickets must still be filterable. See MAIN-50.

### Edge Functions (`supabase/functions/`)
All written in Deno/TypeScript. Each function uses `SUPABASE_SERVICE_ROLE_KEY` for admin operations (auto-provided by Supabase runtime). `create-user` additionally verifies the caller is a `maintenance_exec` by checking their profile via the anon key + caller JWT before proceeding.

| Function | Purpose |
|---|---|
| `create-user` | Provisions new users (auth + public.users profile). Requires `maintenance_exec` role. Writes a `CREATE` row to `user_audit_logs`. |
| `update-user` | Edits an existing user. Two modes via an `action` field: `update` (name/email/role/employee_id/contact/sites/password — **`super_admin` only**) and `set_active` (the activate-deactivate toggle — `super_admin`, plus `maintenance_exec` for supervisor/mechanic/electrician). Both write to `user_audit_logs`. Nobody may edit their own account through it. Email and password changes need the service-role key, which is why this can't be a client write. Note: a password change does **not** revoke the target's existing sessions. |
| `send-email` | Thin wrapper around Resend API for transactional emails |
| `daily-digest` | Reads `user_settings.notify_daily_digest` and sends personalised summaries via Resend |
| `upload-to-drive` | Uploads images to a specific Google Drive folder via service account JWT |
| `get-roorides-vehicles` | (Superseded) Early prototype — fetches vehicles from Roorides and returns them without persisting. No longer used by the app. |
| `sync-roorides-vehicles` | Authenticates with Roorides, fetches all vehicles for org 126 (via `ROORIDES_ORG_ID` secret), and upserts them into the local `vehicles` table. Never overwrites the `site` column. Called by pg_cron at midnight UTC daily and also manually via the "Refresh vehicle list" button on the ticket form. Credentials: `ROORIDES_USERNAME`, `ROORIDES_PASSWORD`, `ROORIDES_ORG_ID` secrets. **See the `sites` note below — the sync owns `sites.is_active`.** |
| `seed-staging-from-prod` | **Staging only.** Nukes all staging auth users and public table data, then reseeds from production. Requires `super_admin` role. All staging users are recreated with password `NVSStaging2025!`. Triggered via the "Seed Staging from Production" page under Settings (only visible when `VITE_ENABLE_DANGER_ZONE=true`). Secrets required in staging: `PROD_SUPABASE_URL`, `PROD_SUPABASE_SERVICE_ROLE_KEY`. |
| `backup-to-drive` | Dumps all tables to JSON and uploads to Google Drive via service account JWT. Deletes backups older than 7 days from the Drive folder. Scheduled hourly 10 AM–7 PM IST (`30 4-13 * * *` UTC) via pg_cron (`nvs-hourly-backup` job). Secrets: `GOOGLE_SERVICE_ACCOUNT_EMAIL`, `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY`, `BACKUP_DRIVE_FOLDER_ID`. |

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
SLA windows are configured in the `sla_rules` table (editable via the SLA Settings page — `super_admin` can write, `maintenance_exec` can view). Database triggers auto-calculate `sla_end_date` and `sla_status` (Pending/Adhered/Violated) per issue. Holiday calendar in `holidays` table and weekly-offs in `system_settings` key `sla_weekly_offs` are used for business-day calculations. Timeline events are stored in `sla_events` and surfaced via `useSLAEvents(ticketId)` in `src/hooks/useSLA.js`.

### Inventory Module
`src/pages/Inventory.jsx` (accessible to `maintenance_exec` and `finance`) has three tabs managed via local state:
1. **Parts Catalog** — stock levels, low-stock filter; `useUpdatePart` for inline edits, `useBulkUpload` for CSV import via `BulkUploadModal`
2. **Purchase History** — invoice list (`usePurchaseInvoices`), record new purchase via `PurchaseModal`; DB trigger auto-restocks parts when invoice items are inserted
3. **Consumption History** — `usePartConsumption`, shows parts used per job card/mechanic

Hooks split across two files:
- `src/hooks/useInventory.js` — inventory-focused exports: `useParts`, `usePurchaseInvoices`, `usePurchaseInvoiceItems`, `useRecordPurchase`, `useUpdatePart`, `usePartConsumption`, `useVehicleHistory`, `useJobCardParts`, `useMechanicProfile`, `useMechanicActivity`, `useCreatePart`, `usePartUnits`, `useAddPartUnit`, `useDeletePartUnit`
- `src/hooks/useParts.js` — job-card parts: `useParts` (lightweight list), `useAddIssuePart`, `useDeleteIssuePart` — imported by `JobCardDetail` and `IssueWorkCard`

### Suppliers Module
Three pages under `/suppliers` (accessible to `maintenance_exec`, `super_admin`, `finance`):
- `src/pages/Suppliers.jsx` — list with status filter (pending/approved/rejected) and a copyable public registration URL
- `src/pages/SupplierDetail.jsx` — view/approve/reject a supplier; uses `useSupplierById` + `useUpdateSupplierStatus`
- `src/pages/SupplierRegistration.jsx` — **public route** (`/supplier-registration`), no auth required; suppliers fill out and submit their own details

All supplier hooks in `src/hooks/useSuppliers.js`: `useSuppliers`, `useSupplierById`, `useUpdateSupplierStatus`.

### Vehicles Page
`src/pages/Vehicles.jsx` — CRUD for the `vehicles` table (accessible to `maintenance_exec`, `super_admin`, `finance`). Inline add/edit modal, site-filter via `vehicle_sites` join. Uses `useVehicles`, `useCreateVehicle`, `useUpdateVehicle` from `src/hooks/useVehicles.js`. Vehicles are also synced nightly from the Roorides API via the `sync-roorides-vehicles` edge function.

### Scrap / Salvage Module
`src/pages/Scrap.jsx` (`/scrap`, accessible to `maintenance_exec`, `super_admin`, `finance`) — tracks scrap/salvage parts and their disposal. Three tabs via local state: **Scrap Inventory**, **Sale History**, **Write-off History**. The record actions (`RecordSaleModal`, `RecordWriteoffModal`) are hidden for the `finance` role, which is view-only here (`isExec = role !== 'finance'`). Sales are recorded against the `scrap_disposal` table (buyer, payment mode/reference, total value, receipt photos). Tab + modal components live in `src/components/scrap/` (`ScrapInventoryTab`, `SaleHistoryTab`, `WriteoffHistoryTab`, `RecordSaleModal`, `RecordWriteoffModal`).

### Outsource Invoices
`src/pages/OutsourceInvoices.jsx` (`/outsource-invoices`, accessible to `maintenance_exec`, `super_admin`, `finance`, `supervisor`) — payment tracking for outsourced-repair invoices. **This is a separate domain from the purchase invoices in the Inventory module** (no parts/line-items). Surfaces a per-invoice payment status (`Approved`/`Hold`/`Reject`), a derived payment state (`Paid`/`Partially Paid`/`Unpaid`, computed from `approved_amount − advance_amount` vs the sum of `payments`), and a "paid by" field (Accounts/Nithin/Manjunath). Filters + pagination are URL-param driven. Uses `useOutsourceInvoices` + `useOutsourceInvoiceSummary` from `src/hooks/useOutsourceInvoices.js`.

### Feedback / Report
`src/pages/FeedbackReport.jsx` (`/feedback`) — supervisors rate resolved issues with a smiley scale (Good/Ok/Bad) stored in `issues.rating`. Accessible to all authenticated roles; only the ticket's creator supervisor can submit a rating. Uses `useUpdateIssue` from `src/hooks/useIssues.js`.

### Vehicle & Mechanic Detail Pages
- `src/pages/VehicleHistory.jsx` — full job-card history for a specific vehicle; uses `useVehicleHistory(vehicleNumber)` and `useJobCardParts(jobCardId)` for lazy-loaded parts per card
- `src/pages/MechanicDetail.jsx` — profile + job card activity + labour hours for a mechanic; uses `useMechanicProfile` + `useMechanicActivity`

### Auth Pages
`src/pages/auth/ForgotPassword.jsx` and `src/pages/auth/UpdatePassword.jsx` — unauthenticated reset flow; both are public routes (`/forgot-password`, `/update-password`).

`Profile.jsx` (`/profile`) lets any authenticated user change **their password only**. Name, email, role and site are read-only by design — `public.users` has no self-UPDATE policy (so a name save silently affected zero rows for every non-exec role while still reporting success), and `supabase.auth.updateUser({ email })` changes the login address without touching `public.users.email`. Both now go through `/settings/users`, which enforces the role rules server-side and records the change in `user_audit_logs`. **Do not re-add self-service name/email editing here** without first adding a column-restricted self-UPDATE path — a naive self-UPDATE policy would let any user set their own `role`.

### Settings (Nested Routes under `/settings`)
`src/pages/settings/SettingsLayout.jsx` wraps a sidebar + `<Outlet>`. Sub-routes:
- `/settings/notifications` — `NotificationSettings.jsx`, reads/writes `user_settings.notify_daily_digest`
- `/settings/users` — embeds `Users` page with `embedded={true}` prop
- `/settings/sla` — embeds `SLASettings` with `embedded={true}` prop
- `/settings/units` — `PartUnitsSettings.jsx`, CRUD for `part_units` table (unit labels for parts)

### Analytics & Export
`src/pages/Analytics.jsx` uses **recharts** for charts. `xlsx` is available for spreadsheet export (used in inventory/analytics exports).

### Component Directory Structure
`src/components/` is organized by domain:
- `shared/` — reusable UI primitives: `Navigation`, `SLATimer`, `SearchableSelect`, `CustomInput`, `CustomSelect`, `FilterSelect`, `LoadingSkeleton`
- `tickets/` — `TicketCard`, `TicketForm`, `TicketList`, `TicketTimeline`, `StatusAccordion`, `DateRangeFilter`, `PhotoUpload`, `FeedbackModal`, `RejectTicketModal`
- `job-cards/` — `IssueWorkCard` (inline issue editing within a job card)
- `inventory/` — `PurchaseModal`, `EditPartModal`, `EditPurchaseModal`, `BulkUploadModal`
- `users/` — `AddUserModal`, `DocumentUpload`
- `suppliers/` — supplier-related modals

### Debug Utilities
`window.testResend(email)` is exposed in App.jsx for testing email via the `send-email` edge function from the browser console.

### Migrations
`supabase/migrations/` contains migration files built incrementally. Schema source of truth: `docs/schema.sql` (full schema) and `src/types/database.types.ts` (TypeScript types) are auto-generated via `npm run schema:dump`. Read these for the complete table/column/trigger picture. Do not trust any other schema reference. When making schema changes, write a new migration file rather than modifying existing ones.

### Environment Variables
```
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
VITE_GOOGLE_DRIVE_FOLDER_ID
VITE_APP_NAME
```
Edge functions use `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`, `RESEND_API_KEY`, `GOOGLE_SERVICE_ACCOUNT_EMAIL`, `GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY` — set in the Supabase dashboard under Edge Function secrets.
