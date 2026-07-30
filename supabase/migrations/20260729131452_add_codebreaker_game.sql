/*
# Add Code Breaker (Mastermind) game with multiplayer

1. New Tables
   - `codebreaker_games` — solo daily games + scores
     - `id` (uuid, PK)
     - `user_id` (uuid, FK auth.users)
     - `puzzle_date` (date) — daily puzzle date
     - `secret_code` (text[]) — array of 4 colors
     - `guesses` (jsonb) — array of guess arrays
     - `feedback` (jsonb) — array of feedback arrays (black/white pegs)
     - `completed` (boolean)
     - `won` (boolean)
     - `guess_count` (int)
     - `created_at` (timestamptz)
   - `codebreaker_matches` — multiplayer rooms
     - Standard room fields (id, host_user_id, code, status, max_players=30, time_limit, deadline_at, etc.)
     - `secret_code` (text[]) — the 4-color code to crack
     - `max_guesses` (int, default 10)
     - `winner_user_id` (uuid, nullable)
   - `codebreaker_match_participants` — players in each room
     - Standard participant fields
     - `guesses` (jsonb) — player's guess history
     - `feedback` (jsonb) — feedback per guess
     - `completed`, `won`, `guess_count`, `points_awarded`

2. New Functions (SECURITY DEFINER)
   - `codebreaker_daily_start()` — start/resume today's daily puzzle
   - `codebreaker_daily_guess(p_guess text[])` — submit a guess to today's puzzle
   - `codebreaker_match_create(p_time_limit int)` — create multiplayer room
   - `codebreaker_match_join(p_code text)` — join room
   - `codebreaker_match_leave(p_match_id uuid)` — leave room
   - `codebreaker_match_start(p_match_id uuid)` — start game
   - `codebreaker_match_guess(p_match_id uuid, p_guess text[])` — submit guess
   - `codebreaker_match_board(p_match_id uuid)` — get room state

3. Game Rules
   - Secret is 4 colors from: red, blue, green, yellow, purple, orange (duplicates allowed)
   - Feedback: 'black' = right color right position, 'white' = right color wrong position
   - 10 guesses max per game
   - Points: First solver = 15 - (guess_count - 1) * 2 (min 5), others who solve = 3

4. Security
   - RLS enabled, SELECT to authenticated.
   - All writes via SECURITY DEFINER RPCs.
*/

-- === codebreaker_games (daily solo) ===
CREATE TABLE IF NOT EXISTS codebreaker_games (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  puzzle_date date NOT NULL DEFAULT current_date,
  secret_code text[] NOT NULL,
  guesses jsonb NOT NULL DEFAULT '[]'::jsonb,
  feedback jsonb NOT NULL DEFAULT '[]'::jsonb,
  completed boolean NOT NULL DEFAULT false,
  won boolean NOT NULL DEFAULT false,
  guess_count int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, puzzle_date)
);

ALTER TABLE codebreaker_games ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "select_own_codebreaker_games" ON codebreaker_games;
CREATE POLICY "select_own_codebreaker_games" ON codebreaker_games FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- === codebreaker_matches ===
CREATE TABLE IF NOT EXISTS codebreaker_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code text NOT NULL UNIQUE,
  secret_code text[] NOT NULL,
  max_guesses int NOT NULL DEFAULT 10,
  max_players int NOT NULL DEFAULT 30,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','finished','cancelled')),
  winner_user_id uuid REFERENCES auth.users(id),
  time_limit_seconds int,
  deadline_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE codebreaker_matches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "select_codebreaker_matches" ON codebreaker_matches;
CREATE POLICY "select_codebreaker_matches" ON codebreaker_matches FOR SELECT TO authenticated USING (true);

-- === codebreaker_match_participants ===
CREATE TABLE IF NOT EXISTS codebreaker_match_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES codebreaker_matches(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'joined' CHECK (status IN ('joined','finished','left')),
  guesses jsonb NOT NULL DEFAULT '[]'::jsonb,
  feedback jsonb NOT NULL DEFAULT '[]'::jsonb,
  completed boolean NOT NULL DEFAULT false,
  won boolean NOT NULL DEFAULT false,
  guess_count int NOT NULL DEFAULT 0,
  points_awarded int NOT NULL DEFAULT 0,
  joined_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE(match_id, user_id)
);

ALTER TABLE codebreaker_match_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "select_codebreaker_match_participants" ON codebreaker_match_participants;
CREATE POLICY "select_codebreaker_match_participants" ON codebreaker_match_participants FOR SELECT TO authenticated USING (true);

