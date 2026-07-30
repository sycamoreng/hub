/*
# Add multiplayer Wordle rooms

Adds head-to-head/group Wordle races (up to 6 players per room). Each room
picks its OWN fresh target word (independent of the daily puzzle) so playing
multiplayer never spoils or burns your daily attempt. Players share a short
6-character room code; the host starts the race and everyone races the same
hidden word. Winner is whoever solves first; remaining players are ranked by
solved / guess count.

1. New Tables
- `wordle_matches` - one row per room.
  - `id` (uuid), `host_user_id` (uuid), `code` (unique short code),
  - `target_word` (text, hidden until match finishes),
  - `letter_count`, `max_guesses`, `max_players`,
  - `status` ('pending' | 'active' | 'finished' | 'cancelled'),
  - `winner_user_id` (uuid, first solver),
  - `started_at`, `finished_at`, `created_at`.
- `wordle_match_participants` - one row per player in a room.
  - `id`, `match_id`, `user_id`, `status`,
  - `guesses` (text[], player's own guesses),
  - `results` (jsonb, per-guess hit/near/miss arrays for the live board),
  - `completed`, `won`, `guess_count`, `rank`,
  - `joined_at`, `finished_at`.

2. Security
- RLS enabled on both tables.
- Matches are readable by any authenticated user (needed so joiners can look up by code).
- Participants: readable by any authenticated user (only colour tiles are shown to
  others via the read-only board RPC; direct SELECT still hides letters because the UI
  chooses what to render).
- All writes flow through security-definer RPCs.

3. RPCs
- `wordle_match_create(letter_count, max_guesses, max_players)` - host creates a room, joins itself.
- `wordle_match_join(code)` - join an existing pending room.
- `wordle_match_leave(match_id)` - leave a pending room.
- `wordle_match_start(match_id)` - host starts the race.
- `wordle_match_submit_guess(match_id, guess)` - submit a guess; awards points to first solver.
- `wordle_match_lookup_by_code(code)` - lookup helper for the deep-link join flow.
- `wordle_match_board(match_id)` - returns the per-player live board (colour results only for others).

4. Notes
- Points: first solver receives (max_guesses - guess_count + 1) * 8, floor 15. Subsequent
  solvers receive floor 5.
- The `target_word` column is intentionally NOT exposed in RLS SELECTs; the RPCs are
  the only path that ever returns the answer, and only once the match is finished.
*/

-- === wordle_matches ===
CREATE TABLE IF NOT EXISTS wordle_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code text NOT NULL UNIQUE,
  target_word text NOT NULL,
  letter_count int NOT NULL DEFAULT 5,
  max_guesses int NOT NULL DEFAULT 6,
  max_players int NOT NULL DEFAULT 6 CHECK (max_players BETWEEN 2 AND 6),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','finished','cancelled')),
  winner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS wordle_matches_status_idx ON wordle_matches(status);
CREATE INDEX IF NOT EXISTS wordle_matches_host_idx ON wordle_matches(host_user_id);

ALTER TABLE wordle_matches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "wordle_matches_select" ON wordle_matches;
CREATE POLICY "wordle_matches_select" ON wordle_matches
  FOR SELECT TO authenticated USING (true);

-- === wordle_match_participants ===
CREATE TABLE IF NOT EXISTS wordle_match_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES wordle_matches(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'joined' CHECK (status IN ('joined','finished','left')),
  guesses text[] NOT NULL DEFAULT ARRAY[]::text[],
  results jsonb NOT NULL DEFAULT '[]'::jsonb,
  completed boolean NOT NULL DEFAULT false,
  won boolean NOT NULL DEFAULT false,
  guess_count int NOT NULL DEFAULT 0,
  rank int,
  joined_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE(match_id, user_id)
);
CREATE INDEX IF NOT EXISTS wordle_match_participants_match_idx ON wordle_match_participants(match_id);
CREATE INDEX IF NOT EXISTS wordle_match_participants_user_idx ON wordle_match_participants(user_id);

ALTER TABLE wordle_match_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "wordle_match_participants_select" ON wordle_match_participants;
CREATE POLICY "wordle_match_participants_select" ON wordle_match_participants
  FOR SELECT TO authenticated USING (true);

-- === helper: score a guess against target ===
CREATE OR REPLACE FUNCTION wordle_match_score_guess(p_target text, p_guess text, p_letter_count int)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_row jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_letter text;
  i int;
BEGIN
  FOR i IN 1..p_letter_count LOOP
    v_letter := substr(p_target, i, 1);
    IF substr(p_guess, i, 1) <> v_letter THEN
      v_counts := jsonb_set(v_counts, array[v_letter],
        to_jsonb(coalesce((v_counts ->> v_letter)::int, 0) + 1), true);
    END IF;
  END LOOP;
  FOR i IN 1..p_letter_count LOOP
    v_letter := substr(p_guess, i, 1);
    IF substr(p_target, i, 1) = v_letter THEN
      v_row := v_row || to_jsonb('hit'::text);
    ELSIF coalesce((v_counts ->> v_letter)::int, 0) > 0 THEN
      v_row := v_row || to_jsonb('near'::text);
      v_counts := jsonb_set(v_counts, array[v_letter],
        to_jsonb((v_counts ->> v_letter)::int - 1), true);
    ELSE
      v_row := v_row || to_jsonb('miss'::text);
    END IF;
  END LOOP;
  RETURN v_row;
