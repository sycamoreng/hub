/*
# Wordle multiplayer: add time limit + increase max players to 30

1. Modified Tables
   - `wordle_matches`:
     - `time_limit_seconds` (int, nullable) — optional countdown timer (null = no limit)
     - `deadline_at` (timestamptz, nullable) — computed from started_at + time_limit on start

2. Modified Functions
   - `wordle_match_create` — accepts optional `p_time_limit` (30/60/90/120/180/null),
     increases max_players cap from 25 to 30
   - `wordle_match_start` — sets deadline_at based on time_limit_seconds
   - `wordle_match_submit_guess` — rejects guesses after deadline, awards speed bonus
     (+5 if solved in first 25%, +3 in first 50%, +1 in first 75% of time)
   - `wordle_match_board` — returns time_limit_seconds and deadline_at

3. Also: `guess_who_matches` max_players default increased from 10 to 30,
   and `guess_who_match_create` validation updated to allow up to 30.

4. Important Notes
   - Backward compatible: existing rooms without time_limit continue to work normally.
   - Speed bonus only applies to the first solver in a timed room.
*/

-- Add time columns to wordle_matches
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='wordle_matches' AND column_name='time_limit_seconds') THEN
    ALTER TABLE wordle_matches ADD COLUMN time_limit_seconds int;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='wordle_matches' AND column_name='deadline_at') THEN
    ALTER TABLE wordle_matches ADD COLUMN deadline_at timestamptz;
  END IF;
END $$;

-- Update wordle_match_create: add p_time_limit, raise cap to 30
CREATE OR REPLACE FUNCTION wordle_match_create(
  p_letter_count int DEFAULT NULL,
  p_max_guesses int DEFAULT NULL,
  p_max_players int DEFAULT 6,
  p_time_limit int DEFAULT NULL
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
  IF v_players < 2 OR v_players > 30 THEN RAISE EXCEPTION 'max_players must be 2-30'; END IF;

  -- Validate time limit
  IF p_time_limit IS NOT NULL AND p_time_limit NOT IN (30, 60, 90, 120, 180) THEN
    p_time_limit := 90;
  END IF;

  SELECT word INTO v_word FROM wordle_words
    WHERE length(word) = v_letters
    ORDER BY random() LIMIT 1;
  IF v_word IS NULL THEN RAISE EXCEPTION 'no word available for that letter count'; END IF;

  LOOP
    v_code := '';
    FOR i IN 1..6 LOOP
      v_code := v_code || substr(v_alphabet, floor(random() * length(v_alphabet))::int + 1, 1);
    END LOOP;
    v_attempt := v_attempt + 1;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM wordle_matches WHERE code = v_code) OR v_attempt > 20;
  END LOOP;

  INSERT INTO wordle_matches (host_user_id, code, target, letter_count, max_guesses, max_players, time_limit_seconds)
  VALUES (v_uid, v_code, v_word, v_letters, v_max, v_players, p_time_limit)
  RETURNING * INTO v_match;

  RETURN v_match;
END;
$$;

-- Update wordle_match_start: set deadline_at
CREATE OR REPLACE FUNCTION wordle_match_start(p_match_id uuid)
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
  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start'; END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'already started'; END IF;

  -- Remove anyone who left before start
  DELETE FROM wordle_match_participants WHERE match_id = p_match_id AND status = 'left';

  SELECT count(*) INTO v_count FROM wordle_match_participants
    WHERE match_id = p_match_id AND status = 'joined';
  IF v_count < 1 THEN RAISE EXCEPTION 'need at least 1 player'; END IF;

  UPDATE wordle_matches SET
    status = 'active',
    started_at = now(),
    deadline_at = CASE WHEN time_limit_seconds IS NOT NULL THEN now() + (time_limit_seconds || ' seconds')::interval ELSE NULL END
  WHERE id = p_match_id RETURNING * INTO v_match;

  RETURN v_match;
END;
$$;

-- Update wordle_match_board to include time fields
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
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v_players
  FROM (
    SELECT p.user_id, p.status, p.guess_count, p.completed, p.won, p.rank,
           p.joined_at, p.finished_at, p.points_awarded,
           CASE WHEN p.user_id = v_uid OR v_match.status = 'finished'
                THEN p.guesses ELSE '[]'::jsonb END AS guesses,
           CASE WHEN p.user_id = v_uid OR v_match.status = 'finished'
                THEN p.results ELSE '[]'::jsonb END AS results,
           s.full_name, s.role
    FROM wordle_match_participants p
    LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
    WHERE p.match_id = p_match_id
    ORDER BY p.won DESC, p.guess_count ASC, p.joined_at
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
      'time_limit_seconds', v_match.time_limit_seconds,
      'deadline_at', v_match.deadline_at,
      'target', CASE WHEN v_match.status = 'finished' THEN v_match.target ELSE NULL END
    ),
    'players', v_players
  );
