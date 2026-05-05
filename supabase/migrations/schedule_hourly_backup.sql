-- Schedule hourly backup to Google Drive.
-- 10 AM – 7 PM IST = 04:30 – 13:30 UTC → cron: '30 4-13 * * *'
-- Keeps 7 days of backups; older files are deleted by the edge function itself.

BEGIN;

SELECT cron.schedule(
  'nvs-hourly-backup',
  '30 4-13 * * *',
  $$
  SELECT net.http_post(
    url     := 'https://awbovpblaxwpsuclpiyh.supabase.co/functions/v1/backup-to-drive',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body    := '{"source":"cron"}'::jsonb
  ) AS request_id;
  $$
);

-- Verify the job was created
SELECT jobid, jobname, schedule FROM cron.job WHERE jobname = 'nvs-hourly-backup';

COMMIT;
