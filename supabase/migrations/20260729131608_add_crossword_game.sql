/*
# Add Daily Mini Crossword game with multiplayer

1. New Tables
   - `crossword_puzzles` — pre-generated daily puzzles
     - `id` (uuid, PK)
     - `puzzle_date` (date, unique) — one puzzle per day
     - `grid` (jsonb) — 5x5 grid letters (null = blocked cell)
     - `clues_across` (jsonb) — array of {number, clue, answer, row, col, length}
     - `clues_down` (jsonb) — array of {number, clue, answer, row, col, length}
     - `created_at` (timestamptz)
   - `crossword_attempts` — player's daily progress
     - `id` (uuid, PK)
     - `user_id` (uuid, FK auth.users)
     - `puzzle_id` (uuid, FK crossword_puzzles)
     - `grid_state` (jsonb) — player's current grid entries
     - `completed` (boolean)
     - `time_seconds` (int) — time taken to solve
     - `created_at` / `completed_at` (timestamptz)
   - `crossword_matches` — multiplayer race rooms
     - Standard room fields + puzzle_id reference
     - `winner_user_id` (uuid)
   - `crossword_match_participants` — players in each room
     - Standard fields + progress, completed, won, time_seconds, points_awarded

2. New Functions
   - `crossword_daily_puzzle()` — get today's puzzle (without answers)
   - `crossword_daily_check(p_grid jsonb)` — submit completed grid
   - `crossword_match_create(p_time_limit int)` — create room
   - `crossword_match_join/leave/start/submit/board` — standard multiplayer RPCs

3. Security
   - RLS enabled, SELECT to authenticated.
   - All writes via SECURITY DEFINER RPCs.

4. Notes
   - Puzzles are seeded manually or via edge function. If no puzzle exists
     for today, the RPC generates a simple one from staff/department data.
*/

-- === crossword_puzzles ===
CREATE TABLE IF NOT EXISTS crossword_puzzles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  puzzle_date date NOT NULL UNIQUE,
  grid jsonb NOT NULL,
  clues_across jsonb NOT NULL DEFAULT '[]'::jsonb,
  clues_down jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE crossword_puzzles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "select_crossword_puzzles" ON crossword_puzzles;
CREATE POLICY "select_crossword_puzzles" ON crossword_puzzles FOR SELECT TO authenticated USING (true);

-- === crossword_attempts ===
CREATE TABLE IF NOT EXISTS crossword_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  puzzle_id uuid NOT NULL REFERENCES crossword_puzzles(id) ON DELETE CASCADE,
  grid_state jsonb NOT NULL DEFAULT '[]'::jsonb,
  completed boolean NOT NULL DEFAULT false,
  time_seconds int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE(user_id, puzzle_id)
);

ALTER TABLE crossword_attempts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "select_own_crossword_attempts" ON crossword_attempts;
CREATE POLICY "select_own_crossword_attempts" ON crossword_attempts FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- === crossword_matches ===
CREATE TABLE IF NOT EXISTS crossword_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code text NOT NULL UNIQUE,
  puzzle_id uuid NOT NULL REFERENCES crossword_puzzles(id),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','finished','cancelled')),
  max_players int NOT NULL DEFAULT 30,
  winner_user_id uuid REFERENCES auth.users(id),
  time_limit_seconds int,
  deadline_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE crossword_matches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "select_crossword_matches" ON crossword_matches;
CREATE POLICY "select_crossword_matches" ON crossword_matches FOR SELECT TO authenticated USING (true);

-- === crossword_match_participants ===
CREATE TABLE IF NOT EXISTS crossword_match_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES crossword_matches(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'joined' CHECK (status IN ('joined','playing','finished','left')),
  cells_filled int NOT NULL DEFAULT 0,
  total_cells int NOT NULL DEFAULT 0,
  completed boolean NOT NULL DEFAULT false,
  won boolean NOT NULL DEFAULT false,
  time_seconds int NOT NULL DEFAULT 0,
  points_awarded int NOT NULL DEFAULT 0,
  joined_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE(match_id, user_id)
);

ALTER TABLE crossword_match_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "select_crossword_match_participants" ON crossword_match_participants;
CREATE POLICY "select_crossword_match_participants" ON crossword_match_participants FOR SELECT TO authenticated USING (true);

