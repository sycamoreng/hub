/*
# Add time limit and speed bonus to Guess Who Multiplayer

1. Modified Tables
   - `guess_who_matches`:
     - `time_limit_seconds` (int, nullable) — optional time limit per room in seconds (null = no time limit)
     - `deadline_at` (timestamptz, nullable) — computed deadline after game starts (started_at + time_limit)

2. Modified Functions
   - `guess_who_match_create` — accepts optional `p_time_limit` parameter (30/60/90/120/null seconds)
   - `guess_who_match_start` — sets deadline_at when time_limit is configured
   - `guess_who_match_submit` — awards speed bonus: if you solve within first 25% of time remaining, +3 extra pts
   - `guess_who_match_board` — returns time_limit_seconds and deadline_at in match object

3. Important Notes
   - Time enforcement is advisory on the client; the server checks elapsed time on submit.
   - If deadline has passed and a player submits, it's rejected with 'time expired'.
   - Clue steal mechanic is already in place (wrong guess = next clue for all).
*/

-- Add columns
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guess_who_matches' AND column_name='time_limit_seconds') THEN
    ALTER TABLE guess_who_matches ADD COLUMN time_limit_seconds int;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='guess_who_matches' AND column_name='deadline_at') THEN
    ALTER TABLE guess_who_matches ADD COLUMN deadline_at timestamptz;
  END IF;
END $$;

