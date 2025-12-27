# NVS Maintenance Management System
## Product Requirements Document v1.0

**Last Updated:** December 27, 2025  
**Product Manager:** [Your Name]  
**Tech Stack:** React + Supabase + Google Drive API  
**Deployment:** Vercel (free tier)

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

### 2. Maintenance Executive (Office Role)
**Primary Device:** Desktop (some mobile)  
**Permissions:**
- View ALL tickets across all sites
- Assign tickets (job sheet ID, date, type)
- Mark duplicate tickets
- Merge/combine related tickets
- Update ticket status
- Mark in-house vs outsourced
- View global dashboard (all sites, SLA performance)

### 3. Finance Team (Office Role)
**Primary Device:** Desktop  
**Permissions:**
- Log spare part purchases
- Log outsourced work invoices
- Link expenses to job sheet IDs
- View expense reports
- Mark payment status

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
  job_sheet_id: text (from physical book)
  assigned_date: date
  activity_plan_date: date
  work_type: enum (In House, Outsource)
  status: enum (Pending, Team Assigned, Completed, Rejected)
  
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
  role: enum (supervisor, maintenance_exec, finance)
  site: text (NULL for exec/finance, specific site for supervisors)
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

## Phase Breakdown

### Phase 1: Core Ticket Flow (Week 1-2)

**Goal:** Replace Google Form → Manual Copy workflow

**Features:**
1. **Ticket Submission (Supervisor - Mobile)**
   - Form with all fields from current Google Form
   - Photo upload to Google Drive
   - Site/vehicle dropdowns pre-populated
   - Submit → creates ticket instantly in DB

2. **Ticket List View (All Roles)**
   - Supervisors: See only their site's tickets
   - Maintenance Exec: See ALL tickets
   - Filters: Site, Date range, Status, Vehicle number
   - Search: Vehicle number lookup
   - Sort: By date, status, SLA violation

3. **Ticket Management (Maintenance Exec - Desktop)**
   - View ticket details
   - Assign job sheet ID
   - Set impact (Minor/Major)
   - Set work type (In House/Outsource)
   - Update status
   - Mark as duplicate/merge tickets
   - Add maintenance comments

4. **Basic Dashboard (Both Roles)**
   - Supervisor: Ticket count by status for their site
   - Maintenance Exec: Global stats (total tickets, pending, violated SLA)

**Database Tables:** tickets, users, sites, vehicles

**Auth:** Supabase Auth with email/password, row-level security

**Deliverable:** Working mobile app where supervisors submit tickets, exec manages them

---

### Phase 2: SLA Tracking & Finance (Week 3)

**Goal:** Add automated SLA monitoring + finance integration

**Features:**

1. **SLA Automation**
   - Auto-calculate `sla_end_date` on ticket creation
   - Real-time SLA status (Adhered/Violated) badges
   - Assignment SLA tracking (1-day rule)
   - Completion SLA tracking (based on category + impact)
   - Dashboard: SLA violation alerts

2. **Finance Module**
   - Finance entry form (spare purchases, outsourced work, job cards)
   - Link finance entries to tickets via job sheet ID
   - Auto-populate ticket details when job sheet ID entered
   - Upload bills/invoices to Google Drive
   - View finance entries filtered by date, site, payment status

3. **Enhanced Ticket View**
   - Show linked finance entries on ticket detail page
   - Total expense per ticket
   - Payment status indicator

**Database Tables:** finance_entries

**Deliverable:** SLA violations visible in real-time, finance data linked to tickets

---

### Phase 3: Dashboards & Analytics (Week 4)

**Goal:** Replace Google Sheets dashboard with live analytics

**Features:**

1. **Supervisor Dashboard (Mobile-friendly)**
   - Tickets by status (Pending, Completed, Rejected)
   - Tickets by category breakdown
   - Monthly ticket trend (chart)
   - SLA adherence rate for their site
   - Recent ticket history

2. **Maintenance Executive Dashboard (Desktop)**
   - Global ticket volume (all sites)
   - SLA performance:
     - Assignment SLA adherence %
     - Completion SLA adherence %
   - Tickets by site (top violators)
   - Tickets by category breakdown
   - Monthly trends (tickets created vs completed)
   - Pending tickets older than X days
   - Outsourced vs In-house work ratio

3. **Finance Dashboard**
   - Total expenses by category
   - Pending payments
   - Top vendors by spend
   - Expense trend by month
   - Site-wise expense breakdown

**Deliverable:** Live dashboards replacing Google Sheets analytics

---

### Phase 4: CSAT & Polish (Week 5+)

**Features:**

1. **CSAT Rating System**
   - Supervisors rate completed tickets
   - 3-point scale: Good, Ok, Bad
   - View average CSAT by site
   - View CSAT trend over time

2. **Notifications**
   - Email/in-app notifications for:
     - Supervisor: Ticket completed
     - Maintenance Exec: New ticket created, SLA violation alert
     - Finance: New invoice submitted

3. **Mobile UX Polish**
   - Offline support (submit ticket without internet, syncs later)
   - Photo compression before upload
   - Quick vehicle number scanner (if QR codes on vehicles)

4. **Export/Reports**
   - Export tickets to Excel
   - Monthly maintenance report PDF
   - SLA performance report

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