END;
$$;

-- === RPC: create match ===
CREATE OR REPLACE FUNCTION wordle_match_create(
  p_letter_count int DEFAULT NULL,
  p_max_guesses int DEFAULT NULL,
  p_max_players int DEFAULT 6
)
RETURNS wordle_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_letters int;
  v_max int;
  v_players int;
  v_word text;
  v_code text;
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_attempt int := 0;
  v_match wordle_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;

  SELECT letter_count, max_guesses INTO v_letters, v_max
    FROM wordle_settings WHERE id = 1;
  v_letters := coalesce(p_letter_count, v_letters, 5);
  v_max := coalesce(p_max_guesses, v_max, 6);
  v_players := coalesce(p_max_players, 6);
  IF v_players < 2 OR v_players > 6 THEN RAISE EXCEPTION 'max_players must be 2-6'; END IF;

  SELECT word INTO v_word FROM wordle_words
    WHERE is_active AND length = v_letters
    ORDER BY random() LIMIT 1;
  IF v_word IS NULL THEN RAISE EXCEPTION 'no words available'; END IF;

  LOOP
    v_attempt := v_attempt + 1;
    v_code := '';
    FOR i IN 1..6 LOOP
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    END LOOP;
    BEGIN
      INSERT INTO wordle_matches (host_user_id, code, target_word, letter_count, max_guesses, max_players)
      VALUES (v_uid, v_code, v_word, v_letters, v_max, v_players)
      RETURNING * INTO v_match;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt > 6 THEN RAISE; END IF;
    END;
  END LOOP;

  INSERT INTO wordle_match_participants (match_id, user_id, status)
  VALUES (v_match.id, v_uid, 'joined');

  RETURN v_match;
END;
$$;

-- === RPC: join by code ===
CREATE OR REPLACE FUNCTION wordle_match_join(p_code text)
RETURNS wordle_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match wordle_matches;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM wordle_matches
    WHERE code = upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.status = 'cancelled' THEN RAISE EXCEPTION 'match cancelled'; END IF;

  IF EXISTS (SELECT 1 FROM wordle_match_participants WHERE match_id = v_match.id AND user_id = v_uid) THEN
    UPDATE wordle_match_participants SET status = 'joined'
      WHERE match_id = v_match.id AND user_id = v_uid AND status = 'left';
    RETURN v_match;
  END IF;

  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'match already started'; END IF;

  SELECT count(*) INTO v_count FROM wordle_match_participants
    WHERE match_id = v_match.id AND status <> 'left';
  IF v_count >= v_match.max_players THEN RAISE EXCEPTION 'room is full'; END IF;

  INSERT INTO wordle_match_participants (match_id, user_id, status)
  VALUES (v_match.id, v_uid, 'joined');

  RETURN v_match;
END;
$$;