-- Helper: compute feedback for a guess against secret
CREATE OR REPLACE FUNCTION private.codebreaker_feedback(p_secret text[], p_guess text[])
RETURNS text[]
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  fb text[] := ARRAY[]::text[];
  used_secret boolean[] := ARRAY[false,false,false,false];
  used_guess boolean[] := ARRAY[false,false,false,false];
  blacks int := 0;
  whites int := 0;
BEGIN
  -- Black pegs (exact match)
  FOR i IN 1..4 LOOP
    IF p_guess[i] = p_secret[i] THEN
      blacks := blacks + 1;
      used_secret[i] := true;
      used_guess[i] := true;
    END IF;
  END LOOP;
  -- White pegs (right color wrong position)
  FOR i IN 1..4 LOOP
    IF NOT used_guess[i] THEN
      FOR j IN 1..4 LOOP
        IF NOT used_secret[j] AND p_guess[i] = p_secret[j] THEN
          whites := whites + 1;
          used_secret[j] := true;
          EXIT;
        END IF;
      END LOOP;
    END IF;
  END LOOP;
  FOR i IN 1..blacks LOOP fb := fb || 'black'; END LOOP;
  FOR i IN 1..whites LOOP fb := fb || 'white'; END LOOP;
  RETURN fb;
END;
$$;

-- Generate a random code
CREATE OR REPLACE FUNCTION private.codebreaker_random_code()
RETURNS text[]
LANGUAGE plpgsql
AS $$
DECLARE
  colors text[] := ARRAY['red','blue','green','yellow','purple','orange'];
  code text[] := ARRAY[]::text[];
BEGIN
  FOR i IN 1..4 LOOP
    code := code || colors[floor(random() * 6)::int + 1];
  END LOOP;
  RETURN code;
END;
$$;

-- === RPC: daily start ===
CREATE OR REPLACE FUNCTION codebreaker_daily_start()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_game codebreaker_games;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_game FROM codebreaker_games WHERE user_id = v_uid AND puzzle_date = current_date;
  IF NOT FOUND THEN
    INSERT INTO codebreaker_games (user_id, puzzle_date, secret_code)
    VALUES (v_uid, current_date, private.codebreaker_random_code())
    RETURNING * INTO v_game;
  END IF;
  RETURN jsonb_build_object(
    'id', v_game.id,
    'puzzle_date', v_game.puzzle_date,
    'guesses', v_game.guesses,
    'feedback', v_game.feedback,
    'completed', v_game.completed,
    'won', v_game.won,
    'guess_count', v_game.guess_count,
    'secret_code', CASE WHEN v_game.completed THEN to_jsonb(v_game.secret_code) ELSE NULL END
  );
END;
$$;

