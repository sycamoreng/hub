/*
  # Add Learning Paths and Quiz System (Phase 1)

  1. New Tables
    - `learning_paths`
      - `id` (uuid, primary key)
      - `name` (text) - path title (e.g. "Onboarding", "Compliance Training")
      - `description` (text) - short description
      - `is_sequential` (bool) - if true, steps must be completed in display_order
      - `badge_id` (uuid, nullable FK to badges) - badge awarded on full path completion
      - `sort_order` (int) - display order of paths
      - `is_active` (bool) - visibility
      - `created_at` (timestamptz)

    - `step_quiz_questions`
      - `id` (uuid, primary key)
      - `step_id` (uuid, FK to onboarding_steps) - which lesson this quiz belongs to
      - `question` (text) - the question text
      - `options` (jsonb) - array of option strings
      - `correct_index` (int) - index of the correct option (0-based)
      - `sort_order` (int) - question display order
      - `created_at` (timestamptz)

    - `step_quiz_attempts`
      - `id` (uuid, primary key)
      - `step_id` (uuid, FK to onboarding_steps)
      - `user_id` (uuid, FK to auth.users)
      - `answers` (jsonb) - array of selected indices
      - `score` (int) - number of correct answers
      - `total` (int) - total number of questions
      - `passed` (bool) - whether the attempt met the threshold
      - `created_at` (timestamptz)

  2. Modified Tables
    - `onboarding_steps`
      - Add `path_id` (uuid, nullable FK to learning_paths)
      - Add `quiz_pass_threshold` (int, default 80) - percentage required to pass quiz

  3. Security
    - RLS enabled on all new tables
    - Authenticated users can read paths and quiz questions
    - Users can submit and view their own quiz attempts
    - Admins manage paths and quiz questions

  4. Notes
    - When is_sequential=true on a path, the UI enforces order based on display_order
    - When is_sequential=false, all steps are available immediately (current behavior)
    - Quiz pass threshold is per-step (allows different difficulty per lesson)
    - A step with 0 quiz questions has no quiz requirement
*/

-- Learning Paths
CREATE TABLE IF NOT EXISTS learning_paths (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text DEFAULT '',
  is_sequential bool DEFAULT false,
  badge_id uuid REFERENCES badges(id) ON DELETE SET NULL,
  sort_order int DEFAULT 0,
  is_active bool DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE learning_paths ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view active paths"
  ON learning_paths FOR SELECT
  TO authenticated
  USING (is_active = true);

CREATE POLICY "Admins can insert paths"
  ON learning_paths FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('onboarding', 'create'));

CREATE POLICY "Admins can update paths"
  ON learning_paths FOR UPDATE
  TO authenticated
  USING (private.admin_can('onboarding', 'update'))
  WITH CHECK (private.admin_can('onboarding', 'update'));

CREATE POLICY "Admins can delete paths"
  ON learning_paths FOR DELETE
  TO authenticated
  USING (private.admin_can('onboarding', 'delete'));

-- Add path_id and quiz_pass_threshold to onboarding_steps
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'onboarding_steps' AND column_name = 'path_id'
  ) THEN
    ALTER TABLE onboarding_steps ADD COLUMN path_id uuid REFERENCES learning_paths(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'onboarding_steps' AND column_name = 'quiz_pass_threshold'
  ) THEN
    ALTER TABLE onboarding_steps ADD COLUMN quiz_pass_threshold int DEFAULT 80;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_onboarding_steps_path ON onboarding_steps(path_id, display_order);

-- Step Quiz Questions
CREATE TABLE IF NOT EXISTS step_quiz_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id uuid NOT NULL REFERENCES onboarding_steps(id) ON DELETE CASCADE,
  question text NOT NULL,
  options jsonb NOT NULL DEFAULT '[]',
  correct_index int NOT NULL DEFAULT 0,
  sort_order int DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE step_quiz_questions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view quiz questions"
  ON step_quiz_questions FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins can insert quiz questions"
  ON step_quiz_questions FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('onboarding', 'create'));

CREATE POLICY "Admins can update quiz questions"
  ON step_quiz_questions FOR UPDATE
  TO authenticated
  USING (private.admin_can('onboarding', 'update'))
  WITH CHECK (private.admin_can('onboarding', 'update'));

CREATE POLICY "Admins can delete quiz questions"
  ON step_quiz_questions FOR DELETE
  TO authenticated
  USING (private.admin_can('onboarding', 'delete'));

CREATE INDEX IF NOT EXISTS idx_step_quiz_questions_step ON step_quiz_questions(step_id, sort_order);

-- Step Quiz Attempts
CREATE TABLE IF NOT EXISTS step_quiz_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id uuid NOT NULL REFERENCES onboarding_steps(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  answers jsonb NOT NULL DEFAULT '[]',
  score int NOT NULL DEFAULT 0,
  total int NOT NULL DEFAULT 0,
  passed bool DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE step_quiz_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own quiz attempts"
  ON step_quiz_attempts FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can submit quiz attempts"
  ON step_quiz_attempts FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_step_quiz_attempts_user_step ON step_quiz_attempts(user_id, step_id);

-- Seed "Certified Sytizen" badge
INSERT INTO badges (code, name, description, emoji, color, metric, threshold, sort_order)
VALUES ('certified_sytizen', 'Certified Sytizen', 'Completed the full onboarding learning path', '🎓', '#16a34a', 'onboarding_path_complete', 1, 20)
ON CONFLICT DO NOTHING;
