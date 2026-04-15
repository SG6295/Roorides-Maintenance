-- The vehicles table was created manually with 'number' instead of 'registration_number'.
-- This aligns the schema with what the app expects.

ALTER TABLE vehicles RENAME COLUMN number TO registration_number;

ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS make TEXT;
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS model TEXT;
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS year INTEGER;
ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS notes TEXT;
