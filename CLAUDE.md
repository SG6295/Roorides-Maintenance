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
| `finance` | Finance entries, inventory, purchase invoices, vehicles; read-only job cards (MAIN-88) |

**Finance reads job cards through SELECT-only policies (MAIN-88).** `"Finance view job cards"` alone left a card's issues, parts, ticket numbers and mechanic name invisible, because each lives in its own RLS-protected table. Finance therefore also has SELECT on `issues`, `issue_parts` and `tickets`, plus `users` rows whose role is `mechanic`/`electrician` — all via `is_finance()`, which exists because a `users` policy that queries `users` recurses. Finance has no write path onto a job card; `JobCardDetail` shows the invoice details and file read-only to every non-exec (`invoiceReadOnly`).

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
| `sync-roorides-vehicles` | Authenticates with Roorides, fetches all vehicles for org 126 (via `ROORIDES_ORG_ID` secret), and upserts them into the local `vehicles` table. Never overwrites the `site` column. Called by pg_cron at midnight UTC daily and also manually via the "Refresh vehicle list" button on the ticket form. Credentials: `ROORIDES_USERNAME`, `ROORIDES_PASSWORD`, `ROORIDES_ORG_ID` secrets. **See the `sites` note below — the sync owns `sites.is_active`.** It owns `vehicles.is_active` the same way, and since MAIN-68 it is also the only thing that can create a vehicle at all — see the `vehicles` note below. |
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
SLA windows are configured in the `sla_rules_config` table (editable via the SLA Settings page — `super_admin` can write, `maintenance_exec` can view). Database triggers auto-calculate `sla_end_date` and `sla_status` (Pending/Adhered/Violated) per issue. Holiday calendar in `holidays` table and weekly-offs in `system_settings` key `sla_weekly_offs` are used for business-day calculations. Timeline events are stored in `sla_events` and surfaced via `useSLAEvents(ticketId)` in `src/hooks/useSLA.js`.

> **There is no `sla_rules` table.** Two tables once held SLA day-counts: the settings page wrote `sla_rules` while the triggers always read `sla_rules_config`, so UI edits changed a row nothing consumed and the two drifted. MAIN-47 made `sla_rules_config` the single source and dropped the decoy. Don't re-add `sla_rules` to anything — it lingered in `backup-to-drive`'s table list long afterwards, logging a failed read on every hourly run.

### Inventory Module
`src/pages/Inventory.jsx` (accessible to `maintenance_exec` and `finance`) has three tabs managed via local state:
1. **Parts Catalog** — stock levels, low-stock filter; `useUpdatePart` for inline edits, `useBulkUpload` for CSV import via `BulkUploadModal`
2. **Purchase History** — invoice list (`usePurchaseInvoices`), record new purchase via `PurchaseModal`; DB trigger auto-restocks parts when invoice items are inserted
3. **Consumption History** — `usePartConsumption`, shows parts used per job card/mechanic

**Purchase invoices are saved only through `save_purchase_invoice(p_invoice_id, p_invoice, p_items)` (MAIN-97).** Create (`p_invoice_id` null) and edit both go through it, so the header, line deletes/updates/inserts and `total_amount` commit or roll back together — the old five-call sequence left an invoice half-saved when a later line's stock check failed. It is `SECURITY INVOKER`, so the exec/finance RLS policies still decide who may save. It writes the header first so a workshop change moves the stock before any line changes (MAIN-72), and takes `total_amount` from the generated `line_total` column. Lines travel as `jsonb`: **do not add a parameter** — under `CREATE OR REPLACE` that creates a second overload rather than replacing it.

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
`src/pages/Vehicles.jsx` — list + edit for the `vehicles` table (accessible to `maintenance_exec`, `super_admin`, `finance`). Search, site-filter via `vehicle_sites` join, and an inline **edit-only** modal. Uses `useVehicles` and `useUpdateVehicle` from `src/hooks/useVehicles.js`. Vehicles are synced nightly from the Roorides API via the `sync-roorides-vehicles` edge function.

