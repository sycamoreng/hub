/*
  # Typing Speed Game

  1. New Tables
    - `typing_categories` — buckets the prompts (e.g. Quotes, Tech terms, Customer service phrases). Admin editable; everyone reads.
    - `typing_prompts` — pool of phrases to type, grouped by category and length tier (short/medium/long). Admin editable; everyone reads.
    - `typing_runs` — per-user run history: mode (timed_30s/timed_60s/sprint), category, wpm, accuracy, characters typed, words typed, errors, duration_ms, finished_at. Used for leaderboards and personal bests.

  2. New Functions
    - `typing_submit_run(...)` — security definer RPC that inserts a run and awards points to `points_events`:
       * 1 point per WPM above 20, capped at 50 per run
       * Bonus 25 points for new personal best in that mode
       * Daily cap of 200 typing points to prevent abuse
       Returns the inserted run plus `points_awarded` and `is_personal_best`.

  3. Security
    - All tables RLS enabled. Authenticated users read prompts and runs (for leaderboards). Users insert their own runs only. Admins manage categories and prompts.
*/

CREATE TABLE IF NOT EXISTS typing_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text UNIQUE NOT NULL,
  name text NOT NULL,
  description text DEFAULT '',
  sort_order int DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE typing_categories ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_categories' AND policyname='Authenticated read categories') THEN
    CREATE POLICY "Authenticated read categories"
      ON typing_categories FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_categories' AND policyname='Admins insert categories') THEN
    CREATE POLICY "Admins insert categories"
      ON typing_categories FOR INSERT TO authenticated
      WITH CHECK (private.admin_can('gamification','create'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_categories' AND policyname='Admins update categories') THEN
    CREATE POLICY "Admins update categories"
      ON typing_categories FOR UPDATE TO authenticated
      USING (private.admin_can('gamification','update'))
      WITH CHECK (private.admin_can('gamification','update'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_categories' AND policyname='Admins delete categories') THEN
    CREATE POLICY "Admins delete categories"
      ON typing_categories FOR DELETE TO authenticated
      USING (private.admin_can('gamification','delete'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS typing_prompts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid REFERENCES typing_categories(id) ON DELETE CASCADE,
  text text NOT NULL,
  length_tier text NOT NULL DEFAULT 'medium',
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT typing_prompts_tier_chk CHECK (length_tier IN ('short','medium','long'))
);

CREATE INDEX IF NOT EXISTS typing_prompts_category_idx ON typing_prompts(category_id) WHERE is_active;

ALTER TABLE typing_prompts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_prompts' AND policyname='Authenticated read prompts') THEN
    CREATE POLICY "Authenticated read prompts"
      ON typing_prompts FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_prompts' AND policyname='Admins insert prompts') THEN
    CREATE POLICY "Admins insert prompts"
      ON typing_prompts FOR INSERT TO authenticated
      WITH CHECK (private.admin_can('gamification','create'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_prompts' AND policyname='Admins update prompts') THEN
    CREATE POLICY "Admins update prompts"
      ON typing_prompts FOR UPDATE TO authenticated
      USING (private.admin_can('gamification','update'))
      WITH CHECK (private.admin_can('gamification','update'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_prompts' AND policyname='Admins delete prompts') THEN
    CREATE POLICY "Admins delete prompts"
      ON typing_prompts FOR DELETE TO authenticated
      USING (private.admin_can('gamification','delete'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS typing_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category_id uuid REFERENCES typing_categories(id) ON DELETE SET NULL,
  mode text NOT NULL DEFAULT 'timed_60s',
  wpm numeric(6,2) NOT NULL DEFAULT 0,
  accuracy numeric(5,2) NOT NULL DEFAULT 0,
  characters_typed int NOT NULL DEFAULT 0,
  words_typed int NOT NULL DEFAULT 0,
  errors int NOT NULL DEFAULT 0,
  duration_ms int NOT NULL DEFAULT 0,
  finished_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  CONSTRAINT typing_runs_mode_chk CHECK (mode IN ('timed_30s','timed_60s','timed_120s','sprint'))
);

CREATE INDEX IF NOT EXISTS typing_runs_user_idx ON typing_runs(user_id, finished_at DESC);
CREATE INDEX IF NOT EXISTS typing_runs_mode_idx ON typing_runs(mode, wpm DESC);
CREATE INDEX IF NOT EXISTS typing_runs_category_idx ON typing_runs(category_id, wpm DESC);

ALTER TABLE typing_runs ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_runs' AND policyname='Authenticated read runs') THEN
    CREATE POLICY "Authenticated read runs"
      ON typing_runs FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_runs' AND policyname='Users insert own runs') THEN
    CREATE POLICY "Users insert own runs"
      ON typing_runs FOR INSERT TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_runs' AND policyname='Admins delete runs') THEN
    CREATE POLICY "Admins delete runs"
      ON typing_runs FOR DELETE TO authenticated
      USING (private.admin_can('gamification','manage'));
  END IF;
END $$;

-- Seed default categories
INSERT INTO typing_categories (slug, name, description, sort_order)
VALUES
  ('general', 'General', 'A mixed bag of phrases.', 0),
  ('quotes', 'Quotes', 'Famous and inspiring quotes.', 1),
  ('customer_service', 'Customer service', 'Polite phrases for client communication.', 2),
  ('tech', 'Tech & terms', 'Tech vocabulary and acronyms.', 3),
  ('company', 'Company values', 'Internal slogans and values.', 4)
ON CONFLICT (slug) DO NOTHING;

-- Seed sample prompts
WITH cat AS (
  SELECT id, slug FROM typing_categories
)
INSERT INTO typing_prompts (category_id, text, length_tier)
SELECT c.id, p.text, p.tier FROM cat c
JOIN (VALUES
  ('general', 'The quick brown fox jumps over the lazy dog.', 'short'),
  ('general', 'Practice makes perfect when you keep showing up every day.', 'medium'),
  ('general', 'A small daily improvement compounds into remarkable results over a long enough period of time.', 'long'),
  ('quotes', 'Stay hungry, stay foolish.', 'short'),
  ('quotes', 'The only way to do great work is to love what you do.', 'medium'),
  ('quotes', 'In the middle of every difficulty lies opportunity, but you must look closely to recognise it before it slips away.', 'long'),
  ('customer_service', 'Thank you for your patience while we look into this.', 'short'),
  ('customer_service', 'I completely understand how frustrating that must be and I will help you sort it out.', 'medium'),
  ('customer_service', 'We sincerely apologise for the inconvenience caused and want to assure you that our team is working hard to resolve this matter as quickly as possible.', 'long'),
  ('tech', 'Refactor the database schema before merging the pull request.', 'short'),
  ('tech', 'A robust system handles failure gracefully and recovers without manual intervention.', 'medium'),
  ('tech', 'Continuous integration combined with automated testing significantly reduces the time it takes to identify and resolve regressions in production.', 'long'),
  ('company', 'We win as a team and grow through ownership.', 'short'),
  ('company', 'Excellence is a habit we choose every single day, in every interaction we have.', 'medium')
) AS p(slug, text, tier) ON p.slug = c.slug
ON CONFLICT DO NOTHING;

-- Submit a run RPC ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.typing_submit_run(
  p_category_id uuid,
  p_mode text,
  p_wpm numeric,
  p_accuracy numeric,
  p_characters_typed int,
  p_words_typed int,
  p_errors int,
  p_duration_ms int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_run typing_runs;
  v_prev_best numeric;
  v_is_pb boolean := false;
  v_points int := 0;
  v_today_total int := 0;
  v_remaining int;
  v_daily_cap int := 200;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_mode NOT IN ('timed_30s','timed_60s','timed_120s','sprint') THEN
    RAISE EXCEPTION 'invalid mode';
  END IF;
  IF p_wpm < 0 OR p_wpm > 400 THEN RAISE EXCEPTION 'invalid wpm'; END IF;
  IF p_accuracy < 0 OR p_accuracy > 100 THEN RAISE EXCEPTION 'invalid accuracy'; END IF;
  IF p_duration_ms < 1000 THEN RAISE EXCEPTION 'duration too short'; END IF;

  INSERT INTO typing_runs (user_id, category_id, mode, wpm, accuracy, characters_typed, words_typed, errors, duration_ms)
  VALUES (v_uid, p_category_id, p_mode, p_wpm, p_accuracy, p_characters_typed, p_words_typed, p_errors, p_duration_ms)
  RETURNING * INTO v_run;

  SELECT COALESCE(MAX(wpm), 0) INTO v_prev_best
  FROM typing_runs
  WHERE user_id = v_uid AND mode = p_mode AND id <> v_run.id;

  v_is_pb := p_wpm > v_prev_best;

  -- Base scoring: only meaningful if accuracy is reasonable
  IF p_accuracy >= 80 THEN
    v_points := LEAST(50, GREATEST(0, FLOOR(p_wpm)::int - 20));
  END IF;
  IF v_is_pb AND p_wpm >= 30 THEN
    v_points := v_points + 25;
  END IF;

  -- Daily cap
  SELECT COALESCE(SUM(points), 0) INTO v_today_total
  FROM points_events
  WHERE user_id = v_uid
    AND event_kind LIKE 'typing_%'
    AND created_at >= date_trunc('day', now());

  v_remaining := GREATEST(0, v_daily_cap - v_today_total);
  v_points := LEAST(v_points, v_remaining);

  IF v_points > 0 THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (
      v_uid,
      CASE WHEN v_is_pb THEN 'typing_pb' ELSE 'typing_run' END,
      'typing_run',
      v_run.id::text,
      v_points,
      'WPM ' || ROUND(p_wpm,1) || ' · accuracy ' || ROUND(p_accuracy,0) || '%' || CASE WHEN v_is_pb THEN ' · PB' ELSE '' END
    );
  END IF;

  RETURN jsonb_build_object(
    'run', to_jsonb(v_run),
    'points_awarded', v_points,
    'is_personal_best', v_is_pb,
    'previous_best', v_prev_best,
    'daily_remaining', GREATEST(0, v_remaining - v_points)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.typing_submit_run(uuid, text, numeric, numeric, int, int, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_submit_run(uuid, text, numeric, numeric, int, int, int, int) TO authenticated;
