/*
  # Schedule daily Google Workspace sync via pg_cron

  Adds `dispatch_google_sync()` that posts to the google-sync edge function
  when auto_sync_enabled is true. Scheduled daily at 03:00 UTC.
*/

CREATE OR REPLACE FUNCTION public.dispatch_google_sync()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled boolean;
  v_settings record;
  v_url text;
  v_headers jsonb;
BEGIN
  SELECT auto_sync_enabled INTO v_enabled FROM google_sync_settings WHERE id = 'default';
  IF NOT COALESCE(v_enabled, false) THEN RETURN; END IF;

  SELECT * INTO v_settings FROM email_settings ORDER BY created_at ASC LIMIT 1;
  IF v_settings IS NULL THEN RETURN; END IF;
  IF COALESCE(v_settings.function_base_url, '') = '' OR COALESCE(v_settings.service_token, '') = '' THEN RETURN; END IF;

  v_url := rtrim(v_settings.function_base_url, '/') || '/functions/v1/google-sync?action=apply';
  v_headers := jsonb_build_object(
    'Authorization', 'Bearer ' || v_settings.service_token,
    'Content-Type', 'application/json'
  );

  PERFORM net.http_post(url := v_url, body := '{}'::jsonb, headers := v_headers);
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'google_sync_daily') THEN
    PERFORM cron.schedule('google_sync_daily', '0 3 * * *', $cron$SELECT public.dispatch_google_sync();$cron$);
  END IF;
END $$;
