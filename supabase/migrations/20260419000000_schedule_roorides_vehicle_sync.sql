-- Schedule a daily sync of vehicles from the Roorides parent application.
-- Runs at midnight UTC every day via pg_cron + pg_net.
-- The edge function authenticates with Roorides, fetches all vehicles, and
-- upserts them into the local vehicles table without overwriting site assignments.

SELECT cron.schedule(
  'sync-roorides-vehicles-daily',
  '0 0 * * *',
  $$
  SELECT net.http_post(
    url     := 'https://awbovpblaxwpsuclpiyh.supabase.co/functions/v1/sync-roorides-vehicles',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF3Ym92cGJsYXh3cHN1Y2xwaXloIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY4MjI5NDgsImV4cCI6MjA4MjM5ODk0OH0.oj6m_Z__bb6v3LXfwx925lPVokRiAIigv24lKz7NkCc'
    ),
    body    := '{}'::jsonb
  )
  $$
);
