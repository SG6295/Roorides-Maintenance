-- Migration Step 2: Add new columns
-- Run this AFTER step 1 completes

-- Add feedback column to issues table
ALTER TABLE issues ADD COLUMN IF NOT EXISTS feedback INTEGER DEFAULT NULL;

-- Add rejection columns to tickets table
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS rejection_reason TEXT DEFAULT NULL;
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS rejection_comment TEXT DEFAULT NULL;

-- After this succeeds, run migration_step3.sql
