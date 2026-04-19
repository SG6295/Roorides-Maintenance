-- Create vehicle_sites junction table to support many-to-many vehicle-site relationships.
-- Sites come from the Roorides API 'school' field, synced automatically at midnight and on-demand.

CREATE TABLE vehicle_sites (
  vehicle_id uuid NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  site_name  text NOT NULL REFERENCES sites(name)   ON DELETE CASCADE,
  PRIMARY KEY (vehicle_id, site_name)
);

ALTER TABLE vehicle_sites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read vehicle_sites"
  ON vehicle_sites FOR SELECT
  USING (auth.role() = 'authenticated');

-- Remove vehicles.site single-site column (replaced by the junction table).
-- Column is nullable and currently NULL for all rows because sites table was empty.
ALTER TABLE vehicles DROP COLUMN IF EXISTS site;