-- === RPC: daily guess ===
CREATE OR REPLACE FUNCTION codebreaker_daily_guess(p_guess text[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_game codebreaker_games;
  v_fb text[];
  v_correct boolean;
  v_colors text[] := ARRAY['red','blue','green','yellow','purple','orange'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF array_length(p_guess, 1) <> 4 THEN RAISE EXCEPTION 'guess must be 4 colors'; END IF;
  FOR i IN 1..4 LOOP
    IF NOT (p_guess[i] = ANY(v_colors)) THEN RAISE EXCEPTION 'invalid color: %', p_guess[i]; END IF;
  END LOOP;

  SELECT * INTO v_game FROM codebreaker_games WHERE user_id = v_uid AND puzzle_date = current_date FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'start a game first'; END IF;
  IF v_game.completed THEN RAISE EXCEPTION 'game already completed'; END IF;
  IF v_game.guess_count >= 10 THEN RAISE EXCEPTION 'no guesses left'; END IF;

  v_fb := private.codebreaker_feedback(v_game.secret_code, p_guess);
  v_correct := p_guess = v_game.secret_code;

  UPDATE codebreaker_games SET
    guesses = guesses || jsonb_build_array(to_jsonb(p_guess)),
    feedback = feedback || jsonb_build_array(to_jsonb(v_fb)),
    guess_count = guess_count + 1,
    completed = v_correct OR guess_count + 1 >= 10,
    won = v_correct
  WHERE id = v_game.id RETURNING * INTO v_game;

  IF v_game.won THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'codebreaker_daily', 'codebreaker_game', v_game.id::text,
      GREATEST(3, 12 - (v_game.guess_count - 1) * 2), 'Cracked the daily code')
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'id', v_game.id,
    'guesses', v_game.guesses,
    'feedback', v_game.feedback,
    'completed', v_game.completed,
    'won', v_game.won,
    'guess_count', v_game.guess_count,
    'secret_code', CASE WHEN v_game.completed THEN to_jsonb(v_game.secret_code) ELSE NULL END
  );
END;
$$;

-- === Multiplayer RPCs ===
CREATE OR REPLACE FUNCTION codebreaker_match_create(p_time_limit int DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_code text;
  v_match codebreaker_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_time_limit IS NOT NULL AND p_time_limit NOT IN (60, 90, 120, 180, 300) THEN p_time_limit := 120; END IF;
  LOOP
    v_code := upper(substr(md5(random()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM codebreaker_matches WHERE code = v_code);
  END LOOP;
  INSERT INTO codebreaker_matches (host_user_id, code, secret_code, time_limit_seconds)
  VALUES (v_uid, v_code, private.codebreaker_random_code(), p_time_limit)
  RETURNING * INTO v_match;
  RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status, 'time_limit_seconds', v_match.time_limit_seconds);
END;
$$;

CREATE OR REPLACE FUNCTION codebreaker_match_join(p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match codebreaker_matches;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM codebreaker_matches WHERE code = upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF EXISTS (SELECT 1 FROM codebreaker_match_participants WHERE match_id = v_match.id AND user_id = v_uid) THEN
    UPDATE codebreaker_match_participants SET status = 'joined' WHERE match_id = v_match.id AND user_id = v_uid AND status = 'left';
    RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status);
  END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'room already started'; END IF;
  SELECT count(*) INTO v_count FROM codebreaker_match_participants WHERE match_id = v_match.id AND status <> 'left';
  IF v_count >= v_match.max_players THEN RAISE EXCEPTION 'room is full'; END IF;
  INSERT INTO codebreaker_match_participants (match_id, user_id) VALUES (v_match.id, v_uid);
  RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status);
END;
$$;

CREATE OR REPLACE FUNCTION codebreaker_match_leave(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_match codebreaker_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM codebreaker_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_match.status = 'pending' THEN
    UPDATE codebreaker_match_participants SET status = 'left' WHERE match_id = p_match_id AND user_id = v_uid;
    IF v_match.host_user_id = v_uid AND NOT EXISTS (SELECT 1 FROM codebreaker_match_participants WHERE match_id = p_match_id AND status <> 'left') THEN
      UPDATE codebreaker_matches SET status = 'cancelled' WHERE id = p_match_id;
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION codebreaker_match_start(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_match codebreaker_matches; v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM codebreaker_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start'; END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'already started'; END IF;
  DELETE FROM codebreaker_match_participants WHERE match_id = p_match_id AND status = 'left';
  SELECT count(*) INTO v_count FROM codebreaker_match_participants WHERE match_id = p_match_id;
  IF v_count < 1 THEN RAISE EXCEPTION 'need at least 1 player'; END IF;
  UPDATE codebreaker_matches SET status = 'active', started_at = now(),
    deadline_at = CASE WHEN time_limit_seconds IS NOT NULL THEN now() + (time_limit_seconds || ' seconds')::interval ELSE NULL END
  WHERE id = p_match_id RETURNING * INTO v_match;
  RETURN jsonb_build_object('id', v_match.id, 'status', v_match.status, 'deadline_at', v_match.deadline_at);
END;
$$;

CREATE OR REPLACE FUNCTION codebreaker_match_guess(p_match_id uuid, p_guess text[])
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match codebreaker_matches;
  v_p codebreaker_match_participants;
  v_fb text[];
  v_correct boolean;
  v_points int := 0;
  v_first boolean := false;
  v_all_done boolean;
  v_colors text[] := ARRAY['red','blue','green','yellow','purple','orange'];
  v_speed_bonus int := 0;
  v_elapsed_pct numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF array_length(p_guess, 1) <> 4 THEN RAISE EXCEPTION 'guess must be 4 colors'; END IF;
  FOR i IN 1..4 LOOP
    IF NOT (p_guess[i] = ANY(v_colors)) THEN RAISE EXCEPTION 'invalid color: %', p_guess[i]; END IF;
  END LOOP;

  SELECT * INTO v_match FROM codebreaker_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'room not active'; END IF;

  IF v_match.deadline_at IS NOT NULL AND now() > v_match.deadline_at THEN
    UPDATE codebreaker_match_participants SET completed = true, status = 'finished', finished_at = now()
      WHERE match_id = p_match_id AND completed = false;
    UPDATE codebreaker_matches SET status = 'finished', finished_at = now() WHERE id = p_match_id AND status <> 'finished';
    RAISE EXCEPTION 'time expired';
  END IF;

  SELECT * INTO v_p FROM codebreaker_match_participants WHERE match_id = p_match_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not in room'; END IF;
  IF v_p.completed THEN RAISE EXCEPTION 'already finished'; END IF;
  IF v_p.guess_count >= v_match.max_guesses THEN RAISE EXCEPTION 'no guesses left'; END IF;

  v_fb := private.codebreaker_feedback(v_match.secret_code, p_guess);
  v_correct := p_guess = v_match.secret_code;

  IF v_correct AND v_match.winner_user_id IS NULL THEN
    v_first := true;
    v_points := GREATEST(5, 15 - (v_p.guess_count) * 2);
    IF v_match.deadline_at IS NOT NULL AND v_match.started_at IS NOT NULL THEN
      v_elapsed_pct := EXTRACT(EPOCH FROM (now() - v_match.started_at)) / v_match.time_limit_seconds;
      IF v_elapsed_pct <= 0.25 THEN v_speed_bonus := 5;
      ELSIF v_elapsed_pct <= 0.50 THEN v_speed_bonus := 3;
      ELSIF v_elapsed_pct <= 0.75 THEN v_speed_bonus := 1; END IF;
      v_points := v_points + v_speed_bonus;
    END IF;
    UPDATE codebreaker_matches SET winner_user_id = v_uid WHERE id = v_match.id;
  ELSIF v_correct THEN
    v_points := 3;
  END IF;

  UPDATE codebreaker_match_participants SET
    guesses = guesses || jsonb_build_array(to_jsonb(p_guess)),
    feedback = feedback || jsonb_build_array(to_jsonb(v_fb)),
    guess_count = guess_count + 1,
    won = v_correct,
    completed = v_correct OR guess_count + 1 >= v_match.max_guesses,
    status = CASE WHEN v_correct OR guess_count + 1 >= v_match.max_guesses THEN 'finished' ELSE status END,
    finished_at = CASE WHEN v_correct OR guess_count + 1 >= v_match.max_guesses THEN now() ELSE NULL END,
    points_awarded = v_points
  WHERE match_id = p_match_id AND user_id = v_uid;

  IF v_correct THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'codebreaker_multi', 'codebreaker_match', v_match.id::text, v_points,
      CASE WHEN v_first THEN 'First to crack the code' ELSE 'Cracked the code' END)
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

  SELECT NOT EXISTS (
    SELECT 1 FROM codebreaker_match_participants WHERE match_id = p_match_id AND status <> 'left' AND completed = false
  ) INTO v_all_done;

  IF v_all_done THEN
    UPDATE codebreaker_matches SET status = 'finished', finished_at = now() WHERE id = p_match_id AND status <> 'finished';
  END IF;

  RETURN codebreaker_match_board(p_match_id);
END;
$$;

CREATE OR REPLACE FUNCTION codebreaker_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match codebreaker_matches;
  v_players jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM codebreaker_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v_players
  FROM (
    SELECT p.user_id, p.status, p.guess_count, p.completed, p.won, p.points_awarded,
           p.joined_at, p.finished_at,
           CASE WHEN p.user_id = v_uid OR v_match.status = 'finished' THEN p.guesses ELSE '[]'::jsonb END AS guesses,
           CASE WHEN p.user_id = v_uid OR v_match.status = 'finished' THEN p.feedback ELSE '[]'::jsonb END AS feedback,
           s.full_name, s.role
    FROM codebreaker_match_participants p
    LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
    WHERE p.match_id = p_match_id
    ORDER BY p.won DESC, p.guess_count ASC, p.joined_at
  ) x;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id,
      'code', v_match.code,
      'status', v_match.status,
      'max_guesses', v_match.max_guesses,
      'max_players', v_match.max_players,
      'host_user_id', v_match.host_user_id,
      'winner_user_id', v_match.winner_user_id,
      'time_limit_seconds', v_match.time_limit_seconds,
      'deadline_at', v_match.deadline_at,
      'started_at', v_match.started_at,
      'finished_at', v_match.finished_at,
      'secret_code', CASE WHEN v_match.status = 'finished' THEN to_jsonb(v_match.secret_code) ELSE NULL END
    ),
    'players', v_players
  );
END;
$$;

GRANT EXECUTE ON FUNCTION codebreaker_daily_start() TO authenticated;
GRANT EXECUTE ON FUNCTION codebreaker_daily_guess(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION codebreaker_match_create(int) TO authenticated;
GRANT EXECUTE ON FUNCTION codebreaker_match_join(text) TO authenticated;
GRANT EXECUTE ON FUNCTION codebreaker_match_leave(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION codebreaker_match_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION codebreaker_match_guess(uuid, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION codebreaker_match_board(uuid) TO authenticated;
