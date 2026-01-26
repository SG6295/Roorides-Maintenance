-- Fix: Add missing status values to the enum
-- Run this in Supabase SQL Editor

-- Add all the new status values that might be missing
ALTER TYPE ticket_status_new ADD VALUE IF NOT EXISTS 'Accepted';
ALTER TYPE ticket_status_new ADD VALUE IF NOT EXISTS 'Work In Progress';
ALTER TYPE ticket_status_new ADD VALUE IF NOT EXISTS 'Resolved';
ALTER TYPE ticket_status_new ADD VALUE IF NOT EXISTS 'Closed';
ALTER TYPE ticket_status_new ADD VALUE IF NOT EXISTS 'Rejected';

-- Verify the enum values after running:
-- SELECT enumlabel FROM pg_enum WHERE enumtypid = 'ticket_status_new'::regtype;
