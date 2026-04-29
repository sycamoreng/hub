/*
  # Email scheduling, mention triggers, and user opt-outs backfill

  1. Extensions
    - Enable `pg_cron` and `pg_net` so we can schedule queue drains and HTTP-call
      the email edge function for daily jobs.

  2. Schema
    - `email_settings`: add `app_base_url` (used for links in emails), `function_base_url`
      (usually the Supabase URL) and `service_token` (cached to authorize pg_cron calls).
    - `notification_preferences` auto-provisioned for every auth user via trigger.

  3. Triggers
    - `tg_queue_mention_email` (after insert on `post_mentions` and `announcement_mentions`):
      builds a queued email by merging the `mention_notification` template with the data of
      the mentioner, the mentioned user, and a deep link. Respects the recipient's
      `email_mentions` preference and the global `default_enabled` switch.

  4. Scheduling
    - pg_cron schedules three jobs, each calling the email function via pg_net:
      - every minute: drain `email_queue`
      - daily 07:00 UTC: queue upcoming-event reminders
      - Mondays 08:00 UTC: queue weekly digest for each active staff member

  5. Security
    - Helper `public.render_template` runs as SECURITY INVOKER (pure function, safe).
    - No policy changes required; triggers and jobs run with definer privileges.
*/

-- Extensions
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- email_settings additions
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='email_settings' AND column_name='app_base_url') THEN
    ALTER TABLE email_settings ADD COLUMN app_base_url text DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='email_settings' AND column_name='function_base_url') THEN
    ALTER TABLE email_settings ADD COLUMN function_base_url text DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='email_settings' AND column_name='service_token') THEN
    ALTER TABLE email_settings ADD COLUMN service_token text DEFAULT '';
  END IF;
END $$;

