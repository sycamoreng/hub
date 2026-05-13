/*
  # Typing Sprint Multiplayer Matches (retry)

  Re-applies multiplayer match tables, RPCs, realtime publication, and notification
  hooks. See accompanying create_typing_multiplayer migration for full description.
*/

CREATE TABLE IF NOT EXISTS typing_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code text UNIQUE NOT NULL,
  category_id uuid REFERENCES typing_categories(id) ON DELETE SET NULL,
  prompt_id uuid REFERENCES typing_prompts(id) ON DELETE SET NULL,
  prompt_text text NOT NULL DEFAULT '',
  mode text NOT NULL DEFAULT 'timed_60s',
  duration_ms int NOT NULL DEFAULT 60000,
  status text NOT NULL DEFAULT 'lobby',
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT typing_matches_status_chk CHECK (status IN ('lobby','running','finished','cancelled')),
  CONSTRAINT typing_matches_mode_chk CHECK (mode IN ('timed_30s','timed_60s','timed_120s','sprint'))
);

CREATE INDEX IF NOT EXISTS typing_matches_host_idx ON typing_matches(host_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS typing_matches_status_idx ON typing_matches(status, created_at DESC);

ALTER TABLE typing_matches ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_matches' AND policyname='Authenticated read matches') THEN
    CREATE POLICY "Authenticated read matches"
      ON typing_matches FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS typing_match_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES typing_matches(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'invited',
  wpm numeric(6,2) DEFAULT 0,
  accuracy numeric(5,2) DEFAULT 0,
  characters_typed int DEFAULT 0,
  words_typed int DEFAULT 0,
  errors int DEFAULT 0,
  duration_ms int DEFAULT 0,
  rank int,
  joined_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (match_id, user_id),
  CONSTRAINT typing_match_participants_status_chk CHECK (status IN ('invited','joined','finished','declined'))
);

CREATE INDEX IF NOT EXISTS typing_match_participants_match_idx ON typing_match_participants(match_id);
CREATE INDEX IF NOT EXISTS typing_match_participants_user_idx ON typing_match_participants(user_id, created_at DESC);

ALTER TABLE typing_match_participants ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_match_participants' AND policyname='Authenticated read participants') THEN
    CREATE POLICY "Authenticated read participants"
      ON typing_match_participants FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='typing_matches'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE typing_matches';
  END IF;
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='typing_match_participants'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE typing_match_participants';
  END IF;
EXCEPTION WHEN others THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION public._typing_random_code()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text := '';
  i int;
BEGIN
  FOR i IN 1..6 LOOP
    v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
  END LOOP;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.typing_match_create(
  p_category_id uuid,
  p_prompt_id uuid,
  p_mode text
)
RETURNS typing_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match typing_matches;
  v_text text;
  v_code text;
  v_attempt int := 0;
  v_duration int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_mode NOT IN ('timed_30s','timed_60s','timed_120s','sprint') THEN
    RAISE EXCEPTION 'invalid mode';
  END IF;
  v_duration := CASE p_mode
    WHEN 'timed_30s' THEN 30000
    WHEN 'timed_60s' THEN 60000
    WHEN 'timed_120s' THEN 120000
    ELSE 0
  END;

  IF p_prompt_id IS NOT NULL THEN
    SELECT text INTO v_text FROM typing_prompts WHERE id = p_prompt_id;
  END IF;
  IF v_text IS NULL THEN
    SELECT text INTO v_text FROM typing_prompts
    WHERE is_active
      AND (p_category_id IS NULL OR category_id = p_category_id)
    ORDER BY random() LIMIT 1;
  END IF;
  IF v_text IS NULL THEN
    RAISE EXCEPTION 'no prompts available';
  END IF;

  LOOP
    v_attempt := v_attempt + 1;
    v_code := public._typing_random_code();
    BEGIN
      INSERT INTO typing_matches (host_user_id, code, category_id, prompt_id, prompt_text, mode, duration_ms)
      VALUES (v_uid, v_code, p_category_id, p_prompt_id, v_text, p_mode, v_duration)
      RETURNING * INTO v_match;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt > 6 THEN RAISE; END IF;
    END;
  END LOOP;

  INSERT INTO typing_match_participants (match_id, user_id, status, joined_at)
  VALUES (v_match.id, v_uid, 'joined', now());

  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_create(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_create(uuid, uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.typing_match_invite(
  p_match_id uuid,
  p_user_ids uuid[]
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match typing_matches;
  v_count int := 0;
  v_target uuid;
  v_actor_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM typing_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can invite' USING ERRCODE='42501'; END IF;
  IF v_match.status <> 'lobby' THEN RAISE EXCEPTION 'match no longer accepting invites'; END IF;

  SELECT COALESCE(full_name, '') INTO v_actor_name FROM staff_members WHERE auth_user_id = v_uid;

  FOREACH v_target IN ARRAY p_user_ids LOOP
    IF v_target IS NULL OR v_target = v_uid THEN CONTINUE; END IF;
    INSERT INTO typing_match_participants (match_id, user_id, status)
    VALUES (p_match_id, v_target, 'invited')
    ON CONFLICT (match_id, user_id) DO NOTHING;
    v_count := v_count + 1;
    INSERT INTO notifications (recipient_id, actor_id, type, title, body, link)
    VALUES (
      v_target,
      v_uid,
      'typing_match_invite',
      'Typing Sprint challenge',
      COALESCE(NULLIF(v_actor_name, ''), 'A teammate') || ' invited you to a typing match. Code ' || v_match.code,
      '/typing?match=' || v_match.code
    );
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_invite(uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_invite(uuid, uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.typing_match_join(p_code text)
RETURNS typing_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match typing_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM typing_matches WHERE code = upper(trim(p_code));
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.status = 'finished' THEN RAISE EXCEPTION 'match already finished'; END IF;
  IF v_match.status = 'cancelled' THEN RAISE EXCEPTION 'match cancelled'; END IF;

  INSERT INTO typing_match_participants (match_id, user_id, status, joined_at)
  VALUES (v_match.id, v_uid, 'joined', now())
  ON CONFLICT (match_id, user_id) DO UPDATE
    SET status = CASE WHEN typing_match_participants.status IN ('declined','invited') THEN 'joined' ELSE typing_match_participants.status END,
        joined_at = COALESCE(typing_match_participants.joined_at, now());

  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_join(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_join(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.typing_match_decline(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  UPDATE typing_match_participants SET status = 'declined'
  WHERE match_id = p_match_id AND user_id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_decline(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_decline(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.typing_match_start(p_match_id uuid)
RETURNS typing_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match typing_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM typing_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start' USING ERRCODE='42501'; END IF;
  IF v_match.status <> 'lobby' THEN RAISE EXCEPTION 'match cannot be started'; END IF;

  UPDATE typing_matches SET status = 'running', started_at = now() WHERE id = p_match_id RETURNING * INTO v_match;
  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_start(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.typing_match_finalize(p_match_id uuid)
RETURNS typing_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_match typing_matches;
BEGIN
  SELECT * INTO v_match FROM typing_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;

  WITH ranked AS (
    SELECT id,
           ROW_NUMBER() OVER (ORDER BY wpm DESC, accuracy DESC, finished_at ASC) AS r
    FROM typing_match_participants
    WHERE match_id = p_match_id AND status = 'finished'
  )
  UPDATE typing_match_participants p
  SET rank = ranked.r
  FROM ranked
  WHERE p.id = ranked.id;

  UPDATE typing_matches
  SET status = 'finished', finished_at = COALESCE(finished_at, now())
  WHERE id = p_match_id
  RETURNING * INTO v_match;

  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_finalize(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_finalize(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.typing_match_submit(
  p_match_id uuid,
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
  v_match typing_matches;
  v_part typing_match_participants;
  v_run_points jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM typing_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.status NOT IN ('running','finished') THEN RAISE EXCEPTION 'match not running'; END IF;

  SELECT * INTO v_part FROM typing_match_participants WHERE match_id = p_match_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;
  IF v_part.status = 'finished' THEN
    RETURN jsonb_build_object('already_submitted', true);
  END IF;

  UPDATE typing_match_participants
  SET wpm = p_wpm,
      accuracy = p_accuracy,
      characters_typed = p_characters_typed,
      words_typed = p_words_typed,
      errors = p_errors,
      duration_ms = p_duration_ms,
      status = 'finished',
      finished_at = now()
  WHERE id = v_part.id;

  v_run_points := public.typing_submit_run(
    v_match.category_id,
    v_match.mode,
    p_wpm,
    p_accuracy,
    p_characters_typed,
    p_words_typed,
    p_errors,
    GREATEST(p_duration_ms, 1000)
  );

  IF NOT EXISTS (
    SELECT 1 FROM typing_match_participants
    WHERE match_id = p_match_id AND status IN ('joined','invited')
  ) THEN
    PERFORM public.typing_match_finalize(p_match_id);
  END IF;

  RETURN jsonb_build_object('submitted', true, 'run', v_run_points);
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_submit(uuid, numeric, numeric, int, int, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_submit(uuid, numeric, numeric, int, int, int, int) TO authenticated;