END;
$$;

-- Update wordle_match_submit_guess: check deadline + speed bonus
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
  v_g text;
  v_results text[];
  v_correct boolean;
  v_points int := 0;
  v_speed_bonus int := 0;
  v_first boolean := false;
  v_all_done boolean;
  v_existing_guesses jsonb;
  v_existing_results jsonb;
  v_elapsed_pct numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  v_g := lower(trim(p_guess));

  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'room not active'; END IF;

  -- Check deadline
  IF v_match.deadline_at IS NOT NULL AND now() > v_match.deadline_at THEN
    UPDATE wordle_match_participants SET completed = true, status = 'finished', finished_at = now()
      WHERE match_id = p_match_id AND completed = false;
    UPDATE wordle_matches SET status = 'finished', finished_at = now() WHERE id = p_match_id AND status <> 'finished';
    RAISE EXCEPTION 'time expired';
  END IF;

  SELECT * INTO v_p FROM wordle_match_participants
    WHERE match_id = p_match_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not in room'; END IF;
  IF v_p.completed THEN RAISE EXCEPTION 'already finished'; END IF;
  IF v_p.guess_count >= v_match.max_guesses THEN RAISE EXCEPTION 'no guesses left'; END IF;

  -- Validate guess is a real word
  IF length(v_g) <> v_match.letter_count THEN
    RAISE EXCEPTION 'guess must be % letters', v_match.letter_count;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM wordle_valid_guesses WHERE word = v_g) THEN
    RAISE EXCEPTION 'not a valid word';
  END IF;

  -- Compute results
  v_results := array_fill(''::text, ARRAY[v_match.letter_count]);
  -- First pass: exact matches
  FOR i IN 1..v_match.letter_count LOOP
    IF substr(v_g, i, 1) = substr(v_match.target, i, 1) THEN
      v_results[i] := 'hit';
    END IF;
  END LOOP;
  -- Second pass: near matches
  FOR i IN 1..v_match.letter_count LOOP
    IF v_results[i] = '' THEN
      DECLARE
        ch text := substr(v_g, i, 1);
        target_count int := 0;
        guess_hit_count int := 0;
        guess_near_before int := 0;
      BEGIN
        FOR j IN 1..v_match.letter_count LOOP
          IF substr(v_match.target, j, 1) = ch THEN target_count := target_count + 1; END IF;
          IF substr(v_g, j, 1) = ch AND v_results[j] = 'hit' THEN guess_hit_count := guess_hit_count + 1; END IF;
          IF j < i AND substr(v_g, j, 1) = ch AND v_results[j] = 'near' THEN guess_near_before := guess_near_before + 1; END IF;
        END LOOP;
        IF target_count > guess_hit_count + guess_near_before THEN
          v_results[i] := 'near';
        ELSE
          v_results[i] := 'miss';
        END IF;
      END;
    END IF;
  END LOOP;

  v_correct := v_g = v_match.target;

  -- Update guesses
  v_existing_guesses := v_p.guesses || to_jsonb(ARRAY[v_g]);
  v_existing_results := v_p.results || jsonb_build_array(to_jsonb(v_results));

  -- Points
  IF v_correct AND v_match.winner_user_id IS NULL THEN
    v_first := true;
    v_points := GREATEST(5, 15 - v_p.guess_count * 3);
    -- Speed bonus for timed rooms
    IF v_match.deadline_at IS NOT NULL AND v_match.started_at IS NOT NULL THEN
      v_elapsed_pct := EXTRACT(EPOCH FROM (now() - v_match.started_at)) / v_match.time_limit_seconds;
      IF v_elapsed_pct <= 0.25 THEN v_speed_bonus := 5;
      ELSIF v_elapsed_pct <= 0.50 THEN v_speed_bonus := 3;
      ELSIF v_elapsed_pct <= 0.75 THEN v_speed_bonus := 1;
      END IF;
      v_points := v_points + v_speed_bonus;
    END IF;
    UPDATE wordle_matches SET winner_user_id = v_uid WHERE id = v_match.id;
  ELSIF v_correct THEN
    v_points := 3;
  END IF;

  UPDATE wordle_match_participants SET
    guesses = v_existing_guesses,
    results = v_existing_results,
    guess_count = jsonb_array_length(v_existing_guesses),
    won = v_correct,
    completed = v_correct OR jsonb_array_length(v_existing_guesses) >= v_match.max_guesses,
    status = CASE WHEN v_correct OR jsonb_array_length(v_existing_guesses) >= v_match.max_guesses THEN 'finished' ELSE status END,
    finished_at = CASE WHEN v_correct OR jsonb_array_length(v_existing_guesses) >= v_match.max_guesses THEN now() ELSE NULL END,
    points_awarded = v_points
  WHERE match_id = p_match_id AND user_id = v_uid;

  -- Award leaderboard points
  IF v_correct THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'wordle_multi', 'wordle_match', v_match.id::text, v_points,
      CASE WHEN v_first THEN 'First to solve in multiplayer Wordle' || CASE WHEN v_speed_bonus > 0 THEN ' (+' || v_speed_bonus || ' speed bonus)' ELSE '' END
           ELSE 'Solved in multiplayer Wordle' END)
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

  -- Check all done
  SELECT NOT EXISTS (
    SELECT 1 FROM wordle_match_participants
      WHERE match_id = p_match_id AND status <> 'left' AND completed = false
  ) INTO v_all_done;

  IF v_all_done THEN
    UPDATE wordle_matches SET status = 'finished', finished_at = now()
      WHERE id = p_match_id AND status <> 'finished';
  END IF;

  RETURN jsonb_build_object(
    'match_id', v_match.id,
    'letter_count', v_match.letter_count,
    'max_guesses', v_match.max_guesses,
    'guesses', v_existing_guesses,
    'results', v_existing_results,
    'completed', v_correct OR jsonb_array_length(v_existing_guesses) >= v_match.max_guesses,
    'won', v_correct,
    'points_awarded', v_points,
    'first_solver', v_first,
    'target', CASE WHEN v_correct OR jsonb_array_length(v_existing_guesses) >= v_match.max_guesses
                   THEN v_match.target ELSE NULL END
  );