**`vehicles` is feed-owned and has no create path — like `sites`, but with an edit UI.** Since MAIN-68 a vehicle can only be created by `sync-roorides-vehicles`. There is no Add Vehicle button, no `useCreateVehicle` hook, and the RLS policy `"Exec and finance update vehicles"` is **UPDATE-only**, so a browser client cannot INSERT or DELETE a vehicle even by calling PostgREST directly. Anything missing is fixed at source in Roorides. The only writer that can create rows is the sync itself, which uses the service-role key and bypasses RLS. Rows are never deleted (`tickets.vehicle_number` and `job_cards.vehicle_number` are free text, so history survives regardless) — departure is expressed as `is_active = false`.

The old `FOR ALL` policy was named `"Exec and finance manage vehicles"`; MAIN-68 dropped and recreated it under the new name, because `ALTER POLICY` cannot change a policy's command and the schema's convention is that `manage` denotes `FOR ALL` while `update` denotes `FOR UPDATE`.

**Only `year` and `notes` are editable.** Every other column — `registration_number`, `make`, `model`, `type`, `is_active`, `raw_data` — is rewritten by the sync on every run, so a local edit to one would be silently reverted within 24 hours. The edit modal therefore shows make/model, site and status read-only and offers inputs for year and notes alone. Note RLS gates rows, not columns: an exec could still PATCH a sync-owned column directly against PostgREST. The UI does not offer it and the sync corrects it nightly, which is the same posture `sites` has.

**`is_active` is sync-owned and not user-editable.** A vehicle is active exactly when the current Roorides feed still returns it — the same two-way rule `sites` gets. The Edit modal had an Active checkbox until MAIN-68 removed it: MAIN-69 made the column machine-owned, so any toggle was reverted by the next sync. This is the same failure mode that is the stated reason there is no Sites settings page. Before MAIN-69 nothing ever revisited the flag, so a vehicle that left the feed kept `is_active = true` forever while `vehicle_sites` was rebuilt without it — leaving 69 rows in prod that no supervisor could see (their vehicle list is site-filtered) but every exec could still pick (a blank Site field means an unfiltered list).

Feed-owned means `raw_data IS NOT NULL`. MAIN-69's `is_active` rule still filters on it, and MAIN-68 deliberately kept that filter: with no create path it is a harmless no-op, and removing it would only cost the guard if a manual row ever reappeared. The carve-out originally existed to protect two hand-added rows in prod (`KA-01-AB-1234`, `KA-01-AB-5678`) — both build placeholders created 2025-12-27 with zero tickets, zero job cards and no `vehicle_sites` links, retired under MAIN-68. No hand-added vehicle can exist from here on.

### Scrap / Salvage Module
`src/pages/Scrap.jsx` (`/scrap`, accessible to `maintenance_exec`, `super_admin`, `finance`) — tracks scrap/salvage parts and their disposal. Three tabs via local state: **Scrap Inventory**, **Sale History**, **Write-off History**. The record actions (`RecordSaleModal`, `RecordWriteoffModal`) are hidden for the `finance` role, which is view-only here (`isExec = role !== 'finance'`). Sales are recorded against the `scrap_disposal` table (buyer, payment mode/reference, total value, receipt photos). Tab + modal components live in `src/components/scrap/` (`ScrapInventoryTab`, `SaleHistoryTab`, `WriteoffHistoryTab`, `RecordSaleModal`, `RecordWriteoffModal`).

**Scrap defaults live in the part master.** A part can carry `default_exclude_from_scrap` + `default_exclusion_reason` (set via the checkbox column in the Parts Catalog, or from the closure modal — see below). `ScrapDecisionModal` seeds those rows as "Exclude from scrap" with the reason pre-filled and collapses them to a single line with a "Default" badge, so consumables need no interaction at closure. The exec can still override per job card; overriding never writes back to the part. The reason is constrained to `consumable` / `destroyed_on_removal` (`parts_default_exclusion_reason_check`) — `other` would need a per-exclusion note the part master cannot supply, and would pre-fill a state the RPC's `MISSING_EXCLUSION_NOTES` guard rejects. Reason labels are single-sourced in `src/constants/scrapExclusion.js`; keep `DEFAULT_EXCLUSION_REASON_OPTIONS` in step with the DB constraint. Each exclusion decision carries `from_default`, stored on `scrap_excluded_parts.from_part_default` — descriptive telemetry only, nothing reads it to make a decision.