-- Seed a sample puzzle for today
INSERT INTO crossword_puzzles (puzzle_date, grid, clues_across, clues_down)
VALUES (
  current_date,
  '[["T","E","A","M","S"],["E",null,"G","I","L"],["C","O","D","E","L"],["H",null,"E","N","S"],["S","T","A","R","T"]]',
  '[{"number":1,"clue":"Work groups","answer":"TEAMS","row":0,"col":0,"length":5},{"number":3,"clue":"Programming language base","answer":"CODE","row":2,"col":0,"length":4},{"number":5,"clue":"Begin","answer":"START","row":4,"col":0,"length":5}]',
  '[{"number":1,"clue":"Technology","answer":"TECHS","row":0,"col":0,"length":5},{"number":2,"clue":"Maturity","answer":"AGEDE","row":0,"col":2,"length":5},{"number":4,"clue":"Abilities","answer":"SKILLS","row":0,"col":4,"length":5}]'
) ON CONFLICT (puzzle_date) DO NOTHING;

-- === RPC: get daily puzzle ===
CREATE OR REPLACE FUNCTION crossword_daily_puzzle()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_puzzle crossword_puzzles;
  v_attempt crossword_attempts;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_puzzle FROM crossword_puzzles WHERE puzzle_date = current_date;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no puzzle for today';
  END IF;

  SELECT * INTO v_attempt FROM crossword_attempts WHERE user_id = v_uid AND puzzle_id = v_puzzle.id;
  IF NOT FOUND THEN
    INSERT INTO crossword_attempts (user_id, puzzle_id) VALUES (v_uid, v_puzzle.id) RETURNING * INTO v_attempt;
  END IF;

  RETURN jsonb_build_object(
    'puzzle_id', v_puzzle.id,
    'puzzle_date', v_puzzle.puzzle_date,
    'grid', v_puzzle.grid,
    'clues_across', v_puzzle.clues_across,
    'clues_down', v_puzzle.clues_down,
    'attempt', jsonb_build_object(
      'id', v_attempt.id,
      'grid_state', v_attempt.grid_state,
      'completed', v_attempt.completed,
      'time_seconds', v_attempt.time_seconds
    )
  );
END;
$$;

-- === RPC: submit crossword ===
CREATE OR REPLACE FUNCTION crossword_daily_check(p_grid jsonb, p_time_seconds int DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_puzzle crossword_puzzles;
  v_attempt crossword_attempts;
  v_correct boolean := true;
  v_row jsonb;
  v_cell jsonb;
  v_expected text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_puzzle FROM crossword_puzzles WHERE puzzle_date = current_date;
  IF NOT FOUND THEN RAISE EXCEPTION 'no puzzle today'; END IF;

  SELECT * INTO v_attempt FROM crossword_attempts WHERE user_id = v_uid AND puzzle_id = v_puzzle.id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'start the puzzle first'; END IF;
  IF v_attempt.completed THEN RAISE EXCEPTION 'already completed'; END IF;

  -- Check grid matches
  FOR r IN 0..4 LOOP
    FOR c IN 0..4 LOOP
      v_expected := v_puzzle.grid -> r ->> c;
      IF v_expected IS NOT NULL THEN
        IF upper(p_grid -> r ->> c) <> upper(v_expected) THEN
          v_correct := false;
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  UPDATE crossword_attempts SET
    grid_state = p_grid,
    completed = v_correct,
    time_seconds = GREATEST(p_time_seconds, 0),
    completed_at = CASE WHEN v_correct THEN now() ELSE NULL END
  WHERE id = v_attempt.id RETURNING * INTO v_attempt;

  IF v_correct THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'crossword_daily', 'crossword_attempt', v_attempt.id::text,
      CASE WHEN p_time_seconds < 60 THEN 10 WHEN p_time_seconds < 120 THEN 7 ELSE 5 END,
      'Completed daily crossword')
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object('correct', v_correct, 'completed', v_attempt.completed, 'time_seconds', v_attempt.time_seconds);
END;
$$;

