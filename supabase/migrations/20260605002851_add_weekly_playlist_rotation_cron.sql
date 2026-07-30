/*
  # Add automatic weekly playlist rotation

  1. Functions
    - `dispatch_playlist_rotation()` - Calls the playlist-rotate edge function
      to create next week's playlist with a random genre

  2. Cron Jobs
    - `playlist_rotation_weekly` - Runs every Saturday at 8:00 UTC (9:00 AM WAT)
      to create the following Monday's playlist ahead of time

  3. Notes
    - The edge function picks from 30 genre options, avoiding the last 8 used
    - If the next week's playlist already exists (admin created one manually), it skips
    - Staff can still create their own personal playlists independently
*/

CREATE OR REPLACE FUNCTION public.dispatch_playlist_rotation()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base_url text;
  v_service_token text;
BEGIN
  SELECT function_base_url, service_token
  INTO v_base_url, v_service_token
  FROM email_settings
  LIMIT 1;

  IF v_base_url IS NULL OR v_service_token IS NULL THEN
    RAISE LOG 'playlist_rotation: missing email_settings config, skipping';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_base_url || '/functions/v1/playlist-rotate',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_token,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
END;
$$;

-- Schedule cron job: every Saturday at 8:00 UTC
SELECT cron.schedule(
  'playlist_rotation_weekly',
  '0 8 * * 6',
  $$SELECT public.dispatch_playlist_rotation();$$
);