**Defaults can also be set from the closure modal, and that write is server-side.** A decision may carry `set_as_default` or `clear_default`, and `close_job_card_with_scrap` updates `public.parts` inside the closure transaction — a client write after the RPC returned could leave a standing default behind on a closure that failed. Ticking any of those checkboxes routes Confirm-and-Complete through a second confirmation listing every affected part, because a part default outlives the job card it was set from. The RPC returns `part_default_changes` (real changes only, no-ops omitted) purely so the client can write the `parts` audit rows; nothing else reads it. Offers are keyed by **part**, not by `issue_part` — a part can appear on one card twice and can only carry one default, and the RPC rejects contradictory directives with `CONFLICTING_PART_DEFAULTS` rather than letting payload order decide. **Do not add a parameter to `close_job_card_with_scrap`** — the new fields live inside the `p_scrap_decisions` jsonb precisely so the signature stays a single 4-argument version; adding a parameter under `CREATE OR REPLACE` creates a second overload instead of replacing the first, which is how the orphan MAIN-57 had to drop came about.

### Outsource Invoices
`src/pages/OutsourceInvoices.jsx` (`/outsource-invoices`, accessible to `maintenance_exec`, `super_admin`, `finance`, `supervisor`) — payment tracking for outsourced-repair invoices. **This is a separate domain from the purchase invoices in the Inventory module** (no parts/line-items). Surfaces two payment statuses, the payments recorded against each invoice, and a "paid by" field whose options live in `PAID_BY_OPTIONS` (`src/constants/outsourceInvoices.js`), mirrored by the `outsource_invoices_paid_by_check` constraint — change both together. Filters + pagination are URL-param driven. Uses `useOutsourceInvoices` + `useOutsourceInvoiceSummary` from `src/hooks/useOutsourceInvoices.js`; the table's parts and the drawer live in `src/components/outsource-invoices/`.

**Two statuses, two owners (MAIN-90).** `maintenance_payment_status` (`Approved`/`Hold`/`Reject`, labelled "Payment status reported by maintenance") is the exec's decision on the job card closure form; it was called `payment_status` until MAIN-90. `finance_payment_status` (default `Due`) and `finance_remark` are finance's, set from the Outsource Invoices drawer and labelled "Payment status reported by finance". Neither overwrites the other. Ownership is enforced by the `guard_outsource_invoice_status_owners` trigger rather than RLS, because RLS gates rows, not columns, and exec, finance and supervisor all hold UPDATE on the table: only `finance` and `super_admin` may change the finance columns, `finance` may not change the maintenance one, and service-role writes (NULL `auth.uid()`) pass. Both value lists live in `src/constants/outsourceInvoices.js` and mirror their CHECK constraints. `get_outsource_invoice_summary` takes `p_maintenance_payment_status` and `p_finance_payment_status` by name; its parameter was renamed by `DROP` + `CREATE`, because `CREATE OR REPLACE` cannot rename a parameter and would leave a second overload behind.

**Payments and the status they drive (MAIN-95).** Finance records one or more payments per invoice — Paid value, TDS, date, posted ledger, method, and bank + UTR for every method but cash — and cancels one whose transaction failed (`status = 'Cancelled'` with a required reason; rows are never deleted, and cancelled ones drop out of every total). Writes go only through `record_outsource_invoice_payment` and `cancel_outsource_invoice_payment`, which check for `finance`/`super_admin`, lock the invoice row, refuse an overpayment and recalculate `finance_payment_status` in the same transaction; there is no client INSERT policy on `outsource_invoice_payments`. Payable = Approved − Advance; Settled = active Paid + TDS + Round-off; the status is **Due** at 0, **Partly Paid** below Payable and **Paid** at Payable, overriding whatever finance had set. `Partly Paid` and `Paid` exist only through that recalculation (`apply_finance_status_recalc` raises a transaction-local `app.finance_status_recalc` flag the guard lets through) — the guard refuses them by hand, for super_admin too, since that is data integrity rather than permission. Changing Approved/Advance recalculates only once money has moved. Round-off (`< ₹1`, only when it settles the invoice exactly) exists for payments rounded to the rupee. The database compares amounts in `numeric`; the form uses paise via `src/utils/settlement.js` and never trusts floats. Payment names come from `get_outsource_invoice_payments`, because finance cannot read exec/finance profiles. A job card's reopen lock counts active payments only.

