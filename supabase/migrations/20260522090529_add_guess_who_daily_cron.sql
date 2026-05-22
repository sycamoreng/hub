/*
  # Add daily cron job for Guess Who puzzle generation

  1. Functions
    - `dispatch_guess_who_generation()` - Calls the guess-who-generate edge function
      to create a new daily puzzle

  2. Cron Jobs
    - `guess_who_daily_generate` - Runs daily at 4:00 UTC (5:00 AM WAT) to ensure
      a new Guess Who puzzle is available each morning

  3. Notes
    - The edge function already checks if today's puzzle exists before creating one
    - Running daily ensures no gaps in the game schedule
*/

CREATE OR REPLACE FUNCTION public.dispatch_guess_who_generation()
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
    RAISE LOG 'guess_who_generation: missing email_settings config, skipping';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_base_url || '/functions/v1/guess-who-generate',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_token,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
END;
$$;

SELECT cron.schedule(
  'guess_who_daily_generate',
  '0 4 * * *',
  $$SELECT public.dispatch_guess_who_generation();$$
);
