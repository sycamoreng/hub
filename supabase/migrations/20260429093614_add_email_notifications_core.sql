/*
  # Email notifications — core schema

  1. New Tables
    - `email_settings` (singleton) — global config admins control
      - `from_name`, `from_email`, `reply_to`, `brand_color`
      - `default_enabled` (master kill switch)
      - `provider` (default 'sendgrid')
      - `footer_html` (appended to every email)
    - `email_templates` — named templates with subject + html/text bodies and variables
      - `slug` (unique, e.g. 'announcement_published')
      - `name`, `description`
      - `subject`, `html_body`, `text_body`
      - `variables` (text[]) — allowed substitutions
      - `is_system` (boolean) — true for the built-ins; cannot be deleted
      - `is_active`
    - `email_queue` — pending/processing/sent/failed outbound mail
      - `to_email`, `to_name`, `subject`, `html_body`, `text_body`
      - `template_slug` (nullable), `payload` (jsonb), `trigger` (text)
      - `status`, `attempts`, `last_error`, `scheduled_at`, `sent_at`
      - `user_id` (nullable recipient reference), `reference_id` (jsonb)
    - `email_log` — append-only audit trail
    - `notification_preferences` — per-user opt-outs
      - `user_id` (unique), `email_mentions`, `email_announcements`, `email_weekly_digest`, `email_event_reminders`, `email_broadcasts`
      - `unsubscribe_token` (unique, used for one-click unsubscribe links)

  2. Modified Tables
    - `announcements`: add `email_on_publish` (bool), `email_audience` (text: 'all'|'department'|'mentioned'), `email_department_id` (uuid), `email_sent_at` (timestamptz)

  3. Security
    - RLS enabled on every table.
    - `email_settings`, `email_templates`, `email_queue`, `email_log`: admin-only via admin_users lookup.
    - `notification_preferences`: each user reads/updates their own row.

  4. Seeds
    - One `email_settings` row with sensible defaults.
    - System templates: announcement_published, mention_notification, event_reminder, weekly_digest, admin_broadcast.
*/

CREATE TABLE IF NOT EXISTS email_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_name text NOT NULL DEFAULT 'Sycamore Info Hub',
  from_email text NOT NULL DEFAULT 'hub@sycamore.ng',
  reply_to text DEFAULT '',
  brand_color text DEFAULT '#0f6e42',
  default_enabled boolean DEFAULT true,
  provider text DEFAULT 'sendgrid',
  footer_html text DEFAULT '<p style="color:#64748b;font-size:12px;margin-top:24px;">You are receiving this email because you are part of the Sycamore team. <a href="{{unsubscribe_url}}">Manage your email preferences</a>.</p>',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE email_settings ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS email_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text UNIQUE NOT NULL,
  name text NOT NULL,
  description text DEFAULT '',
  subject text NOT NULL,
  html_body text NOT NULL,
  text_body text DEFAULT '',
  variables text[] DEFAULT '{}',
  is_system boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE email_templates ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS email_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  to_email text NOT NULL,
  to_name text DEFAULT '',
  subject text NOT NULL,
  html_body text NOT NULL,
  text_body text DEFAULT '',
  template_slug text,
  trigger text DEFAULT 'manual',
  payload jsonb DEFAULT '{}'::jsonb,
  reference_id jsonb DEFAULT '{}'::jsonb,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending',
  attempts int DEFAULT 0,
  last_error text DEFAULT '',
  scheduled_at timestamptz DEFAULT now(),
  sent_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE email_queue ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_email_queue_status ON email_queue(status, scheduled_at);

CREATE TABLE IF NOT EXISTS email_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_id uuid,
  to_email text NOT NULL,
  subject text NOT NULL,
  template_slug text,
  trigger text,
  status text NOT NULL,
  error text DEFAULT '',
  provider_message_id text DEFAULT '',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE email_log ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_email_log_created ON email_log(created_at DESC);

CREATE TABLE IF NOT EXISTS notification_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email_mentions boolean DEFAULT true,
  email_announcements boolean DEFAULT true,
  email_weekly_digest boolean DEFAULT true,
  email_event_reminders boolean DEFAULT true,
  email_broadcasts boolean DEFAULT true,
  unsubscribe_token text UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(24), 'hex'),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