**Invoice history (MAIN-96).** Triggers `outsource_invoices_audit` and `outsource_invoice_payments_audit` write every change to `audit_logs` — the invoice's person-decided fields (both statuses, finance remark, Paid By, the three amounts, pay-by date; not timestamps) and every payment recorded or cancelled, payments under their own id. Being triggers, they capture the closure form, the drawer, the payment RPCs and direct API calls alike. The drawer reads them through `get_outsource_invoice_history`, which attaches performer names (finance cannot read exec/finance profiles) and, for invoices created before the history existed, synthesises a "Created by" entry from the row itself. A status change made by the payment recalculation shares the payment's transaction timestamp and performer, and `foldStatusChanges` (`src/components/outsource-invoices/historyEntries.js`) shows the two as one line.

**Edits happen in the table; the drawer shows history only (MAIN-98).** Finance and super_admin change Finance Status (`FinanceStatusCell`, saves on pick) and Finance Remark (`RemarkCell`, Enter/blur saves, Esc cancels) in their cells, and record or cancel payments in the strip a row's ▸ opens (`PaymentStrip` — anyone can open it, only finance gets the controls). `useUpdateFinancePaymentStatus` writes only the fields it is given, so the two cells cannot overwrite each other. Clicking a row expands that strip, unless the click lands on something interactive (`isInteractiveClick`). The strip is pinned to the visible part of the table — `sticky left-0`, sized by a ResizeObserver to the scroll box's `clientWidth` — so it stays in view however far the table is scrolled sideways. The drawer opens from the row's View history button and shows only the history; the invoice file's View/Copy buttons are the Invoice Link column. Columns are defined as data in `columns.js` (`default` flags = the set everyone sees) and drawn by `InvoiceCell.jsx`; `ColumnManager` shows/hides them for the session only — nothing is saved. Dropdowns inside the sideways-scrolling table are not clipped because `CustomSelect` already anchors its list in a portal (Headless UI v2 `anchor`).

**Multi-vehicle invoices (MAIN-99).** One vendor invoice for work on many vehicles — hub greasing fifteen buses at a parking location — is recorded with **no ticket and no job card**. `batch_services` holds the work (description, supplier, and the invoice file, since on a job card the file lives on `job_cards.invoice_url`); `batch_service_vehicles` holds one line per vehicle with its **site** and its share of the approved amount. Site is per line because one invoice can cover buses from several sites: the form fills it from the vehicle's `vehicle_sites` links — fixed when there is one, a choice among them when there are several, any active site when there are none — and a saved site the bus has since left stays selectable. The database only requires that a site is present (`LINE_SITE_REQUIRED`), never that it is one of the vehicle's current sites: those links are rebuilt nightly, so that rule would make an old batch uncorrectable once its bus moved. The column is nullable for the prod→staging sync and enforced by the save function. The invoice is an ordinary `outsource_invoices` row with `batch_service_id` set instead of `job_card_id` (`outsource_invoices_one_owner_check` requires exactly one), so payments, both statuses, the triggers, the summary tiles and the history work unchanged. Pages: `/batch-invoices/new` and `/batch-invoices/:id` (`BatchServiceDetail.jsx`), reached from "+ Multi-vehicle invoice" on the Job Cards and Outsource Invoices pages; in the list a batch shows "Batch" / "N vehicles", and Vehicle History merges each vehicle's line in among its job cards.

Both tables have **SELECT policies only** (exec, super_admin, finance — the same people who can read job cards); every write goes through `save_batch_service_invoice(p_batch_id, p_batch, p_invoice, p_lines)`, which is `SECURITY DEFINER` with its own exec check as its first statement. That is what holds the rules no row policy can: the lines add up to the approved amount exactly (compared in `numeric`; the form uses paise via `src/utils/batchSplit.js`), no vehicle appears twice, and **nothing changes once an active payment exists** (it locks the invoice row first, as `record_outsource_invoice_payment` does). Lines are matched on `vehicle_number`, so an unchanged line writes no history. Its arguments after the id are `jsonb` — **do not add a parameter**, for the same overload reason as `save_purchase_invoice`. Changes to a batch's work details and lines are logged by `log_batch_service_change` under the batch's id and shown in the invoice history; `groupBatchLines` folds one save's line changes into a single entry. The list query keeps batches beside completed job cards by filtering the `job_card` embed to Completed and then `or(batch_service_id.not.is.null, job_card.not.is.null)` — PostgREST rejects `job_card.status` inside an `or()`. The invoice fields themselves are shared with the job card through `InvoiceDetailsFields.jsx` + `invoiceForm.js`.

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
