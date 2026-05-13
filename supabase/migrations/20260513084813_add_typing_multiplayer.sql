/*
  # Typing Sprint Multiplayer

  1. New Tables
    - `typing_matches` — a single competitive game. Stores host, mode, category, prompt text, status (pending/active/finished/cancelled), starts_at, ends_at, code (8-char invite code), max_players.
    - `typing_match_players` — players in a match. Status (invited/accepted/declined/finished), wpm, accuracy, words/errors, finished_at, finish_rank.

  2. New Functions (SECURITY DEFINER)
    - `typing_match_create(mode, category_id, max_players, length_tier)` — creates a pending match for the caller, picks a random prompt and an 8-char code; auto-adds host as accepted player.
    - `typing_match_invite(match_id, target_user_id)` — host invites a teammate; creates a `typing_match_invite` notification linking to the match.
    - `typing_match_join(code)` — anyone with the code accepts.
    - `typing_match_decline(match_id)` — invitee declines.
    - `typing_match_start(match_id)` — host marks match active; sets starts_at = now() and ends_at based on mode duration; notifies accepted players.
    - `typing_match_submit(match_id, wpm, accuracy, characters_typed, words_typed, errors, duration_ms)` — player records their result, awards points (reuses typing_submit_run scoring rules with a 25-point match-winner bonus assigned post-finish), triggers match-finished if everyone done.
    - `typing_match_finalize(match_id)` — internally awards 25-pt winner bonus to top WPM and notifies all players.

  3. Security
    - RLS enabled. Only invited players or the host can read a match. Authenticated users can't directly write — all writes go through RPCs.
*/

-- Matches ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS typing_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category_id uuid REFERENCES typing_categories(id) ON DELETE SET NULL,
  mode text NOT NULL DEFAULT 'timed_60s',
  prompt_text text NOT NULL,
  length_tier text DEFAULT 'medium',
  status text NOT NULL DEFAULT 'pending',
  code text NOT NULL UNIQUE,
  max_players int NOT NULL DEFAULT 8,
  starts_at timestamptz,
  ends_at timestamptz,
  finalized_at timestamptz,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT typing_matches_status_chk CHECK (status IN ('pending','active','finished','cancelled')),
  CONSTRAINT typing_matches_mode_chk CHECK (mode IN ('timed_30s','timed_60s','timed_120s','sprint'))
);

