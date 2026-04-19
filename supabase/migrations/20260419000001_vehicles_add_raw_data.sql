-- Store the complete vehicle payload from the Roorides parent API.
-- This ensures no data is lost during sync, and future features can access
-- any field without requiring a new migration.
-- Structured columns (registration_number, make, model, etc.) are kept for
-- querying and indexing; raw_data is the source of truth for everything else.

ALTER TABLE vehicles ADD COLUMN IF NOT EXISTS raw_data jsonb;
