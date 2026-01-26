-- Migration Step 1: Add 'New' value to the status enum
-- Run this FIRST, then wait for it to complete before proceeding

ALTER TYPE ticket_status_new ADD VALUE IF NOT EXISTS 'New';

-- After this succeeds, run migration_step2.sql