CREATE INDEX IF NOT EXISTS typing_matches_host_idx ON typing_matches(host_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS typing_matches_status_idx ON typing_matches(status, created_at DESC);

ALTER TABLE typing_matches ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS typing_match_players (
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
  finished_at timestamptz,
  finish_rank int,
  joined_at timestamptz DEFAULT now(),
  CONSTRAINT typing_match_players_unique UNIQUE (match_id, user_id),
  CONSTRAINT typing_match_players_status_chk CHECK (status IN ('invited','accepted','declined','finished'))
);

CREATE INDEX IF NOT EXISTS typing_match_players_user_idx ON typing_match_players(user_id);
CREATE INDEX IF NOT EXISTS typing_match_players_match_idx ON typing_match_players(match_id);

ALTER TABLE typing_match_players ENABLE ROW LEVEL SECURITY;

-- Read policies: a user can read a match if host or invited; same for players row
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_matches' AND policyname='Players read their matches') THEN
    CREATE POLICY "Players read their matches"
      ON typing_matches FOR SELECT TO authenticated
      USING (
        host_user_id = auth.uid()
        OR EXISTS (SELECT 1 FROM typing_match_players p WHERE p.match_id = id AND p.user_id = auth.uid())
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_match_players' AND policyname='Players read own match rows') THEN
    CREATE POLICY "Players read own match rows"
      ON typing_match_players FOR SELECT TO authenticated
      USING (
        user_id = auth.uid()
        OR EXISTS (SELECT 1 FROM typing_matches m WHERE m.id = match_id AND (
          m.host_user_id = auth.uid()
          OR EXISTS (SELECT 1 FROM typing_match_players p2 WHERE p2.match_id = m.id AND p2.user_id = auth.uid())
        ))
      );
  END IF;
END $$;

-- Helper: short random code ---------------------------------------------------

CREATE OR REPLACE FUNCTION public.typing_match_gen_code()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i int;
BEGIN
  FOR i IN 1..8 LOOP
    result := result || substr(chars, 1 + floor(random() * length(chars))::int, 1);
  END LOOP;
  RETURN result;
END;
$$;

-- Create match ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.typing_match_create(
  p_mode text,
  p_category_id uuid,
  p_max_players int,
  p_length_tier text
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
  v_attempts int := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_mode NOT IN ('timed_30s','timed_60s','timed_120s','sprint') THEN RAISE EXCEPTION 'invalid mode'; END IF;

  SELECT text INTO v_text
  FROM typing_prompts
  WHERE is_active = true
    AND (p_category_id IS NULL OR category_id = p_category_id)
    AND (p_length_tier IS NULL OR p_length_tier = '' OR length_tier = p_length_tier)
  ORDER BY random()
  LIMIT 1;

  IF v_text IS NULL THEN RAISE EXCEPTION 'no prompts available for these filters'; END IF;

  -- Ensure unique code
  LOOP
    v_code := typing_match_gen_code();
    EXIT WHEN NOT EXISTS (SELECT 1 FROM typing_matches WHERE code = v_code);
    v_attempts := v_attempts + 1;
    IF v_attempts > 10 THEN RAISE EXCEPTION 'could not allocate code'; END IF;
  END LOOP;

  INSERT INTO typing_matches (host_user_id, category_id, mode, prompt_text, length_tier, code, max_players)
  VALUES (v_uid, p_category_id, p_mode, v_text, p_length_tier, v_code, GREATEST(2, LEAST(20, p_max_players)))
  RETURNING * INTO v_match;

  INSERT INTO typing_match_players (match_id, user_id, status)
  VALUES (v_match.id, v_uid, 'accepted');

  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_create(text, uuid, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_create(text, uuid, int, text) TO authenticated;

-- Invite ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.typing_match_invite(p_match_id uuid, p_target_user_id uuid)
RETURNS typing_match_players
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match typing_matches;
  v_player typing_match_players;
  v_existing typing_match_players;
  v_count int;
  v_host_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO v_match FROM typing_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can invite'; END IF;
  IF v_match.status NOT IN ('pending','active') THEN RAISE EXCEPTION 'match closed'; END IF;
  IF p_target_user_id = v_uid THEN RAISE EXCEPTION 'cannot invite yourself'; END IF;

  SELECT count(*) INTO v_count FROM typing_match_players WHERE match_id = p_match_id AND status IN ('invited','accepted');
  IF v_count >= v_match.max_players THEN RAISE EXCEPTION 'match full'; END IF;

  SELECT * INTO v_existing FROM typing_match_players WHERE match_id = p_match_id AND user_id = p_target_user_id;
  IF FOUND THEN
    RETURN v_existing;
  END IF;

  INSERT INTO typing_match_players (match_id, user_id, status)
  VALUES (p_match_id, p_target_user_id, 'invited')
  RETURNING * INTO v_player;

  SELECT full_name INTO v_host_name FROM staff_members WHERE auth_user_id = v_uid LIMIT 1;

  INSERT INTO notifications (recipient_id, actor_id, type, title, body, link)
  VALUES (
    p_target_user_id,
    v_uid,
    'typing_match_invite',
    COALESCE(v_host_name, 'A colleague') || ' invited you to a Typing Sprint match',
    'Mode: ' || v_match.mode || '. Tap to join.',
    '/typing?match=' || v_match.code
  );

  RETURN v_player;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_invite(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_invite(uuid, uuid) TO authenticated;

-- Join by code ---------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.typing_match_join(p_code text)
RETURNS typing_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match typing_matches;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO v_match FROM typing_matches WHERE code = upper(p_code);
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.status NOT IN ('pending','active') THEN RAISE EXCEPTION 'match closed'; END IF;

  SELECT count(*) INTO v_count FROM typing_match_players WHERE match_id = v_match.id AND status IN ('invited','accepted');
  IF NOT EXISTS (SELECT 1 FROM typing_match_players WHERE match_id = v_match.id AND user_id = v_uid) THEN
    IF v_count >= v_match.max_players THEN RAISE EXCEPTION 'match full'; END IF;
  END IF;

  INSERT INTO typing_match_players (match_id, user_id, status)
  VALUES (v_match.id, v_uid, 'accepted')
  ON CONFLICT (match_id, user_id) DO UPDATE
    SET status = CASE WHEN typing_match_players.status = 'declined' THEN 'accepted' ELSE 'accepted' END;

  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_join(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_join(text) TO authenticated;

-- Decline --------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.typing_match_decline(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  UPDATE typing_match_players SET status = 'declined'
  WHERE match_id = p_match_id AND user_id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_decline(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_decline(uuid) TO authenticated;

-- Start match ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.typing_match_start(p_match_id uuid)
RETURNS typing_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match typing_matches;
  v_duration_ms int;
  v_starts timestamptz := now() + interval '3 seconds';
  v_host_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO v_match FROM typing_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start'; END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'match already started'; END IF;

  v_duration_ms := CASE v_match.mode
    WHEN 'timed_30s' THEN 30000
    WHEN 'timed_60s' THEN 60000
    WHEN 'timed_120s' THEN 120000
    WHEN 'sprint' THEN 300000  -- 5 minute hard cap for sprint
    ELSE 60000
  END;

  UPDATE typing_matches
  SET status = 'active',
      starts_at = v_starts,
      ends_at = v_starts + (v_duration_ms || ' milliseconds')::interval
  WHERE id = p_match_id
  RETURNING * INTO v_match;

  SELECT full_name INTO v_host_name FROM staff_members WHERE auth_user_id = v_uid LIMIT 1;

  INSERT INTO notifications (recipient_id, actor_id, type, title, body, link)
  SELECT p.user_id, v_uid, 'typing_match_started',
         COALESCE(v_host_name, 'Host') || ' started the Typing Sprint match',
         'It begins in 3 seconds. Tap to join.',
         '/typing?match=' || v_match.code
  FROM typing_match_players p
  WHERE p.match_id = p_match_id AND p.status = 'accepted' AND p.user_id <> v_uid;

  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_start(uuid) TO authenticated;

-- Finalize: assign ranks, winner bonus, mark finished ------------------------

CREATE OR REPLACE FUNCTION public.typing_match_finalize(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_match typing_matches;
  v_winner_user_id uuid;
  v_remaining int;
BEGIN
  SELECT * INTO v_match FROM typing_matches WHERE id = p_match_id;
  IF NOT FOUND OR v_match.status = 'finished' THEN RETURN; END IF;

  -- Mark anyone still active as finished with 0 score if past ends_at
  IF v_match.ends_at IS NOT NULL AND now() > v_match.ends_at THEN
    UPDATE typing_match_players
    SET status = 'finished', finished_at = COALESCE(finished_at, now())
    WHERE match_id = p_match_id AND status = 'accepted';
  END IF;

  SELECT count(*) INTO v_remaining
  FROM typing_match_players
  WHERE match_id = p_match_id AND status = 'accepted';

  IF v_remaining > 0 THEN RETURN; END IF;

  -- Assign finish_rank based on wpm desc among finished
  WITH ranked AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY wpm DESC, accuracy DESC, finished_at ASC) AS r
    FROM typing_match_players
    WHERE match_id = p_match_id AND status = 'finished'
  )
  UPDATE typing_match_players p
  SET finish_rank = r.r
  FROM ranked r
  WHERE p.id = r.id;

  -- Winner bonus
  SELECT user_id INTO v_winner_user_id
  FROM typing_match_players
  WHERE match_id = p_match_id AND status = 'finished' AND wpm > 0
  ORDER BY wpm DESC, accuracy DESC, finished_at ASC
  LIMIT 1;

  IF v_winner_user_id IS NOT NULL THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_winner_user_id, 'typing_match_win', 'typing_match', p_match_id::text, 25, 'Won a Typing Sprint match')
    ON CONFLICT DO NOTHING;
  END IF;

  UPDATE typing_matches SET status = 'finished', finalized_at = now() WHERE id = p_match_id;

  -- Notify all players
  INSERT INTO notifications (recipient_id, actor_id, type, title, body, link)
  SELECT p.user_id, v_match.host_user_id, 'typing_match_finished',
         'Typing Sprint match finished',
         'Tap to see the standings.',
         '/typing?match=' || v_match.code
  FROM typing_match_players p
  WHERE p.match_id = p_match_id AND p.status IN ('finished','accepted');
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_finalize(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_finalize(uuid) TO authenticated;

-- Submit a player's match result ---------------------------------------------

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
  v_player typing_match_players;
  v_points int := 0;
  v_today_total int := 0;
  v_remaining int;
  v_daily_cap int := 200;
  v_unfinished int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO v_match FROM typing_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'match not active'; END IF;
  IF p_wpm < 0 OR p_wpm > 400 THEN RAISE EXCEPTION 'invalid wpm'; END IF;
  IF p_accuracy < 0 OR p_accuracy > 100 THEN RAISE EXCEPTION 'invalid accuracy'; END IF;

  UPDATE typing_match_players
  SET status = 'finished',
      wpm = p_wpm,
      accuracy = p_accuracy,
      characters_typed = p_characters_typed,
      words_typed = p_words_typed,
      errors = p_errors,
      duration_ms = p_duration_ms,
      finished_at = now()
  WHERE match_id = p_match_id AND user_id = v_uid AND status = 'accepted'
  RETURNING * INTO v_player;

  IF NOT FOUND THEN RAISE EXCEPTION 'you are not an active player in this match'; END IF;

  -- Mirror as a typing_run for personal-best tracking
  INSERT INTO typing_runs (user_id, category_id, mode, wpm, accuracy, characters_typed, words_typed, errors, duration_ms)
  VALUES (v_uid, v_match.category_id, v_match.mode, p_wpm, p_accuracy, p_characters_typed, p_words_typed, p_errors, p_duration_ms);

  -- Base scoring (same rules as solo, with daily cap)
  IF p_accuracy >= 80 THEN
    v_points := LEAST(50, GREATEST(0, FLOOR(p_wpm)::int - 20));
  END IF;

  SELECT COALESCE(SUM(points), 0) INTO v_today_total
  FROM points_events
  WHERE user_id = v_uid
    AND event_kind LIKE 'typing_%'
    AND created_at >= date_trunc('day', now());

  v_remaining := GREATEST(0, v_daily_cap - v_today_total);
  v_points := LEAST(v_points, v_remaining);

  IF v_points > 0 THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'typing_match_run', 'typing_match', p_match_id::text || ':' || v_uid::text, v_points,
            'Match · WPM ' || ROUND(p_wpm,1) || ' · ' || ROUND(p_accuracy,0) || '%')
    ON CONFLICT DO NOTHING;
  END IF;

  -- Check if everyone is done
  SELECT count(*) INTO v_unfinished
  FROM typing_match_players
  WHERE match_id = p_match_id AND status = 'accepted';

  IF v_unfinished = 0 THEN
    PERFORM typing_match_finalize(p_match_id);
  END IF;

  RETURN jsonb_build_object(
    'player', to_jsonb(v_player),
    'points_awarded', v_points,
    'match_finalized', v_unfinished = 0
  );
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_submit(uuid, numeric, numeric, int, int, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_submit(uuid, numeric, numeric, int, int, int, int) TO authenticated;
