-- Relax Job Card Assignment Constraint
-- Allows Job Cards to be created without immediate assignment (mechanic or vendor)
-- Enforces only that you cannot mix types (e.g. InHouse cannot have vendor_name)

BEGIN;

ALTER TABLE job_cards DROP CONSTRAINT IF EXISTS check_assignment_strict;

ALTER TABLE job_cards ADD CONSTRAINT check_assignment_valid CHECK (
    (type = 'InHouse'::work_type_enum AND vendor_name IS NULL) OR 
    (type = 'Outsource'::work_type_enum AND assigned_mechanic_id IS NULL)
);

COMMIT;