-- Template renderer: replaces {{var}} with values from a jsonb map
CREATE OR REPLACE FUNCTION public.render_template(tpl text, vars jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  k text;
  v text;
  out text := COALESCE(tpl, '');
BEGIN
  IF vars IS NULL THEN RETURN out; END IF;
  FOR k, v IN SELECT key, COALESCE(value #>> '{}', '') FROM jsonb_each(vars) LOOP
    out := replace(out, '{{' || k || '}}', v);
    out := replace(out, '{{ ' || k || ' }}', v);
  END LOOP;
  RETURN out;
END;
$$;

-- Ensure preferences exist per user
CREATE OR REPLACE FUNCTION public.tg_ensure_notification_prefs()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notification_preferences (user_id) VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ensure_notification_prefs ON auth.users;
CREATE TRIGGER ensure_notification_prefs
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.tg_ensure_notification_prefs();

-- Backfill preferences for existing users
INSERT INTO notification_preferences (user_id)
SELECT u.id FROM auth.users u
LEFT JOIN notification_preferences p ON p.user_id = u.id
WHERE p.user_id IS NULL;

-- Build an email from the mention_notification template
CREATE OR REPLACE FUNCTION public.queue_mention_email(
  p_recipient_user_id uuid,
  p_mentioner_name text,
  p_snippet text,
  p_link_path text,
  p_reference jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings record;
  v_template record;
  v_prefs record;
  v_staff record;
  v_vars jsonb;
  v_subject text;
  v_html text;
  v_text text;
  v_unsub text;
  v_footer text;
  v_link text;
BEGIN
  SELECT * INTO v_settings FROM email_settings ORDER BY created_at ASC LIMIT 1;
  IF v_settings IS NULL OR v_settings.default_enabled = false THEN RETURN; END IF;

  SELECT * INTO v_template FROM email_templates WHERE slug = 'mention_notification' AND is_active = true;
  IF v_template IS NULL THEN RETURN; END IF;

  SELECT * INTO v_prefs FROM notification_preferences WHERE user_id = p_recipient_user_id;
  IF v_prefs IS NULL THEN
    INSERT INTO notification_preferences (user_id) VALUES (p_recipient_user_id) ON CONFLICT DO NOTHING;
    SELECT * INTO v_prefs FROM notification_preferences WHERE user_id = p_recipient_user_id;
  END IF;
  IF v_prefs.email_mentions = false THEN RETURN; END IF;

  SELECT s.full_name, s.email INTO v_staff FROM staff_members s
    WHERE s.auth_user_id = p_recipient_user_id AND s.is_active = true AND s.email IS NOT NULL
    LIMIT 1;
  IF v_staff IS NULL OR v_staff.email IS NULL THEN RETURN; END IF;

  v_link := CASE WHEN COALESCE(v_settings.app_base_url, '') = '' THEN p_link_path
                 ELSE rtrim(v_settings.app_base_url, '/') || p_link_path END;
  v_unsub := CASE WHEN COALESCE(v_settings.app_base_url, '') = '' THEN ''
                  ELSE rtrim(v_settings.app_base_url, '/') || '/unsubscribe?token=' || v_prefs.unsubscribe_token END;

  v_vars := jsonb_build_object(
    'first_name', COALESCE(split_part(v_staff.full_name, ' ', 1), 'there'),
    'mentioner_name', COALESCE(p_mentioner_name, 'Someone'),
    'snippet', COALESCE(p_snippet, ''),
    'link_url', v_link,
    'brand_color', COALESCE(v_settings.brand_color, '#0f6e42'),
    'unsubscribe_url', v_unsub
  );

  v_footer := public.render_template(COALESCE(v_settings.footer_html, ''), v_vars);
  v_vars := v_vars || jsonb_build_object('footer_html', v_footer);

  v_subject := public.render_template(v_template.subject, v_vars);
  v_html := public.render_template(v_template.html_body, v_vars);
  v_text := public.render_template(COALESCE(v_template.text_body, ''), v_vars);

  INSERT INTO email_queue (
    to_email, to_name, subject, html_body, text_body, template_slug, trigger, payload, reference_id, user_id, status
  ) VALUES (
    v_staff.email, v_staff.full_name, v_subject, v_html, v_text, 'mention_notification', 'mention',
    v_vars, p_reference, p_recipient_user_id, 'pending'
  );
END;
$$;

-- Post mention email trigger
CREATE OR REPLACE FUNCTION public.tg_queue_post_mention_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_post record;
  v_mentioner text;
  v_snippet text;
BEGIN
  SELECT p.id, p.content, p.author_id INTO v_post FROM posts p WHERE p.id = NEW.post_id;
  IF v_post IS NULL THEN RETURN NEW; END IF;
  IF NEW.user_id = v_post.author_id THEN RETURN NEW; END IF;

  SELECT COALESCE(s.full_name, 'A colleague') INTO v_mentioner
    FROM staff_members s WHERE s.auth_user_id = v_post.author_id LIMIT 1;
  IF v_mentioner IS NULL THEN v_mentioner := 'A colleague'; END IF;

  v_snippet := LEFT(COALESCE(v_post.content, ''), 220);
  IF LENGTH(COALESCE(v_post.content, '')) > 220 THEN v_snippet := v_snippet || '...'; END IF;

  PERFORM public.queue_mention_email(
    NEW.user_id, v_mentioner, v_snippet, '/feed',
    jsonb_build_object('post_id', NEW.post_id)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS post_mention_email ON public.post_mentions;
CREATE TRIGGER post_mention_email
AFTER INSERT ON public.post_mentions
FOR EACH ROW EXECUTE FUNCTION public.tg_queue_post_mention_email();

-- Announcement mention email trigger
CREATE OR REPLACE FUNCTION public.tg_queue_announcement_mention_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ann record;
  v_snippet text;
BEGIN
  SELECT id, title, content INTO v_ann FROM announcements WHERE id = NEW.announcement_id;
  IF v_ann IS NULL THEN RETURN NEW; END IF;

  v_snippet := LEFT(COALESCE(v_ann.content, ''), 220);
  IF LENGTH(COALESCE(v_ann.content, '')) > 220 THEN v_snippet := v_snippet || '...'; END IF;

  PERFORM public.queue_mention_email(
    NEW.user_id, 'An admin', COALESCE(v_ann.title, '') || ' - ' || v_snippet, '/feed',
    jsonb_build_object('announcement_id', NEW.announcement_id)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS announcement_mention_email ON public.announcement_mentions;
CREATE TRIGGER announcement_mention_email
AFTER INSERT ON public.announcement_mentions
FOR EACH ROW EXECUTE FUNCTION public.tg_queue_announcement_mention_email();

-- Helper: call email edge function
CREATE OR REPLACE FUNCTION public.dispatch_email_job(action text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings record;
  v_url text;
  v_headers jsonb;
BEGIN
  SELECT * INTO v_settings FROM email_settings ORDER BY created_at ASC LIMIT 1;
  IF v_settings IS NULL THEN RETURN; END IF;
  IF COALESCE(v_settings.function_base_url, '') = '' OR COALESCE(v_settings.service_token, '') = '' THEN RETURN; END IF;

  v_url := rtrim(v_settings.function_base_url, '/') || '/functions/v1/email/' || action;
  v_headers := jsonb_build_object(
    'Authorization', 'Bearer ' || v_settings.service_token,
    'Content-Type', 'application/json'
  );

  PERFORM net.http_post(url := v_url, body := '{}'::jsonb, headers := v_headers);
END;
$$;

-- Schedule: every minute drain queue
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'email_run_queue') THEN
    PERFORM cron.schedule('email_run_queue', '* * * * *', $cron$SELECT public.dispatch_email_job('run_queue');$cron$);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'email_daily_reminders') THEN
    PERFORM cron.schedule('email_daily_reminders', '0 7 * * *', $cron$SELECT public.dispatch_email_job('daily_reminders');$cron$);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'email_weekly_digest') THEN
    PERFORM cron.schedule('email_weekly_digest', '0 8 * * 1', $cron$SELECT public.dispatch_email_job('weekly_digest');$cron$);
  END IF;
END $$;