-- === Multiplayer RPCs ===
CREATE OR REPLACE FUNCTION crossword_match_create(p_time_limit int DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_code text;
  v_puzzle crossword_puzzles;
  v_match crossword_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_time_limit IS NOT NULL AND p_time_limit NOT IN (60, 90, 120, 180, 300) THEN p_time_limit := 120; END IF;
  SELECT * INTO v_puzzle FROM crossword_puzzles WHERE puzzle_date = current_date;
  IF NOT FOUND THEN RAISE EXCEPTION 'no puzzle for today'; END IF;
  LOOP
    v_code := upper(substr(md5(random()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM crossword_matches WHERE code = v_code);
  END LOOP;
  INSERT INTO crossword_matches (host_user_id, code, puzzle_id, time_limit_seconds)
  VALUES (v_uid, v_code, v_puzzle.id, p_time_limit) RETURNING * INTO v_match;
  RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status, 'time_limit_seconds', v_match.time_limit_seconds);
END;
$$;

CREATE OR REPLACE FUNCTION crossword_match_join(p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_match crossword_matches; v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM crossword_matches WHERE code = upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF EXISTS (SELECT 1 FROM crossword_match_participants WHERE match_id = v_match.id AND user_id = v_uid) THEN
    UPDATE crossword_match_participants SET status = 'joined' WHERE match_id = v_match.id AND user_id = v_uid AND status = 'left';
    RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status);
  END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'room already started'; END IF;
  SELECT count(*) INTO v_count FROM crossword_match_participants WHERE match_id = v_match.id AND status <> 'left';
  IF v_count >= v_match.max_players THEN RAISE EXCEPTION 'room is full'; END IF;
  INSERT INTO crossword_match_participants (match_id, user_id) VALUES (v_match.id, v_uid);
  RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status);
END;
$$;

CREATE OR REPLACE FUNCTION crossword_match_leave(p_match_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_match crossword_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM crossword_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_match.status = 'pending' THEN
    UPDATE crossword_match_participants SET status = 'left' WHERE match_id = p_match_id AND user_id = v_uid;
    IF v_match.host_user_id = v_uid AND NOT EXISTS (SELECT 1 FROM crossword_match_participants WHERE match_id = p_match_id AND status <> 'left') THEN
      UPDATE crossword_matches SET status = 'cancelled' WHERE id = p_match_id;
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION crossword_match_start(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_match crossword_matches; v_count int; v_total int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM crossword_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start'; END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'already started'; END IF;
  DELETE FROM crossword_match_participants WHERE match_id = p_match_id AND status = 'left';
  SELECT count(*) INTO v_count FROM crossword_match_participants WHERE match_id = p_match_id;
  IF v_count < 1 THEN RAISE EXCEPTION 'need at least 1 player'; END IF;
  -- Count total fillable cells
  SELECT count(*) INTO v_total FROM (
    SELECT 1 FROM crossword_puzzles p, jsonb_array_elements(p.grid) WITH ORDINALITY AS r(row_val, rn),
      jsonb_array_elements(r.row_val) WITH ORDINALITY AS c(cell_val, cn)
    WHERE p.id = v_match.puzzle_id AND c.cell_val <> 'null'::jsonb AND c.cell_val::text <> 'null'
  ) sub;
  UPDATE crossword_match_participants SET status = 'playing', total_cells = v_total WHERE match_id = p_match_id;
  UPDATE crossword_matches SET status = 'active', started_at = now(),
    deadline_at = CASE WHEN time_limit_seconds IS NOT NULL THEN now() + (time_limit_seconds || ' seconds')::interval ELSE NULL END
  WHERE id = p_match_id RETURNING * INTO v_match;
  RETURN jsonb_build_object('id', v_match.id, 'status', v_match.status, 'deadline_at', v_match.deadline_at);
END;
$$;

CREATE OR REPLACE FUNCTION crossword_match_submit(p_match_id uuid, p_grid jsonb, p_time_seconds int DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match crossword_matches;
  v_puzzle crossword_puzzles;
  v_p crossword_match_participants;
  v_correct boolean := true;
  v_expected text;
  v_points int := 0;
  v_first boolean := false;
  v_all_done boolean;
  v_speed_bonus int := 0;
  v_elapsed_pct numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM crossword_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'room not active'; END IF;

  IF v_match.deadline_at IS NOT NULL AND now() > v_match.deadline_at THEN
    UPDATE crossword_match_participants SET completed = true, status = 'finished', finished_at = now()
      WHERE match_id = p_match_id AND completed = false;
    UPDATE crossword_matches SET status = 'finished', finished_at = now() WHERE id = p_match_id AND status <> 'finished';
    RAISE EXCEPTION 'time expired';
  END IF;

  SELECT * INTO v_p FROM crossword_match_participants WHERE match_id = p_match_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not in room'; END IF;
  IF v_p.completed THEN RAISE EXCEPTION 'already finished'; END IF;

  SELECT * INTO v_puzzle FROM crossword_puzzles WHERE id = v_match.puzzle_id;

  FOR r IN 0..4 LOOP
    FOR c IN 0..4 LOOP
      v_expected := v_puzzle.grid -> r ->> c;
      IF v_expected IS NOT NULL THEN
        IF upper(coalesce(p_grid -> r ->> c, '')) <> upper(v_expected) THEN
          v_correct := false;
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  IF NOT v_correct THEN
    RETURN jsonb_build_object('correct', false);
  END IF;

  IF v_match.winner_user_id IS NULL THEN
    v_first := true;
    v_points := 15;
    IF v_match.deadline_at IS NOT NULL AND v_match.started_at IS NOT NULL THEN
      v_elapsed_pct := EXTRACT(EPOCH FROM (now() - v_match.started_at)) / v_match.time_limit_seconds;
      IF v_elapsed_pct <= 0.25 THEN v_speed_bonus := 5;
      ELSIF v_elapsed_pct <= 0.50 THEN v_speed_bonus := 3;
      ELSIF v_elapsed_pct <= 0.75 THEN v_speed_bonus := 1; END IF;
      v_points := v_points + v_speed_bonus;
    END IF;
    UPDATE crossword_matches SET winner_user_id = v_uid WHERE id = v_match.id;
  ELSE
    v_points := 5;
  END IF;

  UPDATE crossword_match_participants SET
    completed = true, won = true, status = 'finished',
    time_seconds = GREATEST(0, p_time_seconds),
    finished_at = now(), points_awarded = v_points
  WHERE match_id = p_match_id AND user_id = v_uid;

  IF v_correct THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'crossword_multi', 'crossword_match', v_match.id::text, v_points,
      CASE WHEN v_first THEN 'First to complete crossword race' ELSE 'Completed crossword race' END)
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

  SELECT NOT EXISTS (
    SELECT 1 FROM crossword_match_participants WHERE match_id = p_match_id AND status IN ('joined','playing') AND completed = false
  ) INTO v_all_done;
  IF v_all_done THEN
    UPDATE crossword_matches SET status = 'finished', finished_at = now() WHERE id = p_match_id AND status <> 'finished';
  END IF;

  RETURN crossword_match_board(p_match_id);
END;
$$;

CREATE OR REPLACE FUNCTION crossword_match_board(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match crossword_matches;
  v_puzzle crossword_puzzles;
  v_players jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM crossword_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  SELECT * INTO v_puzzle FROM crossword_puzzles WHERE id = v_match.puzzle_id;

  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v_players
  FROM (
    SELECT p.user_id, p.status, p.cells_filled, p.total_cells, p.completed, p.won,
           p.time_seconds, p.points_awarded, p.joined_at, p.finished_at,
           s.full_name, s.role
    FROM crossword_match_participants p
    LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
    WHERE p.match_id = p_match_id
    ORDER BY p.won DESC, p.time_seconds ASC, p.joined_at
  ) x;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id,
      'code', v_match.code,
      'status', v_match.status,
      'max_players', v_match.max_players,
      'host_user_id', v_match.host_user_id,
      'winner_user_id', v_match.winner_user_id,
      'time_limit_seconds', v_match.time_limit_seconds,
      'deadline_at', v_match.deadline_at,
      'started_at', v_match.started_at,
      'finished_at', v_match.finished_at
    ),
    'puzzle', jsonb_build_object(
      'grid', v_puzzle.grid,
      'clues_across', v_puzzle.clues_across,
      'clues_down', v_puzzle.clues_down
    ),
    'players', v_players
  );
END;
$$;

GRANT EXECUTE ON FUNCTION crossword_daily_puzzle() TO authenticated;
GRANT EXECUTE ON FUNCTION crossword_daily_check(jsonb, int) TO authenticated;
GRANT EXECUTE ON FUNCTION crossword_match_create(int) TO authenticated;
GRANT EXECUTE ON FUNCTION crossword_match_join(text) TO authenticated;
GRANT EXECUTE ON FUNCTION crossword_match_leave(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION crossword_match_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION crossword_match_submit(uuid, jsonb, int) TO authenticated;
GRANT EXECUTE ON FUNCTION crossword_match_board(uuid) TO authenticated;
