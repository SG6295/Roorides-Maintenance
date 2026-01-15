-- Create Audit Logs table
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data JSONB,
    new_data JSONB,
    changed_fields TEXT[], -- Array of field names that changed
    performed_by UUID REFERENCES public.users(id),
    performed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view audit logs" ON audit_logs
    FOR SELECT
    USING (auth.role() = 'authenticated');

-- We won't allow direct INSERTs from client for now to ensure integrity.
-- Instead, we can use a Database Trigger or a Secure Function. 
-- For v0.2 simplicity, we will allow Client Insert for specific defined actions if we do frontend logging,
-- BUT the best practice is a Trigger.
-- Let's stick to Frontend Logging for consistency with SLA Events for now, but restrict it.

CREATE POLICY "Users can insert audit logs" ON audit_logs
    FOR INSERT
    WITH CHECK (auth.uid() = performed_by);

-- Create indexes
CREATE INDEX idx_audit_logs_record_id ON audit_logs(record_id);
CREATE INDEX idx_audit_logs_table_name ON audit_logs(table_name);
