-- Migration Step 9: Set default status to 'New'
-- Run this AFTER step 8 completes

ALTER TABLE tickets ALTER COLUMN status SET DEFAULT 'New';

-- Verify the change
-- SELECT column_default FROM information_schema.columns WHERE table_name = 'tickets' AND column_name = 'status';