END;
$$;

-- Increase guess_who max_players default and validation to 30
ALTER TABLE guess_who_matches ALTER COLUMN max_players SET DEFAULT 30;

-- Update guess_who_match_create to allow up to 30 players
CREATE OR REPLACE FUNCTION guess_who_match_create(p_staff_id uuid DEFAULT NULL, p_time_limit int DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_staff_id uuid;
  v_code text;
  v_match guess_who_matches;
  v_clues jsonb := '[]'::jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;

  IF p_staff_id IS NOT NULL THEN
    v_staff_id := p_staff_id;
  ELSE
    SELECT id INTO v_staff_id FROM staff_members
      WHERE is_active = true AND directory_visible = true
      ORDER BY random() LIMIT 1;
    IF v_staff_id IS NULL THEN RAISE EXCEPTION 'no staff available'; END IF;
  END IF;

  SELECT gp.clues INTO v_clues FROM guess_who_puzzles gp WHERE gp.staff_id = v_staff_id ORDER BY gp.puzzle_date DESC LIMIT 1;
  IF v_clues IS NULL OR jsonb_array_length(v_clues) = 0 THEN
    v_clues := jsonb_build_array(
      jsonb_build_object('category', 'role', 'text', (SELECT 'Works as ' || coalesce(role, 'a team member') FROM staff_members WHERE id = v_staff_id)),
      jsonb_build_object('category', 'team', 'text', (SELECT 'In the ' || coalesce(d.name, 'company') || ' department' FROM staff_members s LEFT JOIN departments d ON d.id = s.department_id WHERE s.id = v_staff_id)),
      jsonb_build_object('category', 'tenure', 'text', (SELECT 'Joined in ' || to_char(coalesce(joined_date, created_at), 'Month YYYY') FROM staff_members WHERE id = v_staff_id))
    );
  END IF;

  LOOP
    v_code := upper(substr(md5(random()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM guess_who_matches WHERE code = v_code);
  END LOOP;

  IF p_time_limit IS NOT NULL AND p_time_limit NOT IN (30, 60, 90, 120, 180) THEN
    p_time_limit := 90;
  END IF;

  INSERT INTO guess_who_matches (host_user_id, code, staff_id, clues, clues_revealed, time_limit_seconds, max_players)
  VALUES (v_uid, v_code, v_staff_id, v_clues, 1, p_time_limit, 30)
  RETURNING * INTO v_match;

  RETURN jsonb_build_object(
    'id', v_match.id,
    'code', v_match.code,
    'status', v_match.status,
    'time_limit_seconds', v_match.time_limit_seconds
  );
END;
$$;

-- Re-grant execute on updated functions
GRANT EXECUTE ON FUNCTION wordle_match_create(int, int, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION wordle_match_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION wordle_match_board(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION wordle_match_submit_guess(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_create(uuid, int) TO authenticated;
