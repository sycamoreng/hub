/*
  # Add automated spark generation cron job

  1. Functions
    - `dispatch_spark_generation()` - Calls the spark-generate edge function to create
      new daily sparks using AI

  2. Cron Jobs
    - `spark_generation_every_3_days` - Runs every 3 days at 5:00 UTC (6:00 AM WAT)
      to generate new spark trivia questions

  3. Notes
    - The edge function checks which upcoming days are missing sparks and fills them
    - Generates 3 days of sparks at a time so there's always a buffer
    - Uses Anthropic AI to create varied trivia questions
*/

CREATE OR REPLACE FUNCTION public.dispatch_spark_generation()
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
    RAISE LOG 'spark_generation: missing email_settings config, skipping';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_base_url || '/functions/v1/spark-generate',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_token,
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
END;
$$;

-- Schedule cron job: every 3 days at 5:00 UTC
SELECT cron.schedule(
  'spark_generation_every_3_days',
  '0 5 */3 * *',
  $$SELECT public.dispatch_spark_generation();$$
);
