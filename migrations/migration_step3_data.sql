-- Migration Step 3: Migrate existing Pending status to New
-- Run this AFTER step 2 completes

UPDATE tickets SET status = 'New' WHERE status = 'Pending';

-- After this succeeds, run migration_step4.sql
