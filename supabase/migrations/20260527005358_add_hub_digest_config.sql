/*
  # Add Hub Digest Configuration

  1. New Tables
    - `digest_config`
      - `id` (uuid, primary key)
      - `frequency` (text) - 'weekly' or 'monthly'
      - `day_of_week` (int) - 0=Sunday..6=Saturday (for weekly)
      - `day_of_month` (int) - 1-28 (for monthly)
      - `send_hour_utc` (int) - 0-23, hour to send
      - `is_active` (bool) - whether digest is enabled
      - `sections` (jsonb) - array of enabled section configs
      - `custom_intro` (text) - optional custom intro text
      - `last_sent_at` (timestamptz) - when last digest was sent
      - `created_at`, `updated_at`

    - `digest_history`
      - `id` (uuid, primary key)
      - `digest_type` (text) - 'weekly' or 'monthly'
      - `period_start` (date) - start of reporting period
      - `period_end` (date) - end of reporting period
      - `stats` (jsonb) - snapshot of compiled stats
      - `recipients_count` (int) - how many emails were queued
      - `sent_at` (timestamptz)

  2. Security
    - Enable RLS on both tables
    - Admin-only access policies

  3. Notes
    - Default sections include: announcements, feed_highlights, birthdays,
      anniversaries, leaderboard, new_joiners, kudos, badges, events, playlist
    - The sections field is a JSONB array where each entry has:
      { "key": "announcements", "label": "Announcements", "enabled": true, "max_items": 5 }
*/

-- Digest configuration (singleton-ish, one per frequency)
CREATE TABLE IF NOT EXISTS digest_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  frequency text NOT NULL DEFAULT 'weekly' CHECK (frequency IN ('weekly', 'monthly')),
  day_of_week int DEFAULT 1 CHECK (day_of_week >= 0 AND day_of_week <= 6),
  day_of_month int DEFAULT 1 CHECK (day_of_month >= 1 AND day_of_month <= 28),
  send_hour_utc int DEFAULT 7 CHECK (send_hour_utc >= 0 AND send_hour_utc <= 23),
  is_active bool DEFAULT true,
  sections jsonb DEFAULT '[
    {"key": "announcements", "label": "Announcements", "enabled": true, "max_items": 5},
    {"key": "feed_highlights", "label": "Feed Highlights", "enabled": true, "max_items": 5},
    {"key": "birthdays", "label": "Birthdays This Period", "enabled": true, "max_items": 10},
    {"key": "anniversaries", "label": "Work Anniversaries", "enabled": true, "max_items": 10},
    {"key": "upcoming_birthdays", "label": "Upcoming Birthdays", "enabled": true, "max_items": 5},
    {"key": "upcoming_anniversaries", "label": "Upcoming Anniversaries", "enabled": true, "max_items": 5},
    {"key": "leaderboard", "label": "Leaderboard Top Performers", "enabled": true, "max_items": 5},
    {"key": "new_joiners", "label": "New Joiners", "enabled": true, "max_items": 10},
    {"key": "kudos", "label": "Kudos & Recognition", "enabled": true, "max_items": 5},
    {"key": "badges", "label": "Badges Earned", "enabled": true, "max_items": 5},
    {"key": "events", "label": "Upcoming Events", "enabled": true, "max_items": 5},
    {"key": "playlist", "label": "Playlist of the Week", "enabled": true, "max_items": 3},
    {"key": "exits", "label": "Departures", "enabled": false, "max_items": 5}
  ]'::jsonb,
  custom_intro text DEFAULT '',
  last_sent_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (frequency)
);

ALTER TABLE digest_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view digest config"
  ON digest_config FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE lower(email) = lower(auth.jwt()->>'email')
    )
  );

CREATE POLICY "Admins can insert digest config"
  ON digest_config FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE lower(email) = lower(auth.jwt()->>'email')
    )
  );

CREATE POLICY "Admins can update digest config"
  ON digest_config FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE lower(email) = lower(auth.jwt()->>'email')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE lower(email) = lower(auth.jwt()->>'email')
    )
  );

-- Digest history (audit trail)
CREATE TABLE IF NOT EXISTS digest_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  digest_type text NOT NULL DEFAULT 'weekly',
  period_start date NOT NULL,
  period_end date NOT NULL,
  stats jsonb DEFAULT '{}'::jsonb,
  recipients_count int DEFAULT 0,
  sent_at timestamptz DEFAULT now()
);

ALTER TABLE digest_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view digest history"
  ON digest_history FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE lower(email) = lower(auth.jwt()->>'email')
    )
  );

CREATE POLICY "Admins can insert digest history"
  ON digest_history FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE lower(email) = lower(auth.jwt()->>'email')
    )
  );

-- Seed default weekly config
INSERT INTO digest_config (frequency, day_of_week, send_hour_utc, is_active)
VALUES ('weekly', 1, 7, true)
ON CONFLICT (frequency) DO NOTHING;

-- Seed default monthly config
INSERT INTO digest_config (frequency, day_of_month, send_hour_utc, is_active)
VALUES ('monthly', 1, 7, false)
ON CONFLICT (frequency) DO NOTHING;
