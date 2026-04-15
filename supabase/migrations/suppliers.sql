-- Suppliers table
CREATE TABLE suppliers (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at timestamptz DEFAULT now(),
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),

  -- Page 1: Basic Details
  email text NOT NULL,
  entity_name text NOT NULL,
  entity_type text NOT NULL,
  entity_type_other text,
  registered_office_address text NOT NULL,
  nature_of_work text NOT NULL,
  workshop_address text,
  owner_name text NOT NULL,
  owner_contact text NOT NULL,
  owner_email text,
  accounts_contact_name text,
  accounts_contact_number text NOT NULL,
  accounts_email text,
  sales_contact_name text,
  sales_contact_number text,
  sales_email text,
  po_communication_emails text,

  -- Page 2: Statutory & Compliance
  pan_number text NOT NULL UNIQUE,
  pan_copy_url text NOT NULL,
  gstin text NOT NULL,
  gst_registration_type text NOT NULL,
  gst_certificate_url text,
  msme_udyam_number text,
  udyam_certificate_url text,
  pf_registration_number text,
  pf_certificate_url text,
  esi_registration_number text,
  esi_certificate_url text,
  labour_license_number text,

  -- Page 3: Bank Details
  bank_name text NOT NULL,
  bank_branch text NOT NULL,
  account_holder_name text NOT NULL,
  account_number text NOT NULL,
  ifsc_code text NOT NULL,
  account_type text,
  cancelled_cheque_url text NOT NULL,

  -- Page 4: Work Experience & Capability
  years_of_experience text NOT NULL,
  major_clients text,
  skilled_manpower_available boolean,
  brand_spares_usage text,

  -- Page 5: Commercial & Payment Terms
  payment_terms_days text NOT NULL,
  submitted_by text NOT NULL
);

-- RLS
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;

-- Anyone (including anonymous users) can register
CREATE POLICY "suppliers_public_insert" ON suppliers
  FOR INSERT WITH CHECK (true);

-- Only maintenance_exec and finance can view supplier list
CREATE POLICY "suppliers_auth_select" ON suppliers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
        AND users.role IN ('maintenance_exec', 'finance')
        AND users.is_active = true
    )
  );

-- Only maintenance_exec can update (for approval workflow)
CREATE POLICY "suppliers_exec_update" ON suppliers
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
        AND users.role = 'maintenance_exec'
        AND users.is_active = true
    )
  );

-- Security-definer RPC so anonymous users can check if a PAN is already registered
-- Called on step 2 of the public registration form to give early feedback
CREATE OR REPLACE FUNCTION check_pan_exists(p_pan text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM suppliers WHERE upper(trim(pan_number)) = upper(trim(p_pan))
  );
$$;

GRANT EXECUTE ON FUNCTION check_pan_exists(text) TO anon;
GRANT EXECUTE ON FUNCTION check_pan_exists(text) TO authenticated;
