-- Part 2: Create New Tables

BEGIN;

-- 1. Job Cards
CREATE TABLE IF NOT EXISTS job_cards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_card_number INTEGER GENERATED ALWAYS AS IDENTITY,
    created_at TIMESTAMP DEFAULT NOW(),
    
    type work_type_enum NOT NULL,
    
    assigned_mechanic_id UUID REFERENCES users(id),
    vendor_name TEXT,
    
    vehicle_number TEXT NOT NULL,
    site TEXT NOT NULL,
    
    status job_card_status DEFAULT 'Open',
    completed_at TIMESTAMP,
    remarks TEXT,
    
    CONSTRAINT check_assignment_strict CHECK (
        (type = 'InHouse'::work_type_enum AND assigned_mechanic_id IS NOT NULL AND vendor_name IS NULL) OR 
        (type = 'Outsource'::work_type_enum AND vendor_name IS NOT NULL AND assigned_mechanic_id IS NULL)
    ),
    CONSTRAINT check_completed_after_created CHECK (completed_at IS NULL OR completed_at >= created_at)
);

-- 2. Issues
CREATE TABLE IF NOT EXISTS issues (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    issue_number TEXT, 
    created_at TIMESTAMP DEFAULT NOW(),
    
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    job_card_id UUID REFERENCES job_cards(id) ON DELETE SET NULL,
    
    description TEXT NOT NULL,
    category issue_category NOT NULL,
    severity issue_severity DEFAULT 'Minor',
    work_type work_type_enum,
    
    status issue_status DEFAULT 'Open',
    
    sla_days INTEGER,
    sla_end_date DATE,
    sla_status sla_status_enum DEFAULT 'Pending',
    
    rating rating_enum,
    rating_remarks TEXT,
    rated_at TIMESTAMP,

    CONSTRAINT check_rated_at_after_created CHECK (rated_at IS NULL OR rated_at >= created_at)
);

COMMIT;