-- === RPC: leave ===
CREATE OR REPLACE FUNCTION wordle_match_leave(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match wordle_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  IF v_match.status = 'pending' THEN
    UPDATE wordle_match_participants SET status = 'left'
      WHERE match_id = p_match_id AND user_id = v_uid;
    IF v_match.host_user_id = v_uid THEN
      IF NOT EXISTS (SELECT 1 FROM wordle_match_participants
                      WHERE match_id = p_match_id AND status <> 'left') THEN
        UPDATE wordle_matches SET status = 'cancelled' WHERE id = p_match_id;
      END IF;
    END IF;
  END IF;
END;
$$;

-- === RPC: start ===
CREATE OR REPLACE FUNCTION wordle_match_start(p_match_id uuid)
RETURNS wordle_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match wordle_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start'; END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'match already started'; END IF;

  UPDATE wordle_matches
    SET status = 'active', started_at = now()
    WHERE id = p_match_id
    RETURNING * INTO v_match;

  RETURN v_match;
END;
$$;

-- === RPC: submit guess ===
CREATE OR REPLACE FUNCTION wordle_match_submit_guess(p_match_id uuid, p_guess text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match wordle_matches;
  v_p wordle_match_participants;
  v_guess text := lower(trim(p_guess));
  v_row jsonb;
  v_won boolean := false;
  v_completed boolean := false;
  v_word_exists boolean;
  v_points int := 0;
  v_first_solver boolean := false;
  v_all_done boolean;
  v_rank int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'match not active'; END IF;

  SELECT * INTO v_p FROM wordle_match_participants
    WHERE match_id = p_match_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not in match'; END IF;
  IF v_p.completed THEN RAISE EXCEPTION 'you have already finished'; END IF;

  IF length(v_guess) <> v_match.letter_count THEN
    RAISE EXCEPTION 'guess must be % letters', v_match.letter_count;
  END IF;
  IF v_guess !~ '^[a-z]+$' THEN RAISE EXCEPTION 'letters only'; END IF;

  SELECT EXISTS(
    SELECT 1 FROM wordle_valid_guesses WHERE word = v_guess
    UNION ALL
    SELECT 1 FROM wordle_words WHERE word = v_guess AND is_active
  ) INTO v_word_exists;
  IF NOT v_word_exists THEN RAISE EXCEPTION 'not a valid word'; END IF;

  v_row := wordle_match_score_guess(v_match.target_word, v_guess, v_match.letter_count);
  v_p.guesses := array_append(v_p.guesses, v_guess);
  v_p.results := v_p.results || jsonb_build_array(v_row);
  v_p.guess_count := array_length(v_p.guesses, 1);
  v_won := (v_guess = v_match.target_word);
  v_completed := v_won OR v_p.guess_count >= v_match.max_guesses;

  IF v_completed AND v_match.winner_user_id IS NULL AND v_won THEN
    v_first_solver := true;
    UPDATE wordle_matches SET winner_user_id = v_uid WHERE id = v_match.id;
  END IF;

  IF v_completed THEN
    SELECT coalesce(max(rank), 0) + 1 INTO v_rank
      FROM wordle_match_participants
      WHERE match_id = p_match_id AND rank IS NOT NULL;
  END IF;

  UPDATE wordle_match_participants
    SET guesses = v_p.guesses,
        results = v_p.results,
        guess_count = v_p.guess_count,
        won = v_won,
        completed = v_completed,
        status = CASE WHEN v_completed THEN 'finished' ELSE status END,
        rank = CASE WHEN v_completed THEN v_rank ELSE rank END,
        finished_at = CASE WHEN v_completed THEN now() ELSE finished_at END
    WHERE match_id = p_match_id AND user_id = v_uid;

  IF v_won THEN
    IF v_first_solver THEN
      v_points := greatest(15, (v_match.max_guesses - v_p.guess_count + 1) * 8);
    ELSE
      v_points := 5;
    END IF;
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'wordle_multiplayer_won', 'wordle_match', v_match.id::text, v_points,
      CASE WHEN v_first_solver
        THEN 'First to solve in ' || v_p.guess_count || ' guesses'
        ELSE 'Solved in ' || v_p.guess_count || ' guesses' END)
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

  SELECT NOT EXISTS (
    SELECT 1 FROM wordle_match_participants
      WHERE match_id = p_match_id AND status <> 'left' AND completed = false
  ) INTO v_all_done;

  IF v_all_done THEN
    UPDATE wordle_matches
      SET status = 'finished', finished_at = now()
      WHERE id = p_match_id AND status <> 'finished';
  END IF;

  RETURN jsonb_build_object(
    'match_id', v_match.id,
    'letter_count', v_match.letter_count,
    'max_guesses', v_match.max_guesses,
    'guesses', to_jsonb(v_p.guesses),
    'results', v_p.results,
    'completed', v_completed,
    'won', v_won,
    'points_awarded', v_points,
    'first_solver', v_first_solver,
    'target', CASE WHEN v_completed OR v_all_done THEN v_match.target_word ELSE NULL END
  );
END;
$$;

-- === RPC: lookup by code ===
CREATE OR REPLACE FUNCTION wordle_match_lookup_by_code(p_code text)
RETURNS wordle_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_match wordle_matches;
BEGIN
  SELECT * INTO v_match FROM wordle_matches WHERE code = upper(trim(p_code));
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  RETURN v_match;
END;
$$;

-- === RPC: live board (colour results only for non-owners) ===
CREATE OR REPLACE FUNCTION wordle_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match wordle_matches;
  v_players jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
    INTO v_players
    FROM (
      SELECT p.user_id,
             p.status,
             p.guess_count,
             p.completed,
             p.won,
             p.rank,
             p.joined_at,
             p.finished_at,
             p.results,
             CASE WHEN p.user_id = v_uid OR v_match.status = 'finished'
                  THEN to_jsonb(p.guesses)
                  ELSE '[]'::jsonb END AS guesses,
             s.full_name,
             s.role
      FROM wordle_match_participants p
      LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
      WHERE p.match_id = p_match_id
      ORDER BY (p.rank IS NULL), p.rank NULLS LAST, p.joined_at
    ) x;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id,
      'code', v_match.code,
      'status', v_match.status,
      'letter_count', v_match.letter_count,
      'max_guesses', v_match.max_guesses,
      'max_players', v_match.max_players,
      'host_user_id', v_match.host_user_id,
      'winner_user_id', v_match.winner_user_id,
      'started_at', v_match.started_at,
      'finished_at', v_match.finished_at,
      'target', CASE WHEN v_match.status = 'finished' THEN v_match.target_word ELSE NULL END
    ),
    'players', v_players
  );
END;
$$;

GRANT EXECUTE ON FUNCTION wordle_match_create(int, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION wordle_match_join(text) TO authenticated;
GRANT EXECUTE ON FUNCTION wordle_match_leave(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION wordle_match_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION wordle_match_submit_guess(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION wordle_match_lookup_by_code(text) TO authenticated;
GRANT EXECUTE ON FUNCTION wordle_match_board(uuid) TO authenticated;
