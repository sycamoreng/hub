/*
  # Google Chat spaces broadcast for announcements

  Adds the ability to post an announcement to one or more Google Chat
  spaces via incoming webhook URLs managed by admins.

  1. New tables
    - `google_chat_spaces`
      - `id` uuid primary key
      - `name` text (display label)
      - `webhook_url` text (Google Chat incoming webhook)
      - `is_active` boolean
      - `created_at`, `updated_at`

  2. Schema changes
    - `announcements`: add `post_to_chat_space_ids uuid[]` default '{}'
    - `announcements`: add `chat_sent_at timestamptz`

  3. Security
    - RLS enabled on `google_chat_spaces`.
    - Read/Write restricted to admins with `communication` section access.
*/

CREATE TABLE IF NOT EXISTS google_chat_spaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL DEFAULT '',
  webhook_url text NOT NULL DEFAULT '',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE google_chat_spaces ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read google chat spaces" ON google_chat_spaces;
CREATE POLICY "Admins read google chat spaces"
  ON google_chat_spaces FOR SELECT
  TO authenticated
  USING (private.admin_can('communication','read') OR private.admin_can('announcements','read'));

DROP POLICY IF EXISTS "Admins insert google chat spaces" ON google_chat_spaces;
CREATE POLICY "Admins insert google chat spaces"
  ON google_chat_spaces FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('communication','create'));

DROP POLICY IF EXISTS "Admins update google chat spaces" ON google_chat_spaces;
CREATE POLICY "Admins update google chat spaces"
  ON google_chat_spaces FOR UPDATE
  TO authenticated
  USING (private.admin_can('communication','update'))
  WITH CHECK (private.admin_can('communication','update'));

DROP POLICY IF EXISTS "Admins delete google chat spaces" ON google_chat_spaces;
CREATE POLICY "Admins delete google chat spaces"
  ON google_chat_spaces FOR DELETE
  TO authenticated
  USING (private.admin_can('communication','delete'));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='announcements' AND column_name='post_to_chat_space_ids'
  ) THEN
    ALTER TABLE announcements ADD COLUMN post_to_chat_space_ids uuid[] NOT NULL DEFAULT '{}';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='announcements' AND column_name='chat_sent_at'
  ) THEN
    ALTER TABLE announcements ADD COLUMN chat_sent_at timestamptz;
  END IF;
END $$;
