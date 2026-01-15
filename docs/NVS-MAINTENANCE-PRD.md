# NVS Maintenance Management System
## Product Requirements Document v2.0

**Last Updated:** December 29, 2025  
**Product Manager:** [Your Name]  
**Tech Stack:** React + Supabase + Google Drive API  
**Deployment:** Vercel (free tier)

**Major Update:** This version introduces a 9-version release roadmap (v0.1 - v0.9) with clear success criteria, dependency mapping, risk mitigation strategies, and technical scalability considerations for handling 1000+ tickets/month. Includes RooRides vehicle integration (v0.8) and bulk parts upload (v0.9).

---

## Executive Summary

Replace manual Google Sheets workflow with a mobile-first web application for managing maintenance of 1000+ vehicles across 60+ client sites.

**Key Metrics:**
- 1000+ vehicles under management
- 60+ client sites
- ~12,000+ historical tickets
- 3 user roles (Supervisors, Maintenance Exec, Finance Team)

**Core Problem:** 
Manual Google Sheets workflow is breaking at scale - duplicate tickets, lost data, slow lookups, no mobile access for field supervisors.

---

## Current System Analysis

### Existing Workflow (Google Sheets)

1. **Supervisor** submits ticket via Google Form
2. **Maintenance Executive** manually copies to "Maintenance register" sheet
   - Deduplicates tickets
   - Combines related tickets
   - Assigns job sheet ID (from physical book)
3. **Maintenance work** performed (in-house or outsourced)
4. **Finance Team** logs expenses via separate Google Form
5. **Supervisors** rate completed work quality

### Pain Points Identified

- Manual copy/paste from form responses to register
- No mobile-friendly interface for field supervisors
- Slow ticket lookups across 60+ site-specific sheets
- SLA violations not visible in real-time
- Finance data disconnected from maintenance tickets
- Dashboard formulas break with large datasets

---

## Technical Architecture

### Stack Decision

```
Frontend:  React 18 + Vite + Tailwind CSS (mobile-first)
Backend:   Supabase (Postgres + Auth + Realtime)
Storage:   Google Drive API (for photos/documents)
Hosting:   Vercel
Cost:      $0/month (free tiers)
```

### Why This Stack?

**Supabase (Database + Auth):**
- Free tier: 500MB DB, 50K users (sufficient for months)
- Built-in auth with row-level security
- Real-time subscriptions for live dashboard updates
- Postgres = handles complex queries (SLA calculations, filtering)

**Google Drive API (File Storage):**
- 15GB free storage (vs Supabase 1GB)
- Already using Google ecosystem
- Familiar to team
- Service account = programmatic access

**React + Vite:**
- Fast dev server
- Mobile-first responsive design
- Single codebase for mobile + desktop

---

## User Roles & Permissions

### 1. Supervisor (Field Role)
**Primary Device:** Mobile  
**Permissions:**
- Submit new maintenance tickets
- Upload photos
- View own site's tickets only
- Filter/search tickets by vehicle, date, status
- Rate completed work (CSAT)
- View dashboard for own site

### 2. Mechanic/Electrician (Field Role)
**Primary Device:** Mobile  
**Permissions:**
- View assigned tickets (all sites)
- Update job sheet details:
  - Odometer reading
  - Work performed (description)
  - Parts used (select from parts library)
  - Labor hours
  - Mark work as complete
- Upload photos (before/after work)
- View job sheet history for vehicle
- **Cannot:**
  - Create new tickets
  - Assign tickets to others
  - Delete tickets
  - View finance data

### 3. Maintenance Executive (Office Role)
**Primary Device:** Desktop (some mobile)  
**Permissions:**
- View ALL tickets across all sites
- Assign tickets to mechanics (job sheet ID, assigned mechanic, date)
- Mark duplicate tickets
- Merge/combine related tickets
- Reject tickets (with reason)
- Update ticket status
- Log expenses:
  - Spare part purchases
  - Outsourced work invoices
  - Job cards (in-house work)
- View global dashboard (all sites, SLA performance)

### 4. Finance Team (Office Role)
**Primary Device:** Desktop  
**Permissions:**
- View expenses logged by maintenance exec
- Make payments against bills:
  - Mark payment status (Pending, Partial, Paid)
  - Upload payment proof
  - Track payment dates
- Review and approve/reject invoices (quality check)
- View expense reports
- Download financial statements
- Reconcile inventory audits
- **Cannot:**
  - Create or log expenses (maintenance exec does this)
  - Modify ticket details

---

## Data Model

### Core Entities

#### 1. Tickets (Maintenance Requests)

```sql
tickets {
  id: uuid PRIMARY KEY
  ticket_number: integer GENERATED (auto-increment from 1434)
  created_at: timestamp
  
  -- From supervisor form
  site: text (dropdown from 60+ sites)
  vehicle_number: text
  category: enum (Mechanical, Electrical, Body, Tyre, GPS/Camera, Other)
  complaint: text
  supervisor_name: text
  supervisor_id: text (employee ID)
  supervisor_contact: text
  photos: text[] (Google Drive URLs)
  remarks: text
  
  -- Assigned by maintenance exec
  impact: enum (Minor, Major)
  job_sheet_id: text (from physical book, initially; later auto-generated)
  assigned_mechanic_id: uuid REFERENCES users (mechanic assigned to do the work)
  assigned_date: date
  activity_plan_date: date
  work_type: enum (In House, Outsource)
  status: enum (Pending, Assigned to Mechanic, Work in Progress, Completed, Rejected)
  
  -- Completion
  completed_date: date
  completion_remarks: text
  
  -- Computed fields
  sla_end_date: date (computed from created_at + SLA days)
  assignment_sla_status: enum (Adhered, Violated)
  completion_sla_status: enum (Adhered, Violated)
  tat_days: integer (days between created and completed)
  
  -- CSAT rating
  rating: enum (Good, Ok, Bad)
  csat_score: integer (Good=2, Ok=1, Bad=0)
  
  -- Metadata
  is_duplicate: boolean DEFAULT false
  merged_into_ticket_id: uuid (if combined with another ticket)
  created_by_user_id: uuid REFERENCES users
}
```

#### 2. Finance Entries

```sql
finance_entries {
  id: uuid PRIMARY KEY
  created_at: timestamp
  
  work_type: enum (Spare Purchases, Outsourced Work, Job Card)
  
  -- Common fields
  activity_date: date
  vehicle_number: text
  job_sheet_id: text (links to ticket)
  ticket_id: uuid REFERENCES tickets (optional)
  site: text
  
  -- Vendor details (for purchases/outsourced)
  vendor_name: text
  vendor_contact: text
  work_description: text
  approved_amount: numeric
  invoice_number: text
  
  -- For job cards (in-house work)
  km_reading: integer
  work_inspected_by: text
  
  -- Payment tracking
  payable_amount: numeric
  advance_amount: numeric
  invoice_value: numeric
  paid_amount: numeric
  payment_date: date
  payment_status: enum (Pending, Partial, Paid)
  transaction_details: text
  payment_via: text
  
  -- Documents (Google Drive URLs)
  bill_attachment: text
  approval_screenshot: text
  job_card_upload: text
  
  -- Metadata
  created_by_user_id: uuid REFERENCES users
  accounting_status: enum (Pending, Processed, Closed)
}
```

#### 3. Users

```sql
users {
  id: uuid PRIMARY KEY
  email: text UNIQUE
  name: text
  employee_id: text
  contact: text
  role: enum (supervisor, mechanic, maintenance_exec, finance)
  site: text (NULL for exec/finance/mechanic with multiple sites, specific site for supervisors)
  assigned_sites: text[] (for mechanics who work across multiple sites)
  is_active: boolean DEFAULT true
  created_at: timestamp
}
```

#### 4. Sites

```sql
sites {
  id: uuid PRIMARY KEY
  name: text UNIQUE
  is_active: boolean DEFAULT true
}
```

#### 5. Vehicles

```sql
vehicles {
  id: uuid PRIMARY KEY
  number: text UNIQUE
  site: text REFERENCES sites(name)
  type: text (e.g., "SWARAJ MAZDA (20+1)")
  is_active: boolean DEFAULT true
}
```

### SLA Rules (From TAT Sheet)

```javascript
const SLA_RULES = {
  "Major-Electrical": 7,
  "Major-Mechanical": 15,
  "Major-Body": 30,
  "Major-Tyre": 15,
  "Major-GPS/Camera": 3,
  "Minor-Electrical": 3,
  "Minor-Mechanical": 3,
  "Minor-Body": 3,
  "Minor-Tyre": 3,
  "Minor-GPS/Camera": 3
};

// Assignment SLA: Must assign within 1 day of creation
const ASSIGNMENT_SLA_DAYS = 1;
```

---

## Version Roadmap

### Versioning Philosophy

Each version delivers **complete, usable functionality** to at least one user group. No half-baked features. No "we'll finish it next version." Every release must:
1. Solve a real pain point completely
2. Be independently deployable
3. Have clear rollback strategy
4. Include success metrics

**Timeline:** Aggressive 2-week sprints. Ship or kill features fast.

---

### 🎯 v0.1: CORE TICKET FLOW + BASIC ADMIN (Weeks 1-2)

**Goal:** Replace Google Form → Sheets workflow for supervisors + enable self-service user management

**Critical Success Criteria:**
- [ ] Supervisors can submit tickets from mobile in <2 min
- [ ] Maintenance exec can view/assign tickets without touching Sheets
- [ ] New users can be added through UI (not SQL)
- [ ] Zero data loss vs Google Sheets
- [ ] 80% of supervisors using app within 1 week of launch

#### Features

**1. Ticket Lifecycle (Supervisors + Maintenance Exec)**
- ✅ Submit ticket form (mobile-optimized)
  - All Google Form fields
  - Photo upload to Google Drive
  - Site/vehicle dropdowns
- ✅ View tickets (role-based)
  - Supervisors: Their site only
  - Maintenance Exec: All tickets
- ✅ Filter & search
  - By site, date range, status, vehicle
  - Vehicle number autocomplete
- ✅ Edit ticket (Maintenance Exec only)
  - Assign job sheet ID
  - Set impact (Minor/Major)
  - Set work type (In House/Outsource)
  - Update status
  - Add comments

**2. Basic User Management (Maintenance Exec)**
- ✅ Add new users via UI
  - Email, name, role, site assignment
  - Auto-generate temporary password
  - Send email with credentials
- ✅ View user list
  - Filter by role, site, active status
- ✅ Deactivate users (soft delete)
- ✅ Role assignment
  - Supervisor (site-restricted)
  - Maintenance Executive (global access)
  - Finance (global access)

**3. Minimal Dashboard**
- ✅ Supervisor view
  - Ticket count by status (Pending, In Progress, Completed)
  - Quick submit button
- ✅ Maintenance Exec view
  - Total tickets (last 7 days, last 30 days, all time)
  - Pending tickets count
  - Tickets by site (bar chart)

**Database Tables:** 
- `tickets`, `users`, `sites`, `vehicles`
- RLS policies for role-based access
- Indexes on frequently queried fields

**Auth:**
- Email/password via Supabase Auth
- Password reset flow
- Session management (7-day expiry)

**Deliverable:** 
- Mobile PWA for supervisors
- Desktop web app for maintenance exec
- Users can onboard themselves after initial admin invite

**v0.1 Exit Criteria:**
- 5+ supervisors successfully submit tickets
- 0 critical bugs in production for 3 days
- Maintenance exec completes 20+ ticket assignments
- Average ticket submission time < 2 minutes

**Known Limitations (Accept for v0.1):**
- No SLA automation (manual calculation)
- No finance module
- No ticket merging
- No advanced dashboards
- No job sheet digitization

---

### 🎯 v0.2: SLA AUTOMATION + ACCESS CONTROL (Week 3)

**Goal:** Automate SLA tracking and harden security/permissions

