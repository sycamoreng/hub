/*
  # Fix playlist rotation dispatcher - same pattern as other cron dispatchers

  The dispatch_playlist_rotation() function was silently failing because
  email_settings.function_base_url and service_token are empty.
  
  Apply the same fix as the other dispatchers: fall back to the project URL
  and anon key when email_settings values are missing.
*/

CREATE OR REPLACE FUNCTION public.dispatch_playlist_rotation()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_url text;
  v_token text;
BEGIN
  -- Try email_settings first for backward compatibility
  SELECT function_base_url, service_token
  INTO v_url, v_token
  FROM email_settings
  ORDER BY created_at ASC
  LIMIT 1;

  -- Use email_settings values if populated, otherwise use project defaults
  IF COALESCE(v_url, '') = '' THEN
    v_url := 'https://zefhzobaostawwramtfv.supabase.co';
  END IF;

  IF COALESCE(v_token, '') = '' THEN
    v_token := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InplZmh6b2Jhb3N0YXd3cmFtdGZ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY4MTg0NjcsImV4cCI6MjA5MjM5NDQ2N30.KOo1dLJwYjtkC4JRM8fKveLAKvIYk3djJHRUcmhy9v0';
  END IF;

  PERFORM net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/playlist-rotate',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_token,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
END;
$function$;
