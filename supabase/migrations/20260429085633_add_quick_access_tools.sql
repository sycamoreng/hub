/*
  # Quick access tools on homepage

  1. New Tables
    - `quick_tools`
      - `id` (uuid, PK)
      - `name` (text)
      - `url` (text)
      - `logo_url` (text) - icon/logo for the tile
      - `allowed_departments` (text[]) - if empty/null, visible to all authenticated users; otherwise only staff in those departments (admins always see all)
      - `sort_order` (int) - display order
      - `is_active` (bool)
      - `created_at`, `updated_at`
  2. Security
    - Enable RLS on `quick_tools`
    - Authenticated users may SELECT all active rows; client filters by department membership. Admins with chatbot/communication permissions can manage.
  3. Seed
    - Sprout, Google Meet, Slack (Product/Technology only), Freshdesk (Customer Experience only), SeamlessHR
*/

CREATE TABLE IF NOT EXISTS quick_tools (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  url text NOT NULL,
  logo_url text DEFAULT '',
  allowed_departments text[] DEFAULT '{}',
  sort_order int DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE quick_tools ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='quick_tools' AND policyname='Authenticated can view active quick tools') THEN
    CREATE POLICY "Authenticated can view active quick tools"
      ON quick_tools FOR SELECT TO authenticated
      USING (is_active = true);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='quick_tools' AND policyname='Admins can insert quick tools') THEN
    CREATE POLICY "Admins can insert quick tools"
      ON quick_tools FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM admin_users
          WHERE admin_users.email = lower(auth.jwt() ->> 'email')
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='quick_tools' AND policyname='Admins can update quick tools') THEN
    CREATE POLICY "Admins can update quick tools"
      ON quick_tools FOR UPDATE TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM admin_users
          WHERE admin_users.email = lower(auth.jwt() ->> 'email')
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM admin_users
          WHERE admin_users.email = lower(auth.jwt() ->> 'email')
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='quick_tools' AND policyname='Admins can delete quick tools') THEN
    CREATE POLICY "Admins can delete quick tools"
      ON quick_tools FOR DELETE TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM admin_users
          WHERE admin_users.email = lower(auth.jwt() ->> 'email')
        )
      );
  END IF;
END $$;

INSERT INTO quick_tools (name, url, logo_url, allowed_departments, sort_order)
SELECT * FROM (VALUES
  ('Sprout', 'https://sprout.sycamore.ng', 'https://www.google.com/s2/favicons?domain=sprout.sycamore.ng&sz=128', ARRAY[]::text[], 10),
  ('Google Meet', 'https://meet.google.com/', 'https://www.google.com/s2/favicons?domain=meet.google.com&sz=128', ARRAY[]::text[], 20),
  ('Slack', 'https://sycamoreng.slack.com/', 'https://www.google.com/s2/favicons?domain=slack.com&sz=128', ARRAY['Product','Technology'], 30),
  ('Freshdesk', 'https://sycamore-ng.freshdesk.com/a/dashboard/omnichannel/default', 'https://www.google.com/s2/favicons?domain=freshdesk.com&sz=128', ARRAY['Customer Experience'], 40),
  ('SeamlessHR', 'https://sycamore.seamlesshrms.com/', 'https://www.google.com/s2/favicons?domain=seamlesshrms.com&sz=128', ARRAY[]::text[], 50)
) AS v(name, url, logo_url, allowed_departments, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM quick_tools WHERE quick_tools.name = v.name);
