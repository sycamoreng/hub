/*
  # Fix Cron Dispatcher Functions - Remove dependency on email_settings URL/token

  1. Problem
    - All cron dispatcher functions depend on `email_settings.function_base_url`
      and `email_settings.service_token` being populated
    - These fields are currently empty strings, causing all cron jobs to silently skip
    - Birthday posts, guess-who puzzles, and spark generation all fail silently

  2. Solution
    - Rewrite dispatcher functions to use the project's Supabase URL directly
    - Use the anon key for edge functions that have JWT verification disabled
    - Fall back to `email_settings` values if available (for backward compatibility)

  3. Modified Functions
    - `dispatch_birthday_check()` - birthday/anniversary daily cron
    - `dispatch_guess_who_generation()` - guess who daily puzzle
    - `dispatch_spark_generation()` - spark generation every 3 days

  4. Notes
    - Edge functions birthday-anniversary-check, guess-who-generate, and spark-generate
      all have verifyJWT=false, so the anon key is sufficient
    - The project URL is stable and won't change
    - email_settings.function_base_url is still respected if populated (takes priority)
*/

-- Rewrite dispatch_birthday_check to not silently fail
CREATE OR REPLACE FUNCTION public.dispatch_birthday_check()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_url text;
  v_token text;
  v_settings record;
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
    url := rtrim(v_url, '/') || '/functions/v1/birthday-anniversary-check',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_token,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
END;
$function$;

-- Rewrite dispatch_guess_who_generation to not silently fail
CREATE OR REPLACE FUNCTION public.dispatch_guess_who_generation()
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
    url := rtrim(v_url, '/') || '/functions/v1/guess-who-generate',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_token,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
END;
$function$;

-- Rewrite dispatch_spark_generation to not silently fail
CREATE OR REPLACE FUNCTION public.dispatch_spark_generation()
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
    url := rtrim(v_url, '/') || '/functions/v1/spark-generate',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_token,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
END;
$function$;