-- Update create RPC to accept time limit
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

  -- Pick a random active staff member if not specified
  IF p_staff_id IS NOT NULL THEN
    v_staff_id := p_staff_id;
  ELSE
    SELECT id INTO v_staff_id FROM staff_members
      WHERE is_active = true AND directory_visible = true
      ORDER BY random() LIMIT 1;
    IF v_staff_id IS NULL THEN RAISE EXCEPTION 'no staff available'; END IF;
  END IF;

  -- Fetch clues from most recent puzzle for this person, or generate placeholder
  SELECT gp.clues INTO v_clues FROM guess_who_puzzles gp WHERE gp.staff_id = v_staff_id ORDER BY gp.puzzle_date DESC LIMIT 1;
  IF v_clues IS NULL OR jsonb_array_length(v_clues) = 0 THEN
    v_clues := jsonb_build_array(
      jsonb_build_object('category', 'role', 'text', (SELECT 'Works as ' || coalesce(role, 'a team member') FROM staff_members WHERE id = v_staff_id)),
      jsonb_build_object('category', 'team', 'text', (SELECT 'In the ' || coalesce(d.name, 'company') || ' department' FROM staff_members s LEFT JOIN departments d ON d.id = s.department_id WHERE s.id = v_staff_id)),
      jsonb_build_object('category', 'tenure', 'text', (SELECT 'Joined in ' || to_char(coalesce(joined_date, created_at), 'Month YYYY') FROM staff_members WHERE id = v_staff_id))
    );
  END IF;

  -- Generate unique 6-char code
  LOOP
    v_code := upper(substr(md5(random()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM guess_who_matches WHERE code = v_code);
  END LOOP;

  -- Validate time limit (allowed: NULL, 30, 60, 90, 120, 180)
  IF p_time_limit IS NOT NULL AND p_time_limit NOT IN (30, 60, 90, 120, 180) THEN
    p_time_limit := 90;
  END IF;

  INSERT INTO guess_who_matches (host_user_id, code, staff_id, clues, clues_revealed, time_limit_seconds)
  VALUES (v_uid, v_code, v_staff_id, v_clues, 1, p_time_limit)
  RETURNING * INTO v_match;

  RETURN jsonb_build_object(
    'id', v_match.id,
    'code', v_match.code,
    'status', v_match.status,
    'time_limit_seconds', v_match.time_limit_seconds
  );
END;
$$;

-- Update start to set deadline
CREATE OR REPLACE FUNCTION guess_who_match_start(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match guess_who_matches;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start'; END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'already started'; END IF;

  SELECT count(*) INTO v_count FROM guess_who_match_participants
    WHERE match_id = p_match_id AND status = 'joined';
  IF v_count < 1 THEN RAISE EXCEPTION 'need at least 1 player'; END IF;

  UPDATE guess_who_matches SET
    status = 'active',
    started_at = now(),
    deadline_at = CASE WHEN time_limit_seconds IS NOT NULL THEN now() + (time_limit_seconds || ' seconds')::interval ELSE NULL END
  WHERE id = p_match_id RETURNING * INTO v_match;

  RETURN jsonb_build_object('id', v_match.id, 'status', v_match.status, 'deadline_at', v_match.deadline_at);
END;
$$;

-- Update submit to check deadline + award speed bonus
CREATE OR REPLACE FUNCTION guess_who_match_submit(p_match_id uuid, p_first_name text, p_last_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match guess_who_matches;
  v_p guess_who_match_participants;
  v_target staff_members;
  v_correct boolean;
  v_target_first text;
  v_target_last text;
  v_name_parts text[];
  v_guesses jsonb;
  v_points int := 0;
  v_speed_bonus int := 0;
  v_first_solver boolean := false;
  v_all_done boolean;
  v_elapsed_pct numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'room not active'; END IF;

  -- Check deadline
  IF v_match.deadline_at IS NOT NULL AND now() > v_match.deadline_at THEN
    -- Auto-finish all remaining players
    UPDATE guess_who_match_participants SET completed = true, status = 'finished', finished_at = now()
      WHERE match_id = p_match_id AND completed = false;
    UPDATE guess_who_matches SET status = 'finished', finished_at = now() WHERE id = p_match_id AND status <> 'finished';
    RAISE EXCEPTION 'time expired';
  END IF;

  SELECT * INTO v_p FROM guess_who_match_participants
    WHERE match_id = p_match_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not in room'; END IF;
  IF v_p.completed THEN RAISE EXCEPTION 'already finished'; END IF;
  IF v_p.guess_count >= v_match.max_guesses THEN RAISE EXCEPTION 'no guesses left'; END IF;

  -- Get target
  SELECT * INTO v_target FROM staff_members WHERE id = v_match.staff_id;
  v_name_parts := string_to_array(trim(v_target.full_name), ' ');
  v_target_first := v_name_parts[1];
  v_target_last := v_name_parts[array_length(v_name_parts, 1)];

  v_correct := (
    lower(trim(p_first_name)) = lower(v_target_first)
    AND lower(trim(p_last_name)) = lower(v_target_last)
  );

  v_guesses := v_p.guesses || jsonb_build_array(jsonb_build_object(
    'first_name', trim(p_first_name),
    'last_name', trim(p_last_name),
    'correct', v_correct
  ));

  -- Determine if first solver + calculate speed bonus
  IF v_correct AND v_match.winner_user_id IS NULL THEN
    v_first_solver := true;
    v_points := GREATEST(5, 15 - (jsonb_array_length(v_guesses) - 1) * 3);
    -- Speed bonus: if timed and solved in first 25% of elapsed time, +3 extra
    IF v_match.deadline_at IS NOT NULL AND v_match.started_at IS NOT NULL THEN
      v_elapsed_pct := EXTRACT(EPOCH FROM (now() - v_match.started_at)) / v_match.time_limit_seconds;
      IF v_elapsed_pct <= 0.25 THEN
        v_speed_bonus := 5;
      ELSIF v_elapsed_pct <= 0.50 THEN
        v_speed_bonus := 3;
      ELSIF v_elapsed_pct <= 0.75 THEN
        v_speed_bonus := 1;
      END IF;
      v_points := v_points + v_speed_bonus;
    END IF;
    UPDATE guess_who_matches SET winner_user_id = v_uid WHERE id = v_match.id;
  ELSIF v_correct THEN
    v_points := 3;
  END IF;

  -- Reveal next clue on wrong guess
  IF NOT v_correct AND v_match.clues_revealed < jsonb_array_length(v_match.clues) THEN
    UPDATE guess_who_matches SET clues_revealed = clues_revealed + 1 WHERE id = v_match.id;
  END IF;

  -- Update participant
  UPDATE guess_who_match_participants SET
    guesses = v_guesses,
    guess_count = jsonb_array_length(v_guesses),
    won = v_correct,
    completed = v_correct OR jsonb_array_length(v_guesses) >= v_match.max_guesses,
    points_awarded = v_points,
    status = CASE WHEN v_correct OR jsonb_array_length(v_guesses) >= v_match.max_guesses THEN 'finished' ELSE status END,
    finished_at = CASE WHEN v_correct OR jsonb_array_length(v_guesses) >= v_match.max_guesses THEN now() ELSE NULL END
  WHERE match_id = p_match_id AND user_id = v_uid;

  -- Award points to leaderboard
  IF v_correct THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'guess_who_multi', 'guess_who_match', v_match.id::text, v_points,
      CASE WHEN v_first_solver THEN 'First to guess in multiplayer Guess Who' || CASE WHEN v_speed_bonus > 0 THEN ' (+' || v_speed_bonus || ' speed bonus)' ELSE '' END
           ELSE 'Correct guess in multiplayer Guess Who' END)
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

  -- Check if all done
  SELECT NOT EXISTS (
    SELECT 1 FROM guess_who_match_participants
      WHERE match_id = p_match_id AND status <> 'left' AND completed = false
  ) INTO v_all_done;

  IF v_all_done THEN
    UPDATE guess_who_matches SET status = 'finished', finished_at = now()
      WHERE id = p_match_id AND status <> 'finished';
  END IF;

  RETURN guess_who_match_board(p_match_id);
END;
$$;

-- Update board RPC to include new fields
CREATE OR REPLACE FUNCTION guess_who_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match guess_who_matches;
  v_players jsonb;
  v_clues jsonb;
  v_answer jsonb := null;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

  -- Only reveal clues up to clues_revealed count
  v_clues := '[]'::jsonb;
  FOR i IN 0..(v_match.clues_revealed - 1) LOOP
    v_clues := v_clues || jsonb_build_array(v_match.clues -> i);
  END LOOP;

  -- Players
  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v_players
  FROM (
    SELECT p.user_id, p.status, p.guess_count, p.completed, p.won,
           p.points_awarded, p.joined_at, p.finished_at,
           CASE WHEN p.user_id = v_uid OR v_match.status = 'finished'
                THEN p.guesses ELSE '[]'::jsonb END AS guesses,
           s.full_name, s.role
    FROM guess_who_match_participants p
    LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
    WHERE p.match_id = p_match_id
    ORDER BY p.won DESC, p.guess_count ASC, p.joined_at
  ) x;

  -- Reveal answer when finished
  IF v_match.status = 'finished' THEN
    SELECT jsonb_build_object(
      'full_name', s.full_name,
      'role', s.role,
      'department', d.name,
      'avatar_url', coalesce(up.avatar_url, '')
    ) INTO v_answer
    FROM staff_members s
    LEFT JOIN departments d ON d.id = s.department_id
    LEFT JOIN user_profiles up ON up.user_id = s.auth_user_id
    WHERE s.id = v_match.staff_id;
  END IF;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id,
      'code', v_match.code,
      'status', v_match.status,
      'max_guesses', v_match.max_guesses,
      'max_players', v_match.max_players,
      'host_user_id', v_match.host_user_id,
      'winner_user_id', v_match.winner_user_id,
      'clues_revealed', v_match.clues_revealed,
      'total_clues', jsonb_array_length(v_match.clues),
      'time_limit_seconds', v_match.time_limit_seconds,
      'deadline_at', v_match.deadline_at,
      'started_at', v_match.started_at,
      'finished_at', v_match.finished_at
    ),
    'clues', v_clues,
    'players', v_players,
    'answer', v_answer
  );
END;
$$;

GRANT EXECUTE ON FUNCTION guess_who_match_create(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_join(text) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_leave(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_submit(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_board(uuid) TO authenticated;
