/*
  # Chat DM space cache

  Adds per-viewer cache of resolved Google Chat DM space IDs so we don't
  hammer Google Chat's findDirectMessage API for every profile visit.

  1. New Tables
    - `chat_dm_space_cache`
      - `id` (uuid, primary key)
      - `viewer_user_id` (uuid, references auth.users) — the signed-in viewer
      - `target_staff_id` (uuid, references staff_members) — the person to DM
      - `space_id` (text) — Google Chat space id (without the "spaces/" prefix)
      - `resolved_at` (timestamptz) — when we looked this up
      - UNIQUE (viewer_user_id, target_staff_id)

  2. Security
    - Enable RLS
    - Viewers can only read/insert/update rows for themselves
    - No DELETE policy (server/service-role handles cleanup if ever needed)
*/

CREATE TABLE IF NOT EXISTS chat_dm_space_cache (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  viewer_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target_staff_id uuid NOT NULL REFERENCES staff_members(id) ON DELETE CASCADE,
  space_id text NOT NULL,
  resolved_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (viewer_user_id, target_staff_id)
);

CREATE INDEX IF NOT EXISTS chat_dm_space_cache_viewer_idx ON chat_dm_space_cache(viewer_user_id);

ALTER TABLE chat_dm_space_cache ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'chat_dm_space_cache' AND policyname = 'Viewer can read own dm cache'
  ) THEN
    CREATE POLICY "Viewer can read own dm cache"
      ON chat_dm_space_cache FOR SELECT
      TO authenticated
      USING (auth.uid() = viewer_user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'chat_dm_space_cache' AND policyname = 'Viewer can insert own dm cache'
  ) THEN
    CREATE POLICY "Viewer can insert own dm cache"
      ON chat_dm_space_cache FOR INSERT
      TO authenticated
      WITH CHECK (auth.uid() = viewer_user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'chat_dm_space_cache' AND policyname = 'Viewer can update own dm cache'
  ) THEN
    CREATE POLICY "Viewer can update own dm cache"
      ON chat_dm_space_cache FOR UPDATE
      TO authenticated
      USING (auth.uid() = viewer_user_id)
      WITH CHECK (auth.uid() = viewer_user_id);
  END IF;
END $$;