**Critical Success Criteria:**
- [ ] SLA violations visible in real-time (no manual calculation)
- [ ] Assignment SLA tracked automatically
- [ ] Granular permissions working (supervisors can't see other sites)
- [ ] SLA breach notifications sent

#### Features

**1. SLA Engine**
- ✅ Auto-calculate `sla_end_date` on ticket creation
  - Based on impact + category matrix
  - Account for weekends/holidays (configurable)
- ✅ Assignment SLA tracking
  - Flag if not assigned within 1 day
  - Visual indicator on ticket list
- ✅ Completion SLA tracking
  - Flag if not completed by `sla_end_date`
  - Color-coded: Green (on time), Yellow (due soon), Red (overdue)
- ✅ SLA event logging
  - Record every SLA milestone in `sla_events` table
  - Track: ticket_id, event_type (created, assigned, completed), timestamp, status (adhered/violated)

**2. SLA Management UI (Maintenance Exec)**
- ✅ Configure SLA rules
  - Edit days for each Impact-Category combination
  - Set assignment SLA threshold
  - Define working days (exclude weekends/holidays)
- ✅ View SLA configuration
  - Table view of all rules
  - Edit inline

**3. Enhanced Ticket View**
- ✅ SLA timer display
  - Show days remaining until SLA breach
  - Countdown for assignment SLA
  - Visual warnings (icon + color)
  - **NOTE:** Updated to compact rectangle style in v0.2. Revisit for v2.0 as per user feedback.

- ✅ SLA history timeline
  - Show all SLA events for ticket
  - Created → Assigned → Completed timestamps

**4. Role-Based Access Control (RBAC)**
- ✅ Permission matrix
  - Define what each role can do (CRUD on tickets, users, etc.)
  - Enforce at API level + database RLS
- ✅ Site-level isolation
  - Supervisors hard-locked to their site (cannot bypass)
  - Query performance optimized for filtered access
- ✅ Audit logging
  - Track who did what, when
  - Log table: `audit_log (user_id, action, resource_type, resource_id, timestamp)`

**5. Notification Preferences (All Users)**
- ✅ User settings page
  - Email notification preferences (on/off for each event type)
  - Notification frequency (real-time, daily digest, weekly summary)
  - Contact email (can differ from login email)
- ✅ Supervisor notifications
  - Ticket assigned to site → Email alert
  - Ticket completed → Email notification with rating request
  - Ticket rejected → Email with rejection reason
  - SLA nearing breach → Email reminder
- ✅ Maintenance exec notifications
  - New ticket created → Optional real-time email
  - SLA violation → Critical alert email
  - Finance entry added → Daily digest
- ✅ Finance team notifications
  - Job sheet pending invoice upload → Email reminder
  - Invoice rejected by accounts → Email alert
- ✅ Email templates
  - Professional HTML templates
  - Include ticket details, direct link to app
  - Unsubscribe option (per notification type)

**Database Changes:**
- New table: `sla_events`
- New table: `sla_rules` (configurable SLA matrix)
- New table: `audit_log`
- New table: `notification_preferences` (user_id, notification_type, enabled, frequency)
- Add computed fields to `tickets`: `assignment_sla_status`, `completion_sla_status`, `days_remaining`

**Deliverable:**
- SLA violations auto-flagged
- Permissions tested against privilege escalation attacks
- Maintenance exec can adjust SLA rules without code changes
- Users control their notification preferences
- Email notifications working for ticket updates

**v0.2 Exit Criteria:**
- SLA calculations match manual calculation for 100 sample tickets
- No permission bypass vulnerabilities found in security review
- SLA breach alerts working for 5 test tickets
- Email notifications delivered within 5 minutes of event
- Unsubscribe feature tested (users can opt-out)

---

### 🎯 v0.3: ANALYTICS DASHBOARD + FINANCE MODULE (Week 4-5)

**Goal:** Give management visibility into performance + integrate finance tracking

**Critical Success Criteria:**
- [ ] Boss can view SLA performance without asking
- [ ] Finance team can log expenses and link to tickets
- [ ] Dashboard replaces Google Sheets for reporting

#### Features

**1. Advanced Dashboard (All Roles)**
- ✅ SLA Performance Dashboard
  - Date range selector (last 7, 30, 90 days, custom)
  - SLA adherence rate (% on-time completions)
  - Breakdown by site, category, impact
  - Charts: Line (trend), Bar (by site), Pie (by category)
- ✅ Site-wise analysis
  - Top violating sites
  - Average TAT by site
  - Ticket volume heatmap
- ✅ Export functionality
  - Export data to Excel
  - Include filters applied
  - Schedule email reports (future: V5)

**2. Finance Module**
- ✅ Log expenses (Finance Team)
  - Spare part purchases
  - Outsourced work invoices
  - Job cards (in-house work)
  - Link to job sheet ID / ticket ID
- ✅ Expense tracking
  - Payment status (Pending, Partial, Paid)
  - Payment date, transaction details
  - Upload bill/invoice attachments (Google Drive)
- ✅ Finance dashboard
  - Total spend by month, site, category
  - Outstanding payments (aging report)
  - Top vendors by spend

**Database Changes:**
- Table: `finance_entries` (already in PRD schema)
- Link `finance_entries.ticket_id` to `tickets.id`
- Add indexes for fast reporting queries

**Deliverable:**
- Real-time dashboard accessible to management
- Finance team stops using separate Google Form
- End-to-end ticket-to-payment tracking

**v0.3 Exit Criteria:**
- Dashboard loads in <3 seconds for 12,000+ tickets
- Finance entries correctly linked to 95% of tickets
- Boss can answer "SLA performance last month?" in <1 minute

---

### 🎯 v0.4: JOB SHEET DIGITIZATION + PARTS LIBRARY (Week 6-7)

**Goal:** Eliminate physical job sheet book + enable parts inventory tracking

**Prerequisites (MUST COMPLETE BEFORE STARTING V4):**
- [ ] Business process study on ticket merging/rejection workflow
- [ ] Interview maintenance exec on job sheet usage patterns
- [ ] Analyze 50+ physical job sheets to extract common patterns

#### Features

**1. Digital Job Sheets**
- ✅ Create job sheet from ticket
  - Auto-populate vehicle, complaint details
  - Add work performed, parts used, labor hours
  - Capture km reading, inspector signature
  - Generate job sheet number (auto-increment)
- ✅ Link multiple tickets to one job sheet
  - Merge related tickets workflow
  - Mark duplicate tickets
  - View merged ticket history
- ✅ Reject tickets
  - Reason selection (Duplicate, Invalid, Out of Scope)
  - Automatic status update
  - Notification to supervisor

**2. Parts Library**
- ✅ Master parts catalog
  - Part number, name, category, unit
  - Standard cost (for estimation)
  - Supplier info
- ✅ Link parts to job sheets
  - Select from parts library
  - Quantity used
  - Auto-calculate cost estimate
- ✅ Parts usage reporting
  - Most used parts
  - Cost analysis by part
  - Identify high-cost categories

**Database Changes:**
- Table: `job_sheets`
- Table: `parts_library`
- Table: `job_sheet_parts` (many-to-many link)
- Table: `ticket_relationships` (for merging)

**Deliverable:**
- Physical job sheet book retired
- Maintenance exec can merge tickets in <30 seconds
- Parts library with 100+ common parts pre-populated

**v0.4 Exit Criteria:**
- 20+ job sheets created digitally
- Ticket merge/reject workflow tested with real users
- Parts library covers 80% of actual usage

---

### 🎯 v0.5: INVENTORY MANAGEMENT (Week 8-9)

**Goal:** Track spare parts inventory from purchase to consumption

**Critical Success Criteria:**
- [ ] Finance team can inward spares through UI
- [ ] Job sheets consume inventory automatically
- [ ] Inventory reports match physical stock within 5% variance

#### Features

**1. Inventory Inward**
- ✅ Purchase order tracking
  - PO number, vendor, date, items
  - Received quantity vs ordered quantity
  - Link to finance entry (for payment tracking)
- ✅ Stock entry
  - Select part from library
  - Quantity, unit cost, batch/lot number
  - Auto-update inventory balance

**2. Consumption Tracking**
- ✅ Auto-consume from job sheets
  - When parts added to job sheet, reduce inventory
  - Track consumption by site, vehicle, category
  - Alert on low stock levels
- ✅ Manual adjustments
  - For damaged, lost, or returned parts
  - Reason required (audit trail)

**3. Inventory Reports**
- ✅ Stock summary
  - Current balance by part
  - Valuation (quantity × unit cost)
  - Movement history (in/out)
- ✅ Consumption analysis
  - Top consuming sites
  - Seasonal trends
  - Reorder recommendations (based on usage rate)
- ✅ Export to Excel

**Database Changes:**
- Table: `inventory_transactions`
- Table: `purchase_orders`
- Add triggers for auto-consumption on job sheet creation

**Deliverable:**
- Real-time inventory visibility
- Automated consumption reduces manual tracking
- Monthly inventory reports for finance

**v0.5 Exit Criteria:**
- 50+ inventory transactions processed
- Consumption matches job sheet usage for 95% of parts
- Stock reports downloaded by finance team weekly

---

### 🎯 v0.6: ACCOUNTS & RECONCILIATION (Week 10-11)

**Goal:** Close the loop on financial tracking and inventory audits

**Critical Success Criteria:**
- [ ] Finance team can reconcile invoices vs payments
- [ ] Inventory audit variance tracked and resolved
- [ ] All financial reports downloadable

#### Features

**1. Invoice Management**
- ✅ View invoices
  - Filter by status (Pending, Paid, Overdue)
  - Aging report (30, 60, 90+ days)
  - Link to finance entry
- ✅ Mark as paid
  - Payment date, amount, transaction ref
  - Upload payment proof (bank statement screenshot)
  - Auto-update finance entry status
- ✅ Generate statements
  - Vendor statements (amount owed by vendor)
  - Site-wise expense summary
  - Monthly/quarterly reports

**2. Bill Tracking**
- ✅ Track unpaid bills
  - Due date reminders
  - Escalation alerts (overdue by X days)
  - Payment priority ranking
- ✅ Bulk payment processing
  - Select multiple bills
  - Record payment details once
  - Download payment summary for bank transfer

**3. Inventory Audit & Reconciliation**
- ✅ Upload audit results
  - Spreadsheet import of physical count
  - Compare with system inventory
  - Identify variances (overstock, shortages)
- ✅ Reconcile differences
  - Investigate discrepancies
  - Adjust inventory (with reason/approval)
  - Track adjustment history
- ✅ Audit history
  - View past audits
  - Variance trends over time
  - Identify chronic issues (theft, wastage)

**4. Invoice Quality Review & Pushback (Accounts Team)**
- ✅ Job sheet review queue
  - List of job sheets pending invoice verification
  - Filter by upload date, site, amount
  - Prioritize high-value invoices (>₹10,000)
- ✅ Invoice image review
  - View uploaded invoice images (zoom, rotate, download)
  - Check for clarity, completeness, authenticity
  - Flag issues: blurry, partial, illegible, wrong document
- ✅ Pushback workflow
  - Reject job sheet with reason selection:
    - Poor image quality (blurry/dark)
    - Incomplete invoice (missing details)
    - Wrong document uploaded
    - Mismatch (invoice amount ≠ claimed amount)
  - Add comments (specific instructions for re-upload)
  - Notify maintenance exec via email + in-app
  - Status: "Pending Re-upload"
- ✅ Re-upload & re-review
  - Maintenance exec receives notification
  - Re-upload invoice (replaces old one)
  - Job sheet goes back to review queue
  - Accounts team re-reviews
  - Track number of rejections (quality metric)
- ✅ Approval workflow
  - Mark as "Approved" when invoice quality acceptable
  - Auto-populate payment details from approved invoice
  - Move to payment processing queue

**Database Changes:**
- Table: `invoice_payments`
- Table: `inventory_audits`
- Table: `inventory_adjustments`
- Table: `job_sheet_reviews` (accounts review history: job_sheet_id, reviewer_id, status, rejection_reason, comments, reviewed_at)
- Add fields to `job_sheets`: `review_status` (enum: Pending Review, Approved, Rejected, Re-uploaded), `rejection_count`, `last_reviewed_at`

**Deliverable:**
- Finance team has complete payment lifecycle visibility
- Inventory audits reconciled within 24 hours of physical count
- Accounts module eliminates separate spreadsheets
- Invoice quality enforced through review workflow
- Maintenance exec receives clear feedback on rejected invoices

**v0.6 Exit Criteria:**
- 100% of invoices tracked from receipt to payment
- First inventory audit completed end-to-end
- Finance team reports 50% time savings on reconciliation
- Invoice rejection workflow tested (accounts team rejects 5 test invoices successfully)
- Re-upload notification received within 5 minutes of rejection

---

### 🎯 v0.7: FEEDBACK & CONTINUOUS IMPROVEMENT (Week 12)

**Goal:** Close feedback loop with supervisors to improve service quality

**Critical Success Criteria:**
- [ ] Supervisors rate completed work consistently
- [ ] Feedback SLA enforced (must rate within X days)
- [ ] Low ratings trigger corrective action

#### Features

**1. Enhanced Feedback Collection**
- ✅ Post-completion feedback
  - Automatic prompt when ticket marked complete
  - Rating: Good (2), Ok (1), Bad (0)
  - Comment field (mandatory for Bad ratings)
  - Photo upload (for quality issues)
- ✅ Feedback SLA for supervisors
  - Must rate within 3 days of completion
  - Reminder notifications (email/SMS)
  - Escalate to site manager if no response

**2. Quality Monitoring**
- ✅ Feedback dashboard
  - Average CSAT score by site, category, maintenance exec
  - Trend analysis (improving/declining)
  - Highlight consistently low-rated work
- ✅ Action triggers
  - Alert maintenance exec if rating < 1.5
  - Flag vendor if 3+ Bad ratings in a month
  - Generate improvement plan template

**3. Supervisor Recognition**
- ✅ Leaderboard
  - Top sites by feedback completion rate
  - Most engaged supervisors
  - Gamification (badges for consistent raters)

**Database Changes:**
- Table: `feedback_sla_events`
- Add computed fields: `avg_csat_score`, `feedback_completion_rate`

**Deliverable:**
- Feedback loop closes within 3 days of work completion
- Management has visibility into service quality trends
- Culture of accountability established

**v0.7 Exit Criteria:**
- 80%+ feedback completion rate within SLA
- CSAT trends tracked for 30+ days
- First corrective action taken based on low ratings

---

### 🎯 v0.8: VEHICLE MODULE & SERVICE HISTORY (Week 13-14)

**Goal:** Integrate with RooRides for vehicle + site data + maintain comprehensive service history linked to odometer readings

**Critical Success Criteria:**
- [ ] Vehicle data synced from RooRides successfully
- [ ] Site information synced from RooRides (replaces manual site entry)
- [ ] Service history tracked per vehicle with odometer progression
- [ ] Odometer readings from job sheets auto-populate service history
- [ ] Invalid odometer readings flagged (e.g., decreasing values)

#### Features

**1. RooRides Integration**
- ✅ API integration with RooRides
  - **Fetch site master data** (site name, location, manager contact, operational status)
  - Fetch vehicle master data (number, type, registration, model)
  - Sync vehicle assignments to sites
  - Update vehicle status (active, inactive, under maintenance)
  - Handle API authentication & rate limits
- ✅ Automatic site & vehicle sync
  - Scheduled sync (daily at 2 AM for sites, hourly for vehicles)
  - Manual refresh option (button in admin panel)
  - Conflict resolution (if site/vehicle exists in both systems)
  - Audit log of synced sites and vehicles
  - **Map RooRides site IDs to internal site references**

**2. Enhanced Vehicle Management**
- ✅ Vehicle profile page
  - All vehicle details from RooRides
  - Assigned site, current status
  - Edit vehicle info (with sync to RooRides if bidirectional)
- ✅ Vehicle search & filtering
  - By site, type, status, registration number
  - Quick lookup from ticket creation form
  - Autocomplete with vehicle details preview

**3. Service History Tracking**
- ✅ Automated service history
  - Every completed job sheet creates service record
  - Link to ticket, job sheet, parts used, cost
  - Odometer reading captured from job sheet
  - Service date, type of work, supervisor rating
- ✅ Service timeline view
  - Chronological list of all services for a vehicle
  - Filter by date range, service type, site
  - Visual timeline with milestones
  - Show service frequency patterns

**4. Odometer Validation**
- ✅ Odometer reading validation
  - Check for decreasing readings (flag errors)
  - Alert if reading increases by >10,000 km since last service
  - Show odometer trend chart per vehicle
  - Estimate next service due based on km intervals
- ✅ Service interval tracking
  - Define standard service intervals (e.g., every 5,000 km)
  - Alert when vehicle due for service
  - Preventive maintenance scheduling

**5. Vehicle Analytics**
- ✅ Vehicle performance dashboard
  - Service frequency by vehicle
  - Average cost per vehicle
  - High-maintenance vehicles (red flag list)
  - Downtime tracking (days in maintenance)
- ✅ Fleet health overview
  - % of fleet with overdue services
  - Average km per vehicle
  - Cost per km analysis

**Database Changes:**
- Table: `roorides_sync_log` (track sync history)
- Table: `service_history` (one record per completed job sheet)
- Add fields to `vehicles`: `roorides_id`, `registration_number`, `model`, `last_sync_at`
- Add fields to `job_sheets`: `odometer_reading`, `estimated_next_service_km`
- Add computed fields: `total_services`, `average_service_cost`, `last_service_date`

**API Integration Requirements:**
- RooRides API endpoint documentation
- API key / OAuth credentials
- Rate limit: Assume 1000 requests/day (plan accordingly)
- Sync strategy: Full sync daily + incremental updates hourly
- Error handling for API downtime (use cached data)

**Deliverable:**
- Vehicle data always in sync with RooRides
- Complete service history per vehicle with odometer tracking
- Alerts for overdue maintenance based on km intervals
- Fleet analytics for proactive maintenance planning

**v0.8 Exit Criteria:**
- 100% of vehicles synced from RooRides
- Service history shows for 50+ vehicles with multiple records
- Odometer validation catches at least 1 test error
- Fleet dashboard loads in <2 seconds

**Risks:**
- **RooRides API unavailable:** Implement caching + manual vehicle entry fallback
- **Odometer reading errors:** Require maintenance exec review before finalizing job sheet
- **Sync conflicts:** Implement "last write wins" with conflict log for manual review

---

### 🎯 v0.9: BULK PARTS/SKU UPLOAD (Week 15)

**Goal:** Enable bulk upload of parts catalog via flat files (CSV/Excel) to avoid manual entry

**Critical Success Criteria:**
- [ ] Parts library can be populated via CSV upload
- [ ] File validation catches errors before import
- [ ] Duplicate detection prevents library corruption
- [ ] Upload history tracked for auditing

#### Features

**1. Flat File Upload Interface**
- ✅ File upload component
  - Accept CSV and Excel (.xlsx) files
  - Drag-and-drop + file browser
  - Max file size: 5MB (configurable)
  - Template download option (pre-formatted CSV/Excel)
- ✅ File preview before import
  - Show first 10 rows for validation
  - Column mapping interface (if headers don't match)
  - Display detected issues (missing required fields, invalid data types)
  - Allow user to fix or abort

**2. Data Validation & Cleaning**
- ✅ Pre-import validation
  - Required fields: part_number, part_name, category, unit
  - Data type checks (cost must be numeric, category must match enum)
  - Duplicate detection (same part_number already exists)
  - Invalid character stripping (remove special chars from part numbers)
- ✅ Validation error reporting
  - Show errors in UI with row numbers
  - Export error report (CSV with issues highlighted)
  - Allow partial import (skip errored rows, import valid ones)
  - Or require all-or-nothing import

**3. Import Modes**
- ✅ Add new parts only
  - Skip existing part_numbers
  - Only insert new records
- ✅ Update existing parts
  - Match on part_number
  - Update fields (name, cost, supplier)
  - Track changes in audit log
- ✅ Replace entire catalog
  - Delete all existing parts
  - Import fresh data
  - **Requires admin confirmation (dangerous operation)**

**4. Upload History & Audit Trail**
- ✅ Track all uploads
  - Who uploaded, when, which file
  - Number of records added/updated/failed
  - Original file stored (for rollback)
- ✅ Rollback capability
  - Undo last upload (if errors found post-import)
  - Restore previous catalog state
  - Show diff of what changed

**5. Bulk SKU Management**
- ✅ SKU/Part number normalization
  - Auto-format part numbers (e.g., uppercase, remove spaces)
  - Detect similar part numbers (fuzzy matching)
  - Suggest merging duplicates
- ✅ Category auto-mapping
  - If category in file doesn't match system enum, suggest closest match
  - Bulk category assignment (select multiple parts, assign category)

**6. Template & Documentation**
- ✅ CSV template download
  - Pre-formatted headers
  - Sample rows with examples
  - Comments explaining each field
- ✅ Import documentation
  - Step-by-step guide (with screenshots)
  - Common errors & how to fix
  - Best practices for data prep

**Database Changes:**
- Table: `parts_upload_history` (track uploads)
- Table: `parts_upload_errors` (log validation failures per upload)
- Add fields to `parts_library`: `created_via_upload`, `last_updated_via_upload`, `upload_id`

**File Format Requirements:**
- **CSV:** UTF-8 encoded, comma-delimited
- **Excel:** .xlsx format (not .xls), max 10,000 rows
- **Required columns:** part_number, part_name, category, unit
- **Optional columns:** standard_cost, supplier_name, supplier_contact, description

**Deliverable:**
- Parts library can be populated with 1000+ parts via single CSV upload
- Validation prevents bad data from corrupting catalog
- Upload history allows rollback if needed
- Finance/Maintenance exec can manage catalog without dev involvement

**v0.9 Exit Criteria:**
- Successfully upload 100+ part test file with 0 errors
- Detect and prevent duplicate part_number import
- Rollback feature tested (upload → rollback → verify restore)
- Template download used by finance team

**Risks:**
- **Malformed file uploaded:** Validation layer catches before DB corruption
- **Duplicate part numbers:** Deduplication logic resolves or flags for manual review
- **Excel file too large:** Set hard limit of 10K rows, recommend splitting files
- **Accidental catalog wipe:** Require double confirmation + admin password for "Replace all"

---

### 🎯 v0.10: MECHANIC MOBILE INTERFACE (Week 16)

**Goal:** Enable mechanics/electricians to access assigned work and update job sheets from mobile devices

**CRITICAL:** This version was MISSING from the original PRD. Without it, the actual field workers (mechanics/electricians) who perform the maintenance work have NO way to interact with the system. This is a fundamental operational blocker.

**Critical Success Criteria:**
- [ ] Mechanics can view their assigned tickets on mobile
- [ ] Mechanics can update job sheet details (odometer, work performed, parts used)
- [ ] Mechanics can mark work as complete
- [ ] Job sheet matches physical form structure (see uploaded physical job sheet example)
- [ ] Mobile UX optimized for field work (large buttons, minimal typing)

#### Features

**1. Mechanic User Management (Maintenance Exec)**
- ✅ Add mechanics to system
  - Name, employee ID, contact, specialty (Mechanic/Electrician)
  - Assign to multiple sites (mechanics work across sites)
  - Set active/inactive status
- ✅ View mechanic list
  - Filter by specialty, site, active status
  - See assigned ticket count per mechanic
  - Workload balancing view

**2. Ticket Assignment to Mechanics (Maintenance Exec)**
- ✅ Assign ticket to specific mechanic
  - Select from dropdown of active mechanics
  - Priority flag (Urgent, Normal, Low)
  - Estimated labor hours
  - Required parts (pre-populate from parts library)
- ✅ Reassign tickets
  - Transfer to different mechanic if needed
  - Track assignment history (audit trail)
- ✅ Mechanic dashboard view
  - See all mechanics' assigned tickets
  - Workload distribution chart
  - Overloaded mechanic alerts

**3. Mechanic Mobile App (Mechanics/Electricians)**

**Home Screen:**
- ✅ My Assigned Tickets list
  - Sorted by priority, then SLA urgency
  - Card view: Vehicle number, complaint, site, priority
  - Color-coded: Red (urgent), Yellow (SLA soon), Green (normal)
  - Filter: By status (Assigned, In Progress, Completed)
  - Search by vehicle number

**Ticket Detail View:**
- ✅ View ticket information
  - Vehicle number, site, complaint, supervisor contact
  - Photos uploaded by supervisor
  - Impact, category, SLA deadline
  - Job sheet ID
- ✅ Start work button
  - Changes status to "Work in Progress"
  - Records start time automatically
  - Locks ticket to this mechanic (prevents conflicts)

**Job Sheet Update Interface:**
- ✅ Capture odometer reading
  - Numeric keyboard input
  - Validation (can't decrease from last reading)
  - Show last odometer reading for reference
- ✅ Work performed description
  - Large text area
  - Voice-to-text option (for easier mobile input)
  - Common phrases quick-select (e.g., "Oil change", "Brake replacement")
- ✅ Parts used
  - Select from parts library (autocomplete search)
  - Quantity per part
  - Add multiple parts
  - Show parts cost estimate (not editable by mechanic)
- ✅ Labor hours input
  - Time picker (hours + minutes)
  - Auto-calculate from start to end time
  - Override if needed
- ✅ Before/After photos
  - Camera integration
  - Compress before upload (smart compression from v2.1)
  - Label photos (Before work, After work, Issue closeup, etc.)
- ✅ Additional notes
  - Recommendations for future maintenance
  - Issues discovered during work
  - Parts that need ordering

**Complete Work:**
- ✅ Mark as complete button
  - Validates all required fields filled:
    - Odometer reading ✓
    - Work performed ✓
    - Parts used (if any) ✓
    - Labor hours ✓
  - Records completion time
  - Updates ticket status to "Completed"
  - Triggers supervisor notification for rating

**4. Job Sheet Structure (Matches Physical Form)**

Based on the uploaded physical job sheet, the digital version captures:

```javascript
job_sheet {
  // Header
  job_sheet_number: auto-generated (e.g., "115/13" format)
  ticket_id: references ticket
  vehicle_number: from ticket
  site: from ticket
  assigned_mechanic_id: references users
  
  // Timestamps
  date_assigned: auto (when assigned to mechanic)
  work_start_time: captured when mechanic taps "Start Work"
  work_end_time: captured when mechanic taps "Complete"
  
  // Vehicle details
  engine_number: text
  chassis_number: text
  vehicle_model: text
  km_reading: integer (odometer)
  
  // Work details
  work_performed: text (description of repairs)
  parts_used: array of {part_id, quantity, cost}
  labor_hours: decimal
  
  // Fuel/fluids (from physical form)
  fuel_at_arrival: integer
  fuel_pumped: integer
  fuel_difference: integer (calculated)
  
  // Photos
  before_photos: text[] (Google Drive URLs)
  after_photos: text[] (Google Drive URLs)
  
  // Sign-offs
  mechanic_signature: text (digital signature or typed name)
  supervisor_signature: text (post-completion)
  inspector_signature: text (if quality check required)
  
  // Completion
  completed_date: date
  remarks: text
  recommendations: text (future maintenance needed)
}
```

**5. Mechanic Dashboard (Mechanics)**
- ✅ Summary cards
  - Tickets assigned to me: 15
  - In progress: 3
  - Completed today: 5
  - Avg. completion time: 2.5 hours
- ✅ Performance metrics
  - Tickets completed this week/month
  - Avg. time per ticket
  - Parts usage summary
  - SLA adherence rate (tickets completed on time)

**Database Changes:**
- Update `users` table: Add `role: enum (supervisor, mechanic, maintenance_exec, finance)`
- Update `tickets` table: Add `assigned_mechanic_id: uuid REFERENCES users`
- Update `job_sheets` table: Add all fields from physical form (see above)
- New table: `mechanic_assignments` (assignment_id, ticket_id, mechanic_id, assigned_at, reassigned_from, reassignment_reason)

**Mobile UX Optimizations:**
- **Large touch targets** (min 48px for buttons)
- **Minimal typing** (dropdowns, autocomplete, voice-to-text)
- **Offline support** (queue updates when offline, sync when online) - FUTURE
- **Camera-first** (one-tap photo capture)
- **Auto-save drafts** (don't lose work if app crashes)

**Deliverable:**
- Mechanic mobile interface fully functional
- Mechanics can view, update, and complete assigned work
- Job sheets digitally match physical form structure
- Ticket assignment workflow: Supervisor → Maintenance Exec → Mechanic → Complete → Supervisor Rating

**v0.10 Exit Criteria:**
- 5+ mechanics test on their actual mobile devices (iOS + Android)
- Mechanics complete 20+ job sheets digitally
- 0 mechanics ask "where's the physical book?" (fully digital workflow adopted)
- Job sheet data quality: 95% of required fields filled correctly
- Mobile app works on low-end devices (tested on 3-year-old phones)

**Risks:**
- **Mechanics resist digital workflow:** Mitigate with hands-on training, show time savings
- **Mobile UX not intuitive:** User test with 3 mechanics BEFORE v0.10 launch, iterate
- **Offline work not supported (v1 issue):** Mechanics in basements/garages may have poor signal - document as known limitation for v0.10, add offline mode in v1.1
- **Digital signature legal validity:** Confirm with legal team if digital signatures acceptable for job sheets

**Why This Was Missing:**
The original PRD assumed the Maintenance Executive performs the actual repair work, which is incorrect. In reality:
- **Supervisor** reports issue
- **Maintenance Exec** coordinates and assigns
- **Mechanic/Electrician** performs actual work ← **This role was completely absent**
- **Supervisor** validates completion

Without this version, the system cannot be used operationally. This is a **show-stopper** if not implemented.

---

## Version Dependencies & Sequencing

```
v0.1 ──> v0.2 ──> v0.3 ──> v0.4 ──> v0.5 ──> v0.6 ──> v0.7 ──> v0.8 ──> v0.9 ──> v0.10
  ↓       ↓        ↓        ↓        ↓        ↓        ↓        ↓        ↓        ↓
Users    SLA    Dashboard  Job     Inventory Accounts Feedback Vehicle  Bulk    Mechanic
         ↓                 Sheets      ↓         ↓              Service  Parts   Mobile
       Access             Parts    Consumption Audit           History  Upload  Interface
       Control           Library
```

**Critical Path:**
- v0.1 → v0.2: Must have users and tickets before SLA tracking
- v0.2 → v0.3: Need SLA data before meaningful dashboards
- v0.3 → v0.4: Finance must be stable before job sheets (dependencies)
- v0.4 → v0.5: Parts library required for inventory
- v0.5 → v0.6: Inventory data required for reconciliation
- v0.6 → v0.7: Accounts settled before feedback enforcement
- v0.7 → v0.8: Service history requires completed job sheet workflow
- v0.8 → v0.9: Vehicle module established before bulk parts import optimization
- **v0.9 → v0.10: Parts library + job sheets must exist before mechanics can use them**

**Parallelizable Work (if 2+ devs):**
- v0.2 SLA engine can be built while v0.1 is in internal testing
- v0.3 Finance module can start before v0.2 ships (separate domain)
- v0.9 Bulk upload can be built anytime after v0.4 (parts library exists)
- **v0.10 Mechanic interface should ideally be built IN PARALLEL with v0.4** (both are about job sheets)

---

## Data Migration Strategy

### Overview

You have **12,000+ historical tickets** in Google Sheets that need to be imported into Supabase for:
1. **Staging environment** (testing with realistic data)
2. **Production environment** (preserve historical records)

This is NOT optional. Without historical data:
- UAT is meaningless (testing with fake data)
- Dashboards show empty charts (no trends)
- Users lose historical context (can't reference old tickets)

### Migration Timeline

- **Week 2:** Import data to staging (for development testing)
- **Week 14:** Validate data quality, fix import scripts
- **Week 15:** Import to production (parallel run starts)

### Source Data (Google Sheets)

**Files to Export:**
1. **Maintenance Register** (main ticket data)
   - ~12,000 rows
   - Columns: Ticket number, date, site, vehicle, category, complaint, impact, job sheet ID, status, SLA dates, etc.
2. **Finance Entries** (TC(S) sheet?)
   - ~20,000 rows
   - Columns: Date, job sheet ID, vendor, amount, invoice number, payment status, etc.
3. **Sites Master** (if exists)
   - 60 sites
4. **Vehicles Master** (if exists)
   - 1000+ vehicles

**Export Process:**
```
1. Open each sheet in Google Sheets
2. File → Download → CSV (.csv)
3. Save with clear names: maintenance_register.csv, finance_entries.csv, sites.csv, vehicles.csv
4. Keep original files as backup
```

### Migration Script Strategy

**Option 1: Python Script (Recommended)**

Use Python + Pandas + Supabase client for controlled import.

**Setup:**
```bash
pip install pandas supabase-py python-dotenv
```

**Script Structure:**
```python
import pandas as pd
from supabase import create_client, Client
from datetime import datetime
import os

# Supabase connection
url = os.environ.get("SUPABASE_URL")
key = os.environ.get("SUPABASE_ANON_KEY")
supabase: Client = create_client(url, key)

# Step 1: Import Sites
def import_sites():
    df = pd.read_csv('sites.csv')
    sites = []
    
    for _, row in df.iterrows():
        sites.append({
            'name': row['site_name'].strip(),
            'is_active': True
        })
    
    # Batch insert (500 at a time to avoid timeout)
    for i in range(0, len(sites), 500):
        batch = sites[i:i+500]
        supabase.table('sites').insert(batch).execute()
    
    print(f"Imported {len(sites)} sites")

# Step 2: Import Vehicles
def import_vehicles():
    df = pd.read_csv('vehicles.csv')
    vehicles = []
    
    for _, row in df.iterrows():
        vehicles.append({
            'number': row['vehicle_number'].strip(),
            'site': row['site'].strip(),
            'type': row['vehicle_type'],
            'is_active': True
        })
    
    for i in range(0, len(vehicles), 500):
        batch = vehicles[i:i+500]
        supabase.table('vehicles').insert(batch).execute()
    
    print(f"Imported {len(vehicles)} vehicles")

# Step 3: Import Tickets (MOST COMPLEX)
def import_tickets():
    df = pd.read_csv('maintenance_register.csv')
    
    # Data cleaning
    df['created_at'] = pd.to_datetime(df['date_created'], errors='coerce')
    df['assigned_date'] = pd.to_datetime(df['date_assigned'], errors='coerce')
    df['completed_date'] = pd.to_datetime(df['date_completed'], errors='coerce')
    
    # Handle nulls
    df = df.fillna({
        'complaint': '',
        'remarks': '',
        'job_sheet_id': '',
        'impact': 'Minor',  # default
        'status': 'Pending'
    })
    
    tickets = []
    
    for _, row in df.iterrows():
        # Calculate SLA end date (you'll need to implement SLA logic)
        sla_days = get_sla_days(row['impact'], row['category'])
        sla_end_date = row['created_at'] + pd.Timedelta(days=sla_days)
        
        tickets.append({
            'ticket_number': int(row['ticket_number']),
            'created_at': row['created_at'].isoformat(),
            'site': row['site'].strip(),
            'vehicle_number': row['vehicle_number'].strip(),
            'category': row['category'],
            'complaint': row['complaint'],
            'supervisor_name': row['supervisor_name'],
            'impact': row['impact'],
            'job_sheet_id': row['job_sheet_id'],
            'assigned_date': row['assigned_date'].isoformat() if pd.notna(row['assigned_date']) else None,
            'completed_date': row['completed_date'].isoformat() if pd.notna(row['completed_date']) else None,
            'status': row['status'],
            'sla_end_date': sla_end_date.isoformat(),
            # created_by_user_id: Set to migration user ID
            'created_by_user_id': MIGRATION_USER_ID
        })
    
    # Import in batches (100 at a time - tickets are larger objects)
    for i in range(0, len(tickets), 100):
        batch = tickets[i:i+100]
        try:
            supabase.table('tickets').insert(batch).execute()
            print(f"Imported batch {i//100 + 1}, {len(batch)} tickets")
        except Exception as e:
            print(f"Error in batch {i//100 + 1}: {e}")
            # Log failed rows for manual review
            with open('failed_tickets.csv', 'a') as f:
                for ticket in batch:
                    f.write(f"{ticket['ticket_number']},Error: {e}\n")
    
    print(f"Imported {len(tickets)} tickets")

# Helper function: SLA calculation
def get_sla_days(impact, category):
    SLA_MATRIX = {
        ('Major', 'Electrical'): 7,
        ('Major', 'Mechanical'): 15,
        ('Major', 'Body'): 30,
        ('Major', 'Tyre'): 15,
        ('Major', 'GPS/Camera'): 3,
        ('Minor', 'Electrical'): 3,
        ('Minor', 'Mechanical'): 3,
        ('Minor', 'Body'): 3,
        ('Minor', 'Tyre'): 3,
        ('Minor', 'GPS/Camera'): 3,
    }
    return SLA_MATRIX.get((impact, category), 3)

# Step 4: Import Finance Entries
def import_finance_entries():
    df = pd.read_csv('finance_entries.csv')
    
    # Similar pattern to tickets
    # Map to finance_entries table schema
    # Handle date conversions, nulls, etc.
    
    pass  # Implementation similar to tickets

# Run migration
if __name__ == "__main__":
    print("Starting migration...")
    import_sites()
    import_vehicles()
    import_tickets()
    import_finance_entries()
    print("Migration complete!")
```

**Option 2: Supabase CSV Import (Simpler, Less Control)**

Supabase dashboard has a CSV import feature:
1. Table Editor → Select table → Import data → Upload CSV
2. Map columns to table fields
3. Preview and import

**Pros:** No coding required
**Cons:** 
- Less control over data cleaning
- No error handling
- Can't batch large imports (may timeout)
- **Not recommended for 12K+ rows**

### Data Cleaning Checklist

Before importing, clean your CSV data:

**1. Dates**
- [ ] Convert to ISO format: `2024-12-29` (not `29/12/2024`)
- [ ] Handle empty dates (set to `null`, not blank)
- [ ] Check for invalid dates (`2024-13-45` = error)

**2. Text Fields**
- [ ] Remove leading/trailing spaces: `"  Site A  "` → `"Site A"`
- [ ] Standardize site names (must match exactly across files)
- [ ] Handle special characters (`'`, `"`, `,` in text can break CSV)

**3. Numbers**
- [ ] Remove currency symbols: `₹10,000` → `10000`
- [ ] Remove commas from numbers: `1,000` → `1000`
- [ ] Ensure ticket numbers are integers

**4. Enums (Status, Category, Impact)**
- [ ] Standardize values (e.g., `Pending` not `pending` or `PENDING`)
- [ ] Map old values to new:
  - Old: `"In Progress"`, New: `"Team Assigned"`
  - Old: `"Done"`, New: `"Completed"`

**5. Foreign Keys**
- [ ] Ensure sites exist before importing vehicles
- [ ] Ensure vehicles exist before importing tickets
- [ ] Create a migration user (for `created_by_user_id`)

### Migration User Creation

Create a special "system" user for historical data:

```sql
-- In Supabase SQL Editor
INSERT INTO users (id, email, name, role, is_active)
VALUES (
  '00000000-0000-0000-0000-000000000001',  -- Fixed UUID for migration
  'migration@nvs.internal',
  'Data Migration Script',
  'maintenance_exec',
  false  -- Inactive, can't login
);
```

Use this user ID for all `created_by_user_id` fields in historical data.

### Validation After Import

**MANDATORY checks after importing to staging:**

```sql
-- 1. Check ticket counts match
SELECT COUNT(*) FROM tickets;
-- Compare to Google Sheets row count

-- 2. Check for duplicate ticket numbers
SELECT ticket_number, COUNT(*) 
FROM tickets 
GROUP BY ticket_number 
HAVING COUNT(*) > 1;
-- Should return 0 rows

-- 3. Check for orphaned vehicles (vehicle not in vehicles table)
SELECT DISTINCT vehicle_number 
FROM tickets 
WHERE vehicle_number NOT IN (SELECT number FROM vehicles);
-- Should return 0 rows (or handle them)

-- 4. Check for orphaned sites
SELECT DISTINCT site 
FROM tickets 
WHERE site NOT IN (SELECT name FROM sites);
-- Should return 0 rows

-- 5. Check SLA dates are calculated
SELECT COUNT(*) 
FROM tickets 
WHERE sla_end_date IS NULL;
-- Should return 0 (or very few for rejected tickets)

-- 6. Check date ranges are reasonable
SELECT MIN(created_at), MAX(created_at) FROM tickets;
-- Should match your expected range (e.g., 2020-2024)

-- 7. Check finance entries linked to tickets
SELECT COUNT(*) 
FROM finance_entries 
WHERE ticket_id IS NULL AND job_sheet_id IS NOT NULL;
-- If high, need to link finance to tickets via job_sheet_id
```

### Handling Migration Errors

**Common Issues:**

**1. Duplicate Ticket Numbers**
- **Cause:** Multiple rows with same ticket_number in sheets
- **Fix:** Deduplicate in CSV before import (keep latest entry)

**2. Invalid Dates**
- **Cause:** Malformed dates (`32/13/2024`)
- **Fix:** Set to `null` or use date validation in script

**3. Missing Sites/Vehicles**
- **Cause:** Ticket references site/vehicle not in master table
- **Fix:** Create missing entries or flag for manual review

**4. Large File Timeouts**
- **Cause:** Importing 12K rows at once
- **Fix:** Batch import (100-500 rows at a time)

**5. Foreign Key Violations**
- **Cause:** Trying to insert ticket before site/vehicle exists
- **Fix:** Import order: Sites → Vehicles → Users → Tickets → Finance

### Testing Migration in Staging

**Week 2: First Import Attempt**
1. Export CSVs from Google Sheets
2. Clean data (dates, text, numbers)
3. Run migration script
4. Validate counts, relationships
5. **Fix errors, re-run until clean**

**Week 14: Final Validation**
1. Re-export latest data from Sheets
2. Import to fresh staging DB
3. Run all validation queries
4. Load test with 12K tickets
5. UAT team verifies data accuracy

### Production Import (Week 15)

**CRITICAL: Only import to production AFTER:**
- [ ] Staging import successful (0 errors)
- [ ] Validation queries pass
- [ ] UAT team confirms data looks correct
- [ ] Backup production DB (in case you need to rollback)

**Production Import Steps:**
1. Take snapshot of empty production DB (Supabase Dashboard → Backups)
2. Run migration script against production
3. Validate immediately (counts, relationships)
4. Test login, create test ticket, check dashboard
5. If ANY issues, rollback and debug in staging

### Incremental Updates During Parallel Run

**Problem:** You import historical data Week 15, but team creates 50 new tickets in Sheets during Week 15-16 (parallel run).

**Solution:** 
- **Option 1:** Manual entry (maintenance exec adds 50 tickets to app)
- **Option 2:** Second migration at cutover (import only NEW tickets created during parallel run)

**Recommended:** Option 1 for 2-week parallel run (manageable volume)

### Migration Rollback Plan

If import fails catastrophically:

```sql
-- Delete all imported data (DANGER: Only in staging!)
TRUNCATE tickets, finance_entries, vehicles, sites, users CASCADE;

-- Or drop and recreate tables (resets auto-increment)
-- Then re-run migration script
```

**Production Rollback:**
- Use Supabase Point-in-Time Recovery (requires Pro plan)
- Or restore from backup snapshot

---

**YOU HAVE CHOSEN A BIG BANG LAUNCH:** Launch to users only after entire product (v0.1 - v0.9) is complete.

This is a **HIGH-RISK strategy** compared to incremental rollout. Here's what you MUST do to mitigate:

### Mandatory Risk Mitigation

**1. Build Staging Environment (Week 2)**
- Separate Supabase project for staging
- Populate with realistic fake data:
  - 1000+ fake tickets across 60 sites
  - 50+ fake users (supervisors, exec, finance)
  - 200+ fake finance entries
  - 100+ fake job sheets with parts
  - 500+ fake inventory transactions
- Mirror production data structure exactly

**2. User Acceptance Testing (UAT) - Weeks 10-14**
- **Supervisors (3 people minimum):**
  - Test ticket submission on their actual devices
  - Validate mobile UX on iOS + Android
  - Submit 20+ test tickets each
  - Rate completed work
- **Maintenance Executive:**
  - Test full workflow from ticket creation to completion
  - Validate SLA calculations against manual calculations
  - Test job sheet creation, merging, rejection
  - Use dashboard to generate reports
- **Finance Team (2 people):**
  - Log expenses, link to tickets
  - Test inventory inward/consumption
  - Reconcile test invoices
  - Download reports

**3. Parallel Run (Mandatory 2 Weeks Minimum)**
- Keep Google Sheets ACTIVE during parallel run
- Enter ALL data in BOTH systems (double entry)
- Compare outputs daily:
  - Ticket counts match
  - SLA calculations match
  - Finance totals match
  - Reports match
- Fix discrepancies before cutover
- **Only switch when 100% confident**

**4. Rollback Plan (Document Before Launch)**
- Daily automated backups to CSV (all tables)
- Keep Google Sheets active as backup for 1 month post-launch
- Document cutover steps with reverse procedure
- Assign rollback decision authority (who can call it)
- Practice rollback in staging (test restore)

**5. Launch Day War Room**
- All developers available (not traveling)
- Maintenance exec + 2 supervisors on call
- Monitor error logs in real-time (first 48 hours)
- Hotfix process documented (how fast can you patch)
- Support channel open (Slack/WhatsApp for urgent issues)

**6. Training Before Launch (Week 14-15)**
- **Supervisors:** 30-min mobile app training video + Q&A
- **Maintenance Exec:** 2-hour hands-on session on all features
- **Finance Team:** 1-hour training on finance module + inventory
- Create quick reference guides (laminated cards)
- Record training sessions for future onboarding

### Why This is Risky (Accept These Risks)

**No Early Feedback Loops:**
- You're building for 15 weeks without real user validation
- If you misunderstand a workflow, you discover it at launch (not week 2)
- Changes are expensive (refactor across 9 versions, not 1)

**All-or-Nothing Adoption:**
- Can't partially roll back if one module fails
- If finance module breaks, supervisors still need it for linked data
- **Entire system must work, or you revert to Sheets**

**Testing Burden:**
- Must test integration of ALL 9 versions together
- Bug in v0.8 could break v0.3 dashboard (cascading failures)
- QA effort is 5x higher than incremental (no production validation per version)

**Cultural Resistance:**
- Users switch from familiar Sheets to completely new system overnight
- No gradual learning curve
- **Resistance will be higher than incremental adoption**

### What You Gain (Why You're Doing This)

**Complete Feature Set on Day 1:**
- Users get full value immediately (not incremental)
- No "coming soon" features causing frustration
- Competitive advantage if speed matters

**No Mid-Flight Changes:**
- Workflows locked once designed (easier to train)
- No user confusion from evolving UI
- One big training session, not continuous change management

**Single Data Migration:**
- Import historical data once (not multiple times)
- Cleaner cutover (old system → new system, done)

---

---

## Technical Scalability & Performance

**Target Load:** 1000 tickets/month (~33 tickets/day, ~250 working hours/month = ~4 tickets/hour during business hours)

### Database Performance

**Potential Bottlenecks:**

1. **Ticket List Queries (Most Frequent)**
   - Supervisors filtering their site's tickets
   - Maintenance exec viewing all tickets with complex filters
   - **Risk:** Full table scan on 12,000+ tickets with multiple JOINs

**Solutions:**
```sql
-- Critical indexes
CREATE INDEX idx_tickets_site ON tickets(site);
CREATE INDEX idx_tickets_status ON tickets(status);
CREATE INDEX idx_tickets_created_at ON tickets(created_at DESC);
CREATE INDEX idx_tickets_sla_status ON tickets(completion_sla_status);
CREATE INDEX idx_tickets_site_status ON tickets(site, status); -- Composite for supervisor queries

-- For maintenance exec global view
CREATE INDEX idx_tickets_created_status ON tickets(created_at DESC, status);

-- For SLA dashboard queries
CREATE INDEX idx_tickets_sla_end_date ON tickets(sla_end_date);
CREATE INDEX idx_tickets_assigned_date ON tickets(assigned_date);
```

2. **Dashboard Aggregation Queries**
   - Counting tickets by site, status, category (GROUP BY queries)
   - SLA adherence rate calculations (nested queries)
   - **Risk:** 5+ second load times on dashboards

**Solutions:**
- **Materialized Views** for pre-computed aggregates (refresh nightly):
```sql
-- Daily stats materialized view
CREATE MATERIALIZED VIEW daily_ticket_stats AS
SELECT 
  DATE(created_at) as date,
  site,
  status,
  category,
  COUNT(*) as ticket_count,
  SUM(CASE WHEN completion_sla_status = 'Adhered' THEN 1 ELSE 0 END) as sla_adhered_count
FROM tickets
GROUP BY DATE(created_at), site, status, category;

-- Refresh nightly via cron job
REFRESH MATERIALIZED VIEW daily_ticket_stats;
```

- **Query result caching** (frontend):
  - Cache dashboard data for 5 minutes (React Query)
  - Only refresh on user action (button click)
  - Background refetch every 5 min for stale data

3. **Finance Entry Lookups**
   - Linking finance entries to tickets via job_sheet_id
   - **Risk:** Slow lookups if job_sheet_id not indexed

**Solutions:**
```sql
CREATE INDEX idx_finance_job_sheet ON finance_entries(job_sheet_id);
CREATE INDEX idx_finance_ticket_id ON finance_entries(ticket_id);
CREATE INDEX idx_finance_created_at ON finance_entries(created_at DESC);
```

4. **Real-time SLA Calculations**
   - Computing `days_remaining` for every ticket on list view
   - **Risk:** CPU-heavy if done per-request

**Solutions:**
- **Database function** (runs on DB server, not app):
```sql
CREATE FUNCTION calculate_sla_days_remaining(sla_end_date DATE)
RETURNS INTEGER AS $$
BEGIN
  RETURN sla_end_date - CURRENT_DATE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Use in queries
SELECT *, calculate_sla_days_remaining(sla_end_date) as days_remaining FROM tickets;
```

- **Scheduled job** to update computed fields nightly (avoid real-time calc):
```sql
-- Nightly update of SLA status (cron job)
UPDATE tickets 
SET 
  completion_sla_status = CASE 
    WHEN completed_date IS NOT NULL AND completed_date <= sla_end_date THEN 'Adhered'
    WHEN completed_date IS NOT NULL AND completed_date > sla_end_date THEN 'Violated'
    WHEN CURRENT_DATE > sla_end_date THEN 'Violated'
    ELSE 'Pending'
  END,
  days_remaining = sla_end_date - CURRENT_DATE
WHERE completed_date IS NULL OR updated_at > (CURRENT_DATE - INTERVAL '1 day');
```

### File Storage (Google Drive)

**Photo Upload Volume:**
- Assume 30% of tickets have photos (~300 photos/month)
- Photos come from two sources:
  1. **WhatsApp forwarded images** (already compressed, ~200-500KB)
  2. **Raw phone camera images** (2-8MB, high resolution)
- **Challenge:** Compress raw images without re-compressing WhatsApp images (quality loss)

**Smart Photo Compression Strategy:**

**1. Client-Side Intelligent Compression**

```javascript
async function smartPhotoCompress(file) {
  // Step 1: Check if already compressed
  const isAlreadyCompressed = (file.size < 1024 * 1024); // < 1MB = likely compressed
  
  if (isAlreadyCompressed) {
    // WhatsApp image or already optimized
    console.log('Image already compressed, skipping');
    return file;  // Upload as-is
  }
  
  // Step 2: Raw camera image, needs compression
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d');
  const img = await loadImage(file);
  
  // Resize to max 1920x1080 (Full HD is sufficient for invoice/vehicle photos)
  const maxWidth = 1920;
  const maxHeight = 1080;
  let width = img.width;
  let height = img.height;
  
  if (width > maxWidth || height > maxHeight) {
    const ratio = Math.min(maxWidth / width, maxHeight / height);
    width = width * ratio;
    height = height * ratio;
  }
  
  canvas.width = width;
  canvas.height = height;
  ctx.drawImage(img, 0, 0, width, height);
  
  // Compress to JPEG with 80% quality (good balance)
  const compressedBlob = await new Promise(resolve => {
    canvas.toBlob(resolve, 'image/jpeg', 0.80);
  });
  
  // Verify compression saved space
  const originalSizeMB = file.size / (1024 * 1024);
  const compressedSizeMB = compressedBlob.size / (1024 * 1024);
  const savings = ((1 - compressedSizeMB / originalSizeMB) * 100).toFixed(1);
  
  console.log(`Compressed ${originalSizeMB.toFixed(2)}MB → ${compressedSizeMB.toFixed(2)}MB (${savings}% savings)`);
  
  return new File([compressedBlob], file.name, {
    type: 'image/jpeg',
    lastModified: Date.now()
  });
}
```

**2. Photo Quality Preservation**

- **Keep EXIF data** (metadata: date taken, GPS location if enabled)
  - Useful for verifying when/where photo was taken
  - Use `exif-js` library to extract and preserve
- **Avoid double compression**
  - Check file size + MIME type
  - If already JPEG <1MB, skip compression
- **Visual quality targets:**
  - Invoice text must be readable (OCR-able)
  - Vehicle damage clearly visible
  - License plate numbers legible

**3. Progressive Upload (UX Optimization)**

```javascript
// Don't block ticket submission on photo upload
async function submitTicket(formData, photos) {
  // Step 1: Submit ticket immediately (get ticket ID)
  const ticket = await createTicket(formData);
  
  // Step 2: Show success message to user
  showSuccessMessage("Ticket created! Uploading photos...");
  
  // Step 3: Upload photos in background
  for (const photo of photos) {
    try {
      const compressed = await smartPhotoCompress(photo);
      const driveUrl = await uploadToGoogleDrive(compressed, ticket.id);
      
      // Step 4: Link photo to ticket
      await addPhotoToTicket(ticket.id, driveUrl);
      
      updateProgress(photos.indexOf(photo) + 1, photos.length);
    } catch (error) {
      // Queue for retry
      queueFailedUpload(ticket.id, photo);
    }
  }
  
  showCompletionMessage("Ticket and photos uploaded successfully!");
}
```

**Benefits:**
- User doesn't wait for photo uploads (can submit next ticket)
- Failed uploads don't block ticket creation
- Retry mechanism for flaky networks

**4. Google Drive API Quota Management**

**Current Limits:**
- 1,000 queries per 100 seconds per user
- ~10 queries/second sustained = safe
- At 300 photos/month = ~10 photos/day = ~1 photo/hour = **safe**

**Batch Upload Scenario (Risk):**
- Supervisor uploads 20 tickets with photos in 10 minutes
- 20 tickets × 2 photos avg = 40 photos
- 40 photos / 10 min = 4 photos/min = **safe**

**Quota Exceeded Handling:**
```javascript
async function uploadWithRetry(file, ticketId, maxRetries = 3) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await uploadToGoogleDrive(file, ticketId);
    } catch (error) {
      if (error.code === 429) { // Quota exceeded
        const backoffMs = Math.pow(2, attempt) * 1000; // Exponential backoff
        console.log(`Quota exceeded, retrying in ${backoffMs}ms...`);
        await sleep(backoffMs);
      } else {
        throw error; // Other error, fail immediately
      }
    }
  }
  throw new Error('Upload failed after max retries');
}
```

**5. Photo Storage Optimization**

- **Compress BEFORE upload** (not after)
  - Saves bandwidth (faster uploads on mobile)
  - Reduces Drive storage usage
- **Delete old photos (optional):**
  - Photos >2 years old auto-deleted (after tickets closed)
  - Or keep forever if storage permits (15GB = ~75,000 photos at 200KB each)

**Storage Projections:**

| Scenario | Photos/Month | Size/Photo | Monthly | Annual | 3 Years |
|----------|--------------|------------|---------|--------|---------|
| **Without compression** | 300 | 2MB | 600MB | 7.2GB | 21.6GB ❌ (exceeds 15GB limit) |
| **With smart compression** | 300 | 200KB | 60MB | 720MB | 2.16GB ✅ |

**Savings:** 10x storage reduction, fits comfortably within free tier.

**Risks:**
- Drive API quota exceeded → Solution: Exponential backoff + retry
- Photos fill up Drive storage → Solution: Compress + optional cleanup policy
- Upload failures on poor network → Solution: Queue + background retry


### Supabase Free Tier Limits

**Current Limits (as of Dec 2024):**
- **Database:** 500MB storage
- **File storage:** 1GB (not using, Google Drive instead)
- **Bandwidth:** 2GB/month
- **API requests:** Unlimited (but rate-limited)

**Projected Usage:**
- **Database size after 1 year:**
  - 12,000 tickets × 1KB/ticket = 12MB
  - 24,000 finance entries × 1KB = 24MB
  - 1,000 job sheets × 2KB = 2MB
  - 5,000 inventory transactions × 500B = 2.5MB
  - **Total: ~50MB** (10% of limit) ✅

- **Bandwidth:**
  - Dashboard loads: 100KB/load × 500 loads/month = 50MB
  - API calls: Negligible (<1MB)
  - **Total: <100MB/month** (5% of limit) ✅

**When to Upgrade to Pro ($25/mo):**
- Database exceeds 400MB (80% of limit)
- Need >1M row reads/month (advanced analytics)
- Want automatic backups + point-in-time recovery
- **Estimated timeline:** 18-24 months at current growth

### Concurrent User Load

**Peak Concurrent Users:**
- 60 supervisors × 10% active simultaneously = 6 concurrent
- 1 maintenance exec
- 1 finance user
- **Total: ~8-10 concurrent users** (very low)

**Supabase Handles:**
- Free tier: 500 concurrent connections
- **You're using 2%** ✅

**Frontend Optimizations:**
- **React Query** for data fetching (automatic caching + deduplication)
- **Debounce search inputs** (wait 300ms before query)
- **Virtualized lists** for long ticket lists (render only visible rows)
- **Code splitting** (lazy load dashboard components)

### Real-time Features (Supabase Realtime)

**Use Cases:**
- Dashboard auto-updates when new ticket created
- Notification when ticket assigned to supervisor
- Live SLA violation alerts

**Risks:**
- WebSocket connections count toward concurrent limit
- Battery drain on mobile (constant connection)

**Solutions:**
- **Polling instead of WebSockets** for mobile:
  - Refresh dashboard every 30 seconds (not real-time)
  - Only fetch changes since last poll (incremental)
  - Battery-friendly
- **WebSockets only for desktop** (maintenance exec dashboard)
- **Limit subscriptions** to critical tables only (tickets, not finance)

### Search Performance

**Problem:** Searching 12,000 tickets by vehicle number or complaint text

**Solutions:**
- **Full-text search index** (PostgreSQL built-in):
```sql
-- Add tsvector column for full-text search
ALTER TABLE tickets ADD COLUMN search_vector tsvector;

-- Populate search vector (combines vehicle_number + complaint)
UPDATE tickets SET search_vector = 
  to_tsvector('english', COALESCE(vehicle_number, '') || ' ' || COALESCE(complaint, ''));

-- Create GIN index for fast full-text search
CREATE INDEX idx_tickets_search ON tickets USING GIN(search_vector);

-- Search query (sub-second even with 100K rows)
SELECT * FROM tickets 
WHERE search_vector @@ to_tsquery('english', 'brake');
```

- **Frontend debouncing** (wait 300ms after user stops typing)
- **Limit results** to 100 max (pagination for more)

### Export to Excel Performance

**Problem:** Exporting 12,000 tickets to Excel freezes browser

**Solutions:**
- **Server-side export** (generate Excel on backend):
  - Use `exceljs` library (Node.js)
  - Stream data to avoid memory overflow
  - Return download URL (don't send file in API response)
- **Chunked export** (if client-side):
  - Fetch 1000 rows at a time
  - Append to Excel file progressively
  - Show progress bar
- **Limit default export** to current filters/date range (not entire DB)

### Failure Scenarios & Recovery

**1. Google Drive API Down**
- **Symptoms:** Photo uploads fail
- **Recovery:** 
  - Queue uploads to retry later
  - Allow ticket submission without photos (optional field)
  - Alert admin after 10 failed uploads

**2. Supabase Database Slow**
- **Symptoms:** Dashboard takes >10s to load
- **Recovery:**
  - Frontend timeout after 5s (show cached data)
  - Alert admin if queries consistently slow
  - Fallback to materialized views (stale but fast)

**3. High Concurrent Load (Unexpected)**
- **Symptoms:** 50+ supervisors online simultaneously (rare)
- **Recovery:**
  - Supabase auto-scales connections
  - Frontend queues requests (max 5 concurrent per user)
  - Show "high traffic, please wait" message

**4. Data Corruption (Bug in Code)**
- **Symptoms:** Wrong SLA calculations, missing tickets
- **Recovery:**
  - Daily automated backups (Supabase built-in)
  - Point-in-time recovery (Pro plan only)
  - Manual CSV exports as fallback (keep for 7 days)

### Load Testing (Before Launch)

**MANDATORY: Run these tests in staging before production launch**

**1. Ticket Creation Load Test**
```bash
# Simulate 100 supervisors submitting tickets simultaneously
artillery quick --count 100 --num 10 POST https://api.yourdomain.com/tickets
```
- **Pass criteria:** <3s response time for 95% of requests

**2. Dashboard Query Load Test**
```bash
# Simulate 20 users loading dashboard at once
artillery quick --count 20 --num 5 GET https://api.yourdomain.com/dashboard
```
- **Pass criteria:** <5s load time with 12K tickets

**3. Photo Upload Stress Test**
- Upload 50 photos in 1 minute (batch upload scenario)
- **Pass criteria:** All uploads succeed, or queue for retry

**4. Database Size Test**
- Import 50,000 fake tickets (4 years of data)
- Run queries, measure response time
- **Pass criteria:** Queries still <3s with 50K rows

### Monitoring & Alerts (Production)

**Set up these alerts BEFORE launch:**

**1. Database Performance**
- Alert if query time >5s (Supabase dashboard)
- Alert if database size >400MB (80% of free tier)
- Weekly email with slow query report

**2. API Errors**
- Alert if 5xx errors >10/hour (something broke)
- Alert if 4xx errors >100/hour (bad requests spike)
- Log all errors to Sentry or similar

**3. User Activity**
- Alert if 0 tickets submitted for 24 hours (system dead?)
- Alert if concurrent users >50 (unexpected load)

**4. Storage**
- Alert if Google Drive API quota exceeded
- Alert if photo uploads fail >10 times/day

**5. Automated Daily Backups**
- Daily CSV export of all critical tables (tickets, finance, users, vehicles)
- Email backup files to admin (backup@nvs.com)
- Retention: Keep daily backups for 7 days, weekly for 30 days
- **CRITICAL:** This is your safety net if database corrupts

**Implementation (Scheduled Job):**

```javascript
// Supabase Edge Function (runs daily at 3 AM)
import { createClient } from '@supabase/supabase-js';
import { stringify } from 'csv-stringify/sync';
import nodemailer from 'nodemailer';

export async function dailyBackup() {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  
  // Fetch all tables
  const tables = ['tickets', 'finance_entries', 'users', 'sites', 'vehicles', 'job_sheets'];
  const csvFiles = {};
  
  for (const table of tables) {
    const { data, error } = await supabase.from(table).select('*');
    
    if (error) {
      console.error(`Error fetching ${table}:`, error);
      continue;
    }
    
    // Convert to CSV
    const csv = stringify(data, { header: true });
    csvFiles[table] = csv;
  }
  
  // Create email with attachments
  const transporter = nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 587,
    auth: { user: BACKUP_EMAIL, pass: BACKUP_EMAIL_PASSWORD }
  });
  
  const attachments = Object.entries(csvFiles).map(([name, csv]) => ({
    filename: `${name}_${new Date().toISOString().split('T')[0]}.csv`,
    content: csv
  }));
  
  await transporter.sendMail({
    from: 'backups@nvs.com',
    to: 'admin@nvs.com',  // Change to your admin email
    subject: `NVS Daily Backup - ${new Date().toISOString().split('T')[0]}`,
    text: `
      Daily database backup attached.
      
      Tables included:
      ${tables.map(t => `- ${t}: ${csvFiles[t].split('\n').length - 1} rows`).join('\n')}
      
      If you need to restore, import these CSVs into Supabase.
    `,
    attachments
  });
  
  console.log('Backup email sent successfully');
}

// Schedule via Supabase cron (pg_cron extension)
// Or use Vercel Cron Jobs: https://vercel.com/docs/cron-jobs
```

**Setup Instructions:**

1. **Enable Supabase cron (pg_cron extension):**
   ```sql
   -- In Supabase SQL Editor
   CREATE EXTENSION IF NOT EXISTS pg_cron;
   
   -- Schedule daily backup at 3 AM
   SELECT cron.schedule(
     'daily-backup',
     '0 3 * * *',  -- Cron expression: 3 AM daily
     $$
     -- Call your backup function here
     $$
   );
   ```

2. **Or use Vercel Cron Job:**
   - Create API route: `/api/backup`
   - Configure in `vercel.json`:
     ```json
     {
       "crons": [
         {
           "path": "/api/backup",
           "schedule": "0 3 * * *"
         }
       ]
     }
     ```

3. **Email Setup:**
   - Use Gmail App Password (not regular password)
   - Or use SendGrid/Resend for better reliability
   - Store credentials in environment variables

**Why This Matters:**
- Supabase free tier doesn't have point-in-time recovery
- If database corrupts (bug in code, accidental DELETE), you can restore from CSV
- Email delivery means backups stored off-platform (not just in Supabase)
- Daily frequency = max 24 hours of data loss

**Testing:**
- Run backup manually once (test email delivery)
- Verify CSV files contain correct data
- Test restore process (import CSV to staging DB)

### Performance Budget (Targets)

| Metric | Target | Measured How |
|--------|--------|--------------|
| Ticket list load time | <2s | Chrome DevTools Network tab |
| Dashboard load time | <3s | Lighthouse Performance score >90 |
| Ticket submission (with photo) | <5s | End-to-end test |
| Search results | <1s | Frontend timer |
| Export to Excel (1000 rows) | <10s | Backend processing time |
| Database query time (p95) | <500ms | Supabase metrics |
| Photo upload (2MB) | <10s | Drive API response time |

**Measure these weekly** in staging, fix if targets missed.

---

| Version | User Adoption | Time Savings | Data Quality | Business Value |
|---------|---------------|--------------|--------------|----------------|
| v0.1 | 80% supervisors active | 50% faster ticket submission | 0% data loss | Replace Google Form |
| v0.2 | 100% maintenance exec using SLA | Auto-calculation saves 2hr/day | 100% SLA accuracy | Prevent violations |
| v0.3 | Finance team onboarded | Boss gets reports instantly | 95% expense-ticket linkage | Real-time visibility |
| v0.4 | Physical book retired | 30% faster job sheet creation | 80% ticket relationships correct | Digitization complete |
| v0.5 | Inventory tracked digitally | 40% reduction in stock checks | 95% consumption accuracy | Prevent stockouts |
| v0.6 | All invoices in system | 50% faster reconciliation | 100% audit trail | Financial control |
| v0.7 | Feedback culture established | Quality issues detected faster | 80% feedback completion | Continuous improvement |
| v0.8 | Vehicle data synced | Service history automated | 100% odometer validation | Proactive maintenance |
| v0.9 | Parts catalog complete | Bulk upload saves 10+ hours | 99% parts library accuracy | Eliminate manual entry |
| v0.10 | Mechanics using mobile app | 60% faster job sheet completion | 95% job sheet data accuracy | Field workers empowered |

---

## Risk Management by Version

### v0.1 Risks
- **User resistance:** Mitigate with parallel run (Sheets + App for 1 week)
- **Mobile UX issues:** Test on 5+ device types before launch
- **Supabase limits:** Monitor usage, plan upgrade trigger

### v0.2 Risks
- **SLA calculation errors:** Validate against 100 historical tickets
- **Permission bypass:** Security audit before ship
- **Performance degradation:** Load test with 12K tickets

### v0.3 Risks
- **Dashboard performance:** Optimize queries, add caching
- **Finance data migration:** Validate every import
- **Excel export broken:** Test with large datasets

### v0.4 Risks
- **Job sheet workflow misaligned:** User testing with maintenance exec mandatory
- **Parts library incomplete:** Pre-populate from purchase history
- **Merge logic errors:** Extensive QA on edge cases

### v0.5 Risks
- **Inventory sync issues:** Implement transaction locking
- **Consumption tracking gaps:** Audit trail for every transaction
- **Low stock alerts missed:** Test notification system thoroughly

### v0.6 Risks
- **Payment data corruption:** Backups before any bulk operations
- **Audit reconciliation errors:** Manual verification for first 3 audits
- **Finance team training:** Hands-on sessions required

### v0.7 Risks
- **Feedback fatigue:** Keep feedback simple (3 taps max)
- **SLA enforcement backfires:** Pilot with 2 sites first
- **Low adoption:** Incentivize with recognition program

### v0.8 Risks
- **RooRides API downtime:** Implement caching + manual vehicle entry fallback
- **API authentication failures:** Store backup credentials, test auth renewal
- **Odometer data quality:** Require maintenance exec review on suspicious readings
- **Service history gaps:** Backfill historical data from old records (manual effort)

### v0.9 Risks
- **Malformed CSV/Excel files:** Robust validation layer with detailed error messages
- **Accidental catalog wipe:** Require admin password + double confirmation for destructive operations
- **Duplicate part numbers:** Implement fuzzy matching + manual review for conflicts
- **Large file uploads:** Set hard limits (10K rows max), recommend chunking

### v0.10 Risks
- **Mechanics resist digital workflow:** Hands-on training mandatory, show time savings over physical forms
- **Poor mobile UX:** User test with 3 mechanics BEFORE v0.10 launch, iterate based on feedback
- **Offline work limitation:** Mechanics in basements/garages have poor signal - document as known limitation
- **Low-end device performance:** Test on 3-year-old phones to ensure app works on older hardware
- **Digital signature legal validity:** Confirm with legal team if digital signatures acceptable for job sheets

---

## Next Steps After Each Version

### Post-v0.1
- Collect user feedback (survey + interviews)
- Monitor error logs for 1 week
- Fix critical bugs before v0.2 start
- Measure adoption metrics daily

### Post-v0.2
- Validate SLA calculations with maintenance exec
- Run security penetration test
- Optimize database queries
- Plan v0.3 dashboard mockups

### Post-v0.3
- Finance team training session
- Build Excel export templates
- Boss reviews dashboard (get feedback)
- Plan v0.4 job sheet workflow study

### Post-v0.4
- Retire physical job sheet book (ceremony!)
- Validate parts library completeness
- Maintenance exec QA session
- Prepare for inventory integration

### Post-v0.5
- First inventory audit with new system
- Analyze consumption patterns
- Optimize stock levels
- Train finance team on reconciliation

### Post-v0.6
- Full financial audit (internal)
- Compare old vs new process (time savings)
- Document SOPs for accounts module
- Prepare for feedback rollout

### Post-v0.7
- Collect initial feedback data
- Analyze CSAT trends
- Identify low-performing areas
- Prepare for vehicle module integration

### Post-v0.8
- Validate RooRides sync accuracy (manual spot-check)
- Review service history for 20+ vehicles
- Test odometer validation with edge cases
- Document vehicle maintenance SOPs

### Post-v0.9
- Pre-populate parts library with historical data (CSV import)
- Validate parts catalog completeness with finance team
- Test bulk upload with real supplier catalogs
- Document import procedures for future updates

### Post-v0.10
- Train all mechanics on mobile app (hands-on sessions)
- Create quick reference cards (laminated, keep in tool boxes)
- Monitor adoption rate (% of job sheets completed digitally vs physical)
- Collect mechanic feedback (what's working, what's frustrating)
- Retire physical job sheet books (ceremony!) - only use digital from now on

---

## IMPORTANT: What Didn't Make the Cut (v0.1-v0.10)

These features are OUT OF SCOPE for initial launch. Park them in the backlog:

- ❌ Multi-tenant support (other companies using the app)
- ❌ Mobile app (native iOS/Android) - PWA is sufficient
- ❌ Offline mode - requires significant complexity
- ❌ Push notifications - email/SMS is enough
- ❌ Advanced analytics (ML/AI predictions)
- ❌ Integration with ERP systems
- ❌ Vendor portal (for outsourced work tracking)
- ❌ Vehicle maintenance scheduling (beyond tickets)
- ❌ Automated PO generation
- ❌ Multi-currency support

**Why cut these?**  
Focus wins. Ship the core, prove value, then expand. Every feature you add delays launch and increases complexity. Start simple, scale smart.

---

## Database Schema (Supabase SQL)

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Sites table
CREATE TABLE sites (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT UNIQUE NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Vehicles table
CREATE TABLE vehicles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  number TEXT UNIQUE NOT NULL,
  site TEXT REFERENCES sites(name) ON UPDATE CASCADE,
  type TEXT,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Users table (extends Supabase auth.users)
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  employee_id TEXT,
  contact TEXT,
  role TEXT CHECK (role IN ('supervisor', 'maintenance_exec', 'finance')) NOT NULL,
  site TEXT REFERENCES sites(name) ON UPDATE CASCADE, -- NULL for exec/finance
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Tickets table
CREATE TABLE tickets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ticket_number INTEGER GENERATED ALWAYS AS IDENTITY,
  created_at TIMESTAMP DEFAULT NOW(),
  
  -- Form data
  site TEXT NOT NULL REFERENCES sites(name) ON UPDATE CASCADE,
  vehicle_number TEXT NOT NULL,
  category TEXT CHECK (category IN ('Mechanical', 'Electrical', 'Body', 'Tyre', 'GPS/Camera', 'Other')) NOT NULL,
  complaint TEXT NOT NULL,
  supervisor_name TEXT NOT NULL,
  supervisor_id TEXT NOT NULL,
  supervisor_contact TEXT,
  photos TEXT[], -- Google Drive URLs
  remarks TEXT,
  
  -- Assignment
  impact TEXT CHECK (impact IN ('Minor', 'Major')),
  job_sheet_id TEXT,
  assigned_date DATE,
  activity_plan_date DATE,
  work_type TEXT CHECK (work_type IN ('In House', 'Outsource')),
  status TEXT CHECK (status IN ('Pending', 'Team Assigned', 'Completed', 'Rejected')) DEFAULT 'Pending',
  
  -- Completion
  completed_date DATE,
  completion_remarks TEXT,
  
  -- SLA (computed)
  sla_days INTEGER, -- Based on impact + category
  sla_end_date DATE,
  assignment_sla_status TEXT CHECK (assignment_sla_status IN ('Adhered', 'Violated', 'Pending')),
  completion_sla_status TEXT CHECK (completion_sla_status IN ('Adhered', 'Violated', 'Pending')),
  tat_days INTEGER,
  
  -- CSAT
  rating TEXT CHECK (rating IN ('Good', 'Ok', 'Bad')),
  csat_score INTEGER CHECK (csat_score IN (0, 1, 2)),
  
  -- Metadata
  is_duplicate BOOLEAN DEFAULT false,
  merged_into_ticket_id UUID REFERENCES tickets(id),
  created_by_user_id UUID REFERENCES users(id) NOT NULL
);

-- Finance entries table
CREATE TABLE finance_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMP DEFAULT NOW(),
  
  work_type TEXT CHECK (work_type IN ('Spare Purchases', 'Outsourced Work', 'Job Card')) NOT NULL,
  activity_date DATE NOT NULL,
  vehicle_number TEXT,
  job_sheet_id TEXT,
  ticket_id UUID REFERENCES tickets(id),
  site TEXT REFERENCES sites(name) ON UPDATE CASCADE,
  
  -- Vendor
  vendor_name TEXT,
  vendor_contact TEXT,
  work_description TEXT NOT NULL,
  approved_amount NUMERIC,
  invoice_number TEXT,
  
  -- Job card specific
  km_reading INTEGER,
  work_inspected_by TEXT,
  
  -- Payment
  payable_amount NUMERIC,
  advance_amount NUMERIC,
  invoice_value NUMERIC,
  paid_amount NUMERIC,
  payment_date DATE,
  payment_status TEXT CHECK (payment_status IN ('Pending', 'Partial', 'Paid')) DEFAULT 'Pending',
  transaction_details TEXT,
  payment_via TEXT,
  
  -- Documents (Google Drive URLs)
  bill_attachment TEXT,
  approval_screenshot TEXT,
  job_card_upload TEXT,
  
  -- Metadata
  created_by_user_id UUID REFERENCES users(id) NOT NULL,
  accounting_status TEXT CHECK (accounting_status IN ('Pending', 'Processed', 'Closed')) DEFAULT 'Pending'
);

-- Indexes for performance
CREATE INDEX idx_tickets_site ON tickets(site);
CREATE INDEX idx_tickets_status ON tickets(status);
CREATE INDEX idx_tickets_created_at ON tickets(created_at DESC);
CREATE INDEX idx_tickets_vehicle_number ON tickets(vehicle_number);
CREATE INDEX idx_tickets_job_sheet_id ON tickets(job_sheet_id);
CREATE INDEX idx_finance_job_sheet_id ON finance_entries(job_sheet_id);
CREATE INDEX idx_finance_ticket_id ON finance_entries(ticket_id);

-- Row Level Security (RLS)
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- RLS Policies for tickets
-- Supervisors see only their site's tickets
CREATE POLICY "Supervisors see own site tickets"
  ON tickets FOR SELECT
  USING (
    auth.uid() IN (
      SELECT id FROM users 
      WHERE role = 'supervisor' 
      AND site = tickets.site
    )
  );

-- Maintenance exec sees all tickets
CREATE POLICY "Exec sees all tickets"
  ON tickets FOR ALL
  USING (
    auth.uid() IN (
      SELECT id FROM users WHERE role = 'maintenance_exec'
    )
  );

-- Supervisors can create tickets
CREATE POLICY "Supervisors create tickets"
  ON tickets FOR INSERT
  WITH CHECK (
    auth.uid() IN (
      SELECT id FROM users WHERE role = 'supervisor'
    )
  );

-- Similar policies for finance_entries...
```

---

## Google Drive Integration

### Setup

1. **Create Google Cloud Project**
2. **Enable Google Drive API**
3. **Create Service Account**
   - Download JSON key
   - Share drive folder with service account email

### Environment Variables

```bash
VITE_GOOGLE_DRIVE_FOLDER_ID=your_folder_id
VITE_GOOGLE_SERVICE_ACCOUNT_KEY=base64_encoded_json_key
```

### Upload Flow

```javascript
// Frontend uploads to backend endpoint
POST /api/upload-photo
{
  file: File (multipart),
  ticket_id: uuid,
  uploaded_by: user_id
}

// Backend (Supabase Edge Function)
// 1. Authenticate with Google Drive using service account
// 2. Upload file to shared folder
// 3. Generate shareable link
// 4. Return URL
// 5. Store URL in tickets.photos array

Response:
{
  url: "https://drive.google.com/file/d/FILE_ID/view",
  file_id: "FILE_ID"
}
```

---

## API Endpoints (Supabase Functions)

### Tickets

```
POST   /tickets              - Create ticket
GET    /tickets              - List tickets (filtered by role)
GET    /tickets/:id          - Get ticket details
PATCH  /tickets/:id          - Update ticket
POST   /tickets/:id/merge    - Merge ticket into another
DELETE /tickets/:id/photos   - Delete photo from Drive
```

### Finance

```
POST   /finance              - Create finance entry
GET    /finance              - List finance entries
GET    /finance/:id          - Get finance entry
PATCH  /finance/:id          - Update finance entry
GET    /finance/by-jobsheet/:id - Get entries for job sheet
```

### Dashboard

```
GET /dashboard/supervisor/:site  - Supervisor dashboard stats
GET /dashboard/maintenance       - Maintenance exec dashboard
GET /dashboard/finance           - Finance dashboard
```

### Utility

```
POST /upload-photo               - Upload to Google Drive
GET  /sites                      - List all sites
GET  /vehicles                   - List all vehicles
GET  /vehicles/by-site/:site     - Vehicles for a site
```

---

## Frontend Structure

```
src/
├── components/
│   ├── tickets/
│   │   ├── TicketForm.jsx          (Mobile-optimized form)
│   │   ├── TicketList.jsx          (Filterable list)
│   │   ├── TicketCard.jsx          (Mobile card view)
│   │   ├── TicketDetail.jsx        (Full ticket view)
│   │   └── TicketFilters.jsx       (Site, status, date filters)
│   ├── finance/
│   │   ├── FinanceForm.jsx
│   │   ├── FinanceList.jsx
│   │   └── FinanceDetail.jsx
│   ├── dashboard/
│   │   ├── SupervisorDashboard.jsx
│   │   ├── MaintenanceDashboard.jsx
│   │   └── FinanceDashboard.jsx
│   └── shared/
│       ├── PhotoUpload.jsx         (Camera + gallery)
│       ├── VehicleSearch.jsx       (Autocomplete)
│       ├── DatePicker.jsx
│       └── StatusBadge.jsx         (SLA indicators)
├── hooks/
│   ├── useTickets.js               (React Query hook)
│   ├── useFinance.js
│   └── useAuth.js
├── lib/
│   ├── supabase.js                 (Supabase client)
│   ├── googleDrive.js              (Drive upload logic)
│   └── slaCalculator.js            (SLA logic)
├── pages/
│   ├── Login.jsx
│   ├── Dashboard.jsx
│   ├── Tickets.jsx
│   ├── TicketDetails.jsx
│   ├── Finance.jsx
│   └── Profile.jsx
└── App.jsx
```

---

## Mobile-First Design Principles

### Key Screens (Mobile)

1. **Ticket Submission**
   - Large touch targets (48px min)
   - Auto-fill supervisor details
   - Camera integration for photos
   - Vehicle number autocomplete

2. **Ticket List**
   - Card-based layout
   - Swipe to refresh
   - Infinite scroll
   - SLA status color-coded

3. **Dashboard**
   - Big numbers (ticket counts)
   - Simple charts (bar/pie)
   - Quick actions (Submit ticket button)

### Desktop Enhancements

- Table view for tickets (more columns visible)
- Multi-select for bulk actions
- Keyboard shortcuts
- Larger charts with drill-downs

---

## Deployment Plan

### Prerequisites

1. **Supabase Project**
   - Create free project at supabase.com
   - Run SQL schema from above
   - Set up RLS policies
   - Create initial users

2. **Google Cloud Setup**
   - Create service account
   - Share Drive folder
   - Store credentials securely

3. **Vercel Account**
   - Connect GitHub repo
   - Set environment variables

### Environment Variables

```bash
# Supabase
VITE_SUPABASE_URL=https://xxx.supabase.co
VITE_SUPABASE_ANON_KEY=your_anon_key

# Google Drive
VITE_GOOGLE_DRIVE_FOLDER_ID=your_folder_id
GOOGLE_SERVICE_ACCOUNT_KEY={"type":"service_account",...}

# App Config
VITE_APP_NAME=NVS Maintenance
VITE_ASSIGNMENT_SLA_DAYS=1
```

### Deployment Steps

```bash
# 1. Create React app
npm create vite@latest nvs-maintenance -- --template react
cd nvs-maintenance
npm install

# 2. Install dependencies
npm install @supabase/supabase-js
npm install tailwindcss @headlessui/react
npm install react-query
npm install react-hook-form
npm install date-fns
npm install recharts (for charts)

# 3. Configure Tailwind (mobile-first)
npx tailwindcss init -p

# 4. Set up Supabase client
# Create src/lib/supabase.js

# 5. Build and deploy
npm run build
vercel --prod
```

---

## Data Migration (Phase 2+)

### From Google Sheets to Supabase

**Don't import old data yet.** Only after Phase 1 is approved.

When ready:

```python
# migration script
import pandas as pd
import psycopg2

# 1. Read "Maintenance register" sheet
df = pd.read_excel('NVS_Maintenance_register.xlsx', sheet_name='Maintenance register')

# 2. Clean data
# - Parse dates
# - Map status values
# - Handle nulls

# 3. Insert to Supabase
# INSERT INTO tickets (...)
# VALUES (...)

# 4. Verify counts match
```

---

## Success Metrics

### Phase 1 Success Criteria

- [ ] Supervisors can submit tickets from mobile in <2 min
- [ ] Maintenance exec can see all tickets instantly
- [ ] Filters work (site, date, vehicle)
- [ ] Photos upload to Google Drive successfully
- [ ] No tickets lost (compared to Google Sheets)

### Phase 2 Success Criteria

- [ ] SLA violations automatically flagged
- [ ] Finance entries linked to tickets
- [ ] Dashboard loads in <3 seconds

### Phase 3 Success Criteria

- [ ] Dashboards replace all Google Sheets analytics
- [ ] Boss can see real-time metrics
- [ ] Export to Excel works

---

## Risk Mitigation

### Technical Risks

**Risk:** Supabase free tier limits hit
**Mitigation:** Monitor usage, upgrade to Pro ($25/mo) if needed within 3 months

**Risk:** Google Drive API quota exceeded
**Mitigation:** Use multiple service accounts if needed (each gets 20K requests/day)

**Risk:** Photos fill up Drive storage
**Mitigation:** Compress images before upload, implement cleanup policy (delete photos older than 2 years)

### User Adoption Risks

**Risk:** Supervisors resist new system
**Mitigation:** 
- Keep form simple (same fields as Google Form)
- Make mobile UX faster than typing in Google Forms
- Show immediate value (see ticket status instantly)

**Risk:** Maintenance exec workflow disrupted
**Mitigation:**
- Parallel run for 2 weeks (keep updating sheets until confident)
- Train on ticket merging/duplicate marking
- Provide keyboard shortcuts for fast desktop work

---

## Open Questions / Decisions Needed

1. **User Authentication**
   - Magic link (email-only login)?
   - Or email + password?
   - **Recommendation:** Email + password for now (simpler)

2. **Ticket Numbering**
   - Continue from 1434 (last ticket in sheets)?
   - Or restart from 1?
   - **Recommendation:** Continue from 1434

3. **Physical Job Sheet Book**
   - Keep using physical books?
   - Or digitize job sheets in app?
   - **Recommendation:** Keep physical book for now, just track ID in app

4. **Duplicate Detection**
   - Automatic (same vehicle + same day)?
   - Or manual (exec marks duplicates)?
   - **Recommendation:** Manual for now (exec knows context)

5. **Site Access Control**
   - Supervisors can ONLY see their site?
   - Or see all but filter by default?
   - **Recommendation:** Hard restriction (only their site) for security

---

## Next Steps

### Immediate (Today)

1. ✅ Review this PRD
2. Create Supabase account + project
3. Create Google Cloud project + service account
4. Set up GitHub repo
5. Initialize React app

### This Week

1. Implement Phase 1 core features
2. Test ticket submission flow
3. Test with maintenance exec
4. Iterate based on feedback

### Next Week

1. Add SLA automation
2. Build finance module
3. Integrate Google Drive uploads

---

## Questions for Product Manager

1. Should supervisors be able to edit submitted tickets, or only maintenance exec?
2. Do you want push notifications (requires PWA setup)?
3. Should the app work offline (submit tickets without internet)?
4. What's the priority: Speed or features? (Determines if we cut scope)

---

## Appendix: Current Data Insights

From your 12,000+ ticket analysis:

- **Most common category:** Mechanical work (~40% of tickets)
- **Average tickets per month:** ~350-400
- **Top violating sites:** (need to analyze TC(S) sheet for this)
- **SLA adherence rate:** ~65-70% (estimated from sheets)
- **Finance entries:** ~20,000+ rows (spare parts, invoices)

**Key insight:** You're managing significant volume. This isn't a toy app - it's enterprise-grade fleet maintenance. Build accordingly.

---

**END OF PRD**

*This document is a living document. Update as requirements evolve.*
