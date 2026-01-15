
-- Create user_settings table
CREATE TABLE IF NOT EXISTS public.user_settings (
    user_id UUID REFERENCES auth.users(id) PRIMARY KEY,
    notify_daily_digest BOOLEAN DEFAULT false,
    digest_preferences JSONB DEFAULT '{"sla_expiring": true, "rejected_24h": true, "created_24h": true}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view their own settings" ON public.user_settings
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own settings" ON public.user_settings
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own settings" ON public.user_settings
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Trigger to update updated_at
CREATE EXTENSION IF NOT EXISTS moddatetime;

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.user_settings
    FOR EACH ROW EXECUTE PROCEDURE moddatetime (updated_at);
