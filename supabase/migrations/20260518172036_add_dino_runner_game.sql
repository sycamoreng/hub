/*
  # Add Dino Runner game

  1. New Tables
    - `dino_runner_scores`
      - `id` (uuid, primary key)
      - `user_id` (uuid) — references auth user
      - `score` (integer) — final distance in points
      - `duration_ms` (integer) — how long the run lasted
      - `created_at` (timestamptz)
  2. Security
    - RLS enabled. Authenticated users can insert their own runs and read all
      runs (used to render the leaderboard). No update or delete policy.
  3. Notes
    1. Personal best is computed client-side via max(score) per user.
    2. The leaderboard view returns the top score per user.
*/

CREATE TABLE IF NOT EXISTS dino_runner_scores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  score integer NOT NULL DEFAULT 0,
  duration_ms integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS dino_runner_scores_user_id_idx ON dino_runner_scores(user_id);
CREATE INDEX IF NOT EXISTS dino_runner_scores_score_idx ON dino_runner_scores(score DESC);

ALTER TABLE dino_runner_scores ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'dino_runner_scores'
      AND policyname = 'Authenticated can read all dino runs'
  ) THEN
    CREATE POLICY "Authenticated can read all dino runs"
      ON dino_runner_scores
      FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'dino_runner_scores'
      AND policyname = 'Users insert own dino run'
  ) THEN
    CREATE POLICY "Users insert own dino run"
      ON dino_runner_scores
      FOR INSERT
      TO authenticated
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;