-- Announcements additions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'announcements' AND column_name = 'email_on_publish'
  ) THEN
    ALTER TABLE announcements ADD COLUMN email_on_publish boolean DEFAULT false;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'announcements' AND column_name = 'email_audience'
  ) THEN
    ALTER TABLE announcements ADD COLUMN email_audience text DEFAULT 'all';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'announcements' AND column_name = 'email_department_id'
  ) THEN
    ALTER TABLE announcements ADD COLUMN email_department_id uuid REFERENCES departments(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'announcements' AND column_name = 'email_sent_at'
  ) THEN
    ALTER TABLE announcements ADD COLUMN email_sent_at timestamptz;
  END IF;
END $$;

-- Helper: is the caller an admin?
CREATE OR REPLACE FUNCTION is_email_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users
    WHERE admin_users.email = lower(auth.jwt() ->> 'email')
  );
$$;

-- RLS: email_settings (admins only)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_settings' AND policyname='Admins view email settings') THEN
    CREATE POLICY "Admins view email settings" ON email_settings FOR SELECT TO authenticated USING (is_email_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_settings' AND policyname='Admins insert email settings') THEN
    CREATE POLICY "Admins insert email settings" ON email_settings FOR INSERT TO authenticated WITH CHECK (is_email_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_settings' AND policyname='Admins update email settings') THEN
    CREATE POLICY "Admins update email settings" ON email_settings FOR UPDATE TO authenticated USING (is_email_admin()) WITH CHECK (is_email_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_settings' AND policyname='Admins delete email settings') THEN
    CREATE POLICY "Admins delete email settings" ON email_settings FOR DELETE TO authenticated USING (is_email_admin());
  END IF;
END $$;

-- RLS: email_templates (admins only)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_templates' AND policyname='Admins view email templates') THEN
    CREATE POLICY "Admins view email templates" ON email_templates FOR SELECT TO authenticated USING (is_email_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_templates' AND policyname='Admins insert email templates') THEN
    CREATE POLICY "Admins insert email templates" ON email_templates FOR INSERT TO authenticated WITH CHECK (is_email_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_templates' AND policyname='Admins update email templates') THEN
    CREATE POLICY "Admins update email templates" ON email_templates FOR UPDATE TO authenticated USING (is_email_admin()) WITH CHECK (is_email_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_templates' AND policyname='Admins delete email templates') THEN
    CREATE POLICY "Admins delete email templates" ON email_templates FOR DELETE TO authenticated USING (is_email_admin() AND is_system = false);
  END IF;
END $$;

-- RLS: email_queue + email_log (admins only; edge functions use service role)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_queue' AND policyname='Admins view email queue') THEN
    CREATE POLICY "Admins view email queue" ON email_queue FOR SELECT TO authenticated USING (is_email_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_queue' AND policyname='Admins insert email queue') THEN
    CREATE POLICY "Admins insert email queue" ON email_queue FOR INSERT TO authenticated WITH CHECK (is_email_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_queue' AND policyname='Admins update email queue') THEN
    CREATE POLICY "Admins update email queue" ON email_queue FOR UPDATE TO authenticated USING (is_email_admin()) WITH CHECK (is_email_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_queue' AND policyname='Admins delete email queue') THEN
    CREATE POLICY "Admins delete email queue" ON email_queue FOR DELETE TO authenticated USING (is_email_admin());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_log' AND policyname='Admins view email log') THEN
    CREATE POLICY "Admins view email log" ON email_log FOR SELECT TO authenticated USING (is_email_admin());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='email_log' AND policyname='Admins insert email log') THEN
    CREATE POLICY "Admins insert email log" ON email_log FOR INSERT TO authenticated WITH CHECK (is_email_admin());
  END IF;
END $$;

-- RLS: notification_preferences (each user manages their own)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='notification_preferences' AND policyname='Users view own preferences') THEN
    CREATE POLICY "Users view own preferences" ON notification_preferences FOR SELECT TO authenticated USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='notification_preferences' AND policyname='Users insert own preferences') THEN
    CREATE POLICY "Users insert own preferences" ON notification_preferences FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='notification_preferences' AND policyname='Users update own preferences') THEN
    CREATE POLICY "Users update own preferences" ON notification_preferences FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Seed settings row if absent
INSERT INTO email_settings (from_name, from_email)
SELECT 'Sycamore Info Hub', 'hub@sycamore.ng'
WHERE NOT EXISTS (SELECT 1 FROM email_settings);

-- Seed system templates
INSERT INTO email_templates (slug, name, description, subject, html_body, text_body, variables, is_system)
SELECT * FROM (VALUES
  (
    'announcement_published',
    'Announcement published',
    'Sent when an admin publishes an announcement and opts to email staff.',
    'New announcement: {{announcement_title}}',
    '<div style="font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;max-width:640px;margin:0 auto;padding:24px;color:#0f172a;">'
      '<div style="background:{{brand_color}};color:#ffffff;padding:20px 24px;border-radius:12px;">'
        '<div style="font-size:12px;letter-spacing:0.14em;text-transform:uppercase;opacity:0.8;">Announcement</div>'
        '<h1 style="margin:8px 0 0;font-size:22px;">{{announcement_title}}</h1>'
      '</div>'
      '<div style="padding:20px 4px;line-height:1.55;font-size:15px;">{{announcement_body}}</div>'
      '<a href="{{announcement_url}}" style="display:inline-block;background:{{brand_color}};color:#ffffff;padding:10px 18px;border-radius:999px;font-weight:600;text-decoration:none;font-size:14px;">Read on the Hub</a>'
      '{{footer_html}}'
    '</div>',
    'New announcement: {{announcement_title}}\n\n{{announcement_body_plain}}\n\nRead on the Hub: {{announcement_url}}',
    ARRAY['first_name','announcement_title','announcement_body','announcement_body_plain','announcement_url','brand_color','footer_html','unsubscribe_url'],
    true
  ),
  (
    'mention_notification',
    'You were mentioned',
    'Sent when another staff member mentions a user in a post or announcement.',
    '{{mentioner_name}} mentioned you on the Hub',
    '<div style="font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;max-width:640px;margin:0 auto;padding:24px;color:#0f172a;">'
      '<h1 style="font-size:20px;margin:0 0 12px;">{{mentioner_name}} mentioned you</h1>'
      '<blockquote style="border-left:3px solid {{brand_color}};margin:0;padding:8px 16px;color:#334155;">{{snippet}}</blockquote>'
      '<p style="margin:20px 0;"><a href="{{link_url}}" style="background:{{brand_color}};color:#ffffff;padding:10px 18px;border-radius:999px;font-weight:600;text-decoration:none;">Open in the Hub</a></p>'
      '{{footer_html}}'
    '</div>',
    '{{mentioner_name}} mentioned you on the Hub: {{snippet}}\n\n{{link_url}}',
    ARRAY['first_name','mentioner_name','snippet','link_url','brand_color','footer_html','unsubscribe_url'],
    true
  ),
  (
    'event_reminder',
    'Upcoming event reminder',
    'Reminds staff of a holiday or event coming up soon.',
    'Reminder: {{event_title}} on {{event_date}}',
    '<div style="font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;max-width:640px;margin:0 auto;padding:24px;color:#0f172a;">'
      '<h1 style="font-size:20px;margin:0 0 8px;">{{event_title}}</h1>'
      '<div style="color:#64748b;margin-bottom:16px;">{{event_date}} &middot; {{event_type}}</div>'
      '<p style="line-height:1.55;">{{event_description}}</p>'
      '{{footer_html}}'
    '</div>',
    '{{event_title}} on {{event_date}} ({{event_type}})\n\n{{event_description}}',
    ARRAY['first_name','event_title','event_date','event_type','event_description','brand_color','footer_html','unsubscribe_url'],
    true
  ),
  (
    'weekly_digest',
    'Weekly activity digest',
    'Weekly roundup of new posts, announcements and upcoming events.',
    'Your weekly Sycamore roundup',
    '<div style="font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;max-width:640px;margin:0 auto;padding:24px;color:#0f172a;">'
      '<h1 style="font-size:22px;margin:0 0 16px;">This week at Sycamore</h1>'
      '<div style="line-height:1.6;">{{digest_body}}</div>'
      '{{footer_html}}'
    '</div>',
    'This week at Sycamore\n\n{{digest_body_plain}}',
    ARRAY['first_name','digest_body','digest_body_plain','brand_color','footer_html','unsubscribe_url'],
    true
  ),
  (
    'admin_broadcast',
    'Admin broadcast',
    'Generic template admins can use to send a one-off email.',
    '{{subject}}',
    '<div style="font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;max-width:640px;margin:0 auto;padding:24px;color:#0f172a;">'
      '<h1 style="font-size:22px;margin:0 0 16px;">{{heading}}</h1>'
      '<div style="line-height:1.6;">{{body}}</div>'
      '{{footer_html}}'
    '</div>',
    '{{heading}}\n\n{{body_plain}}',
    ARRAY['first_name','subject','heading','body','body_plain','brand_color','footer_html','unsubscribe_url'],
    true
  )
) AS v(slug, name, description, subject, html_body, text_body, variables, is_system)
WHERE NOT EXISTS (SELECT 1 FROM email_templates t WHERE t.slug = v.slug);
