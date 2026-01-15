-- Create SLA Events table
CREATE TABLE IF NOT EXISTS sla_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    ticket_id UUID REFERENCES tickets(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('CREATED', 'ASSIGNED', 'COMPLETED', 'STATUS_CHANGE', 'REJECTED', 'COMMENT')),
    created_by UUID REFERENCES auth.users(id) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Enable RLS
ALTER TABLE sla_events ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view events for tickets they can access" ON sla_events
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM tickets
            WHERE tickets.id = sla_events.ticket_id
            -- Add logic here if strict RLS is needed, generally authenticated users can view for now
            -- or rely on the fact they can't get the ticket_ID if they can't see the ticket.
            -- For simplicity and alignment with current ticket policy:
        )
    );

-- Allow authenticated users to insert events (application logic controls valid events)
CREATE POLICY "Users can insert events" ON sla_events
    FOR INSERT
    WITH CHECK (auth.uid() = created_by);

-- Create index for faster timeline lookups
CREATE INDEX idx_sla_events_ticket_id ON sla_events(ticket_id);
