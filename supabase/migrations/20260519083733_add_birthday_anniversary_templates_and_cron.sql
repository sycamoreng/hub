/*
  # Add Birthday and Work Anniversary Email Templates + Daily Cron

  1. New Data
    - Email template: `staff_birthday` - sent to the birthday person
    - Email template: `staff_work_anniversary` - sent to the anniversary person

  2. Functions
    - `dispatch_birthday_check()` - calls the birthday-anniversary-check edge function

  3. Cron Job
    - `birthday_anniversary_daily` - runs daily at 6:00 UTC (7:00 AM WAT)

  4. Notes
    - Templates use {{first_name}}, {{full_name}}, {{years}}, {{year_label}} variables
    - Follows existing pattern: email_settings.function_base_url + service_token
    - Notifications go to all staff; emails go to the celebrant
*/

-- Birthday email template
INSERT INTO email_templates (slug, name, description, subject, html_body, text_body, variables, is_system, is_active)
VALUES (
  'staff_birthday',
  'Staff Birthday',
  'Sent to a staff member on their birthday',
  'Happy Birthday, {{first_name}}!',
  '<div style="font-family: -apple-system, BlinkMacSystemFont, ''Segoe UI'', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px 20px;">
    <div style="text-align: center; margin-bottom: 32px;">
      <h1 style="color: #1e293b; font-size: 28px; margin: 0 0 8px;">Happy Birthday, {{first_name}}!</h1>
      <p style="color: #64748b; font-size: 16px; margin: 0;">From everyone at Sycamore</p>
    </div>
    <div style="background: #f8fafc; border-radius: 12px; padding: 24px; margin-bottom: 24px;">
      <p style="color: #334155; font-size: 16px; line-height: 1.6; margin: 0;">
        Wishing you a wonderful birthday, {{full_name}}! We hope your day is filled with joy, celebration and everything that makes you happy.
      </p>
      <p style="color: #334155; font-size: 16px; line-height: 1.6; margin: 16px 0 0;">
        Thank you for being such a valued member of the Sycamore family. Here''s to another great year ahead!
      </p>
    </div>
    <p style="color: #94a3b8; font-size: 13px; text-align: center;">The Sycamore Team</p>
  </div>',
  'Happy Birthday, {{first_name}}! Wishing you a wonderful birthday from everyone at Sycamore. Thank you for being such a valued member of the team.',
  ARRAY['first_name', 'full_name'],
  true,
  true
)
ON CONFLICT (slug) DO NOTHING;

-- Work Anniversary email template
INSERT INTO email_templates (slug, name, description, subject, html_body, text_body, variables, is_system, is_active)
VALUES (
  'staff_work_anniversary',
  'Staff Work Anniversary',
  'Sent to a staff member on their work anniversary',
  'Congratulations on {{year_label}} at Sycamore, {{first_name}}!',
  '<div style="font-family: -apple-system, BlinkMacSystemFont, ''Segoe UI'', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px 20px;">
    <div style="text-align: center; margin-bottom: 32px;">
      <h1 style="color: #1e293b; font-size: 28px; margin: 0 0 8px;">{{year_label}} at Sycamore!</h1>
      <p style="color: #64748b; font-size: 16px; margin: 0;">Congratulations, {{first_name}}</p>
    </div>
    <div style="background: #f8fafc; border-radius: 12px; padding: 24px; margin-bottom: 24px;">
      <p style="color: #334155; font-size: 16px; line-height: 1.6; margin: 0;">
        Today marks {{year_label}} since you joined the Sycamore family, {{full_name}}. What an incredible journey it has been!
      </p>
      <p style="color: #334155; font-size: 16px; line-height: 1.6; margin: 16px 0 0;">
        Your dedication, hard work and contributions have made a real difference. We are grateful to have you on the team and look forward to many more milestones together.
      </p>
    </div>
    <p style="color: #94a3b8; font-size: 13px; text-align: center;">The Sycamore Team</p>
  </div>',
  'Congratulations on {{year_label}} at Sycamore, {{first_name}}! Your dedication and contributions have made a real difference. We look forward to many more milestones together.',
  ARRAY['first_name', 'full_name', 'years', 'year_label'],
  true,
  true
)
ON CONFLICT (slug) DO NOTHING;

-- Dispatcher function for the birthday/anniversary check
CREATE OR REPLACE FUNCTION public.dispatch_birthday_check()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_settings record;
  v_url text;
  v_headers jsonb;
BEGIN
  SELECT * INTO v_settings FROM email_settings ORDER BY created_at ASC LIMIT 1;
  IF v_settings IS NULL THEN RETURN; END IF;
  IF COALESCE(v_settings.function_base_url, '') = '' OR COALESCE(v_settings.service_token, '') = '' THEN RETURN; END IF;

  v_url := rtrim(v_settings.function_base_url, '/') || '/functions/v1/birthday-anniversary-check';
  v_headers := jsonb_build_object(
    'Authorization', 'Bearer ' || v_settings.service_token,
    'Content-Type', 'application/json'
  );

  PERFORM net.http_post(url := v_url, body := '{}'::jsonb, headers := v_headers);
END;
$function$;

-- Schedule daily at 6:00 UTC (7:00 AM WAT)
SELECT cron.schedule(
  'birthday_anniversary_daily',
  '0 6 * * *',
  'SELECT public.dispatch_birthday_check();'
);
