/*
# Add multiplayer Guess Who + richer clue support

1. New Tables
   - `guess_who_matches` — one row per multiplayer room
   - `guess_who_match_participants` — one row per player in a room

2. Modified Functions
   - `guess_who_start_or_get` — now returns structured clues (category+text)

3. New Functions
   - `guess_who_match_create(staff_id?)` — host creates a room (picks random or today's staff)
   - `guess_who_match_join(code)` — join a pending room
   - `guess_who_match_leave(match_id)` — leave a pending room
   - `guess_who_match_start(match_id)` — host starts the race
   - `guess_who_match_submit(match_id, first_name, last_name)` — submit a guess
   - `guess_who_match_board(match_id)` — get match state for all players

4. Security
   - RLS on both tables, SELECT to authenticated.
   - All writes via SECURITY DEFINER RPCs.
*/

-- === guess_who_matches ===
CREATE TABLE IF NOT EXISTS guess_who_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code text NOT NULL UNIQUE,
  staff_id uuid NOT NULL REFERENCES staff_members(id),
  clues jsonb NOT NULL DEFAULT '[]'::jsonb,
  max_guesses int NOT NULL DEFAULT 5,
  max_players int NOT NULL DEFAULT 10,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','finished','cancelled')),
  winner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  clues_revealed int NOT NULL DEFAULT 1,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS guess_who_matches_status_idx ON guess_who_matches(status);
ALTER TABLE guess_who_matches ENABLE ROW LEVEL SECURITY;
CREATE POLICY "gw_matches_select" ON guess_who_matches FOR SELECT TO authenticated USING (true);

-- === guess_who_match_participants ===
CREATE TABLE IF NOT EXISTS guess_who_match_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES guess_who_matches(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'joined' CHECK (status IN ('joined','finished','left')),
  guesses jsonb NOT NULL DEFAULT '[]'::jsonb,
  completed boolean NOT NULL DEFAULT false,
  won boolean NOT NULL DEFAULT false,
  guess_count int NOT NULL DEFAULT 0,
  points_awarded int NOT NULL DEFAULT 0,
  joined_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE(match_id, user_id)
);
CREATE INDEX IF NOT EXISTS gw_match_participants_match_idx ON guess_who_match_participants(match_id);
ALTER TABLE guess_who_match_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "gw_participants_select" ON guess_who_match_participants FOR SELECT TO authenticated USING (true);

-- === RPC: create match ===
CREATE OR REPLACE FUNCTION guess_who_match_create(p_staff_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_staff staff_members;
  v_clues jsonb;
  v_code text;
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_attempt int := 0;
  v_match guess_who_matches;
  v_dept_name text;
  v_location_name text;
  v_city text;
  v_manager_name text;
  v_direct_reports int;
  v_pronoun text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;

  -- Pick staff member
  IF p_staff_id IS NOT NULL THEN
    SELECT * INTO v_staff FROM staff_members WHERE id = p_staff_id AND is_active AND directory_visible;
  ELSE
    SELECT * INTO v_staff FROM staff_members WHERE is_active AND directory_visible ORDER BY random() LIMIT 1;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'no eligible staff'; END IF;

  -- Gather context for clues
  SELECT name INTO v_dept_name FROM departments WHERE id = v_staff.department_id;
  SELECT name, city INTO v_location_name, v_city FROM locations WHERE id = v_staff.location_id;
  SELECT full_name INTO v_manager_name FROM staff_members WHERE id = v_staff.manager_id;
  SELECT count(*) INTO v_direct_reports FROM staff_members WHERE manager_id = v_staff.id AND is_active;

  v_pronoun := CASE WHEN lower(v_staff.gender) = 'female' THEN 'She'
                    WHEN lower(v_staff.gender) = 'male' THEN 'He'
                    ELSE 'This person' END;

  -- Generate fallback clues (AI clues come from edge function for daily, but multiplayer uses these)
  v_clues := jsonb_build_array(
    jsonb_build_object('category', 'vibe', 'text', v_pronoun || ' is a valued member of the Sycamore family' || CASE WHEN v_city IS NOT NULL THEN ' based in ' || v_city ELSE '' END || '.'),
    jsonb_build_object('category', 'location', 'text', CASE WHEN v_location_name IS NOT NULL THEN 'You''ll find them at the ' || v_location_name || '.' ELSE 'This person works hard every day.' END),
    jsonb_build_object('category', 'team', 'text', CASE WHEN v_dept_name IS NOT NULL THEN v_pronoun || ' is part of the ' || v_dept_name || ' department.' ELSE 'They work across several teams.' END),
    jsonb_build_object('category', 'connections', 'text', CASE WHEN v_manager_name IS NOT NULL THEN v_pronoun || ' reports to ' || v_manager_name || CASE WHEN v_direct_reports > 0 THEN ' and manages ' || v_direct_reports || ' people' ELSE '' END || '.' ELSE CASE WHEN v_direct_reports > 0 THEN v_pronoun || ' manages ' || v_direct_reports || ' direct report' || CASE WHEN v_direct_reports > 1 THEN 's' ELSE '' END || '.' ELSE v_pronoun || ' is an individual contributor.' END END),
    jsonb_build_object('category', 'role', 'text', v_pronoun || CASE WHEN v_staff.role IS NOT NULL THEN ' works as ' || v_staff.role ELSE '' END || CASE WHEN v_dept_name IS NOT NULL THEN ' in ' || v_dept_name ELSE '' END || '.')
  );

  -- Generate room code
  LOOP
    v_attempt := v_attempt + 1;
    v_code := '';
    FOR i IN 1..6 LOOP
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    END LOOP;
    BEGIN
      INSERT INTO guess_who_matches (host_user_id, code, staff_id, clues, max_guesses, max_players)
      VALUES (v_uid, v_code, v_staff.id, v_clues, 5, 10)
      RETURNING * INTO v_match;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt > 6 THEN RAISE; END IF;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'id', v_match.id,
    'code', v_match.code,
    'status', v_match.status,
    'max_guesses', v_match.max_guesses,
    'max_players', v_match.max_players,
    'host_user_id', v_match.host_user_id
  );
END;
$$;

-- === RPC: join by code ===
CREATE OR REPLACE FUNCTION guess_who_match_join(p_code text)
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
  SELECT * INTO v_match FROM guess_who_matches WHERE code = upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

  IF EXISTS (SELECT 1 FROM guess_who_match_participants WHERE match_id = v_match.id AND user_id = v_uid) THEN
    UPDATE guess_who_match_participants SET status = 'joined'
      WHERE match_id = v_match.id AND user_id = v_uid AND status = 'left';
    RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status);
  END IF;

  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'room already started'; END IF;
  SELECT count(*) INTO v_count FROM guess_who_match_participants
    WHERE match_id = v_match.id AND status <> 'left';
  IF v_count >= v_match.max_players THEN RAISE EXCEPTION 'room is full'; END IF;

  INSERT INTO guess_who_match_participants (match_id, user_id) VALUES (v_match.id, v_uid);
  RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status);
END;
$$;

-- === RPC: leave ===
CREATE OR REPLACE FUNCTION guess_who_match_leave(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match guess_who_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_match.status = 'pending' THEN
    UPDATE guess_who_match_participants SET status = 'left'
      WHERE match_id = p_match_id AND user_id = v_uid;
    IF v_match.host_user_id = v_uid THEN
      IF NOT EXISTS (SELECT 1 FROM guess_who_match_participants WHERE match_id = p_match_id AND status <> 'left') THEN
        UPDATE guess_who_matches SET status = 'cancelled' WHERE id = p_match_id;
      END IF;
    END IF;
  END IF;
END;
$$;

-- === RPC: start ===
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

  UPDATE guess_who_matches SET status = 'active', started_at = now()
    WHERE id = p_match_id RETURNING * INTO v_match;

  RETURN jsonb_build_object('id', v_match.id, 'status', v_match.status);
END;
$$;

-- === RPC: submit guess ===
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
  v_first_solver boolean := false;
  v_all_done boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'room not active'; END IF;

  SELECT * INTO v_p FROM guess_who_match_participants
    WHERE match_id = p_match_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'not in room'; END IF;
  IF v_p.completed THEN RAISE EXCEPTION 'already finished'; END IF;

  -- Check guess limit
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

  -- Determine if first solver
  IF v_correct AND v_match.winner_user_id IS NULL THEN
    v_first_solver := true;
    v_points := GREATEST(5, 15 - (jsonb_array_length(v_guesses) - 1) * 3);
    UPDATE guess_who_matches SET winner_user_id = v_uid WHERE id = v_match.id;
  ELSIF v_correct THEN
    v_points := 3;
  END IF;

  -- Reveal next clue for the room after each wrong guess by anyone
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

  -- Award points
  IF v_correct THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'guess_who_multi', 'guess_who_match', v_match.id::text, v_points,
      CASE WHEN v_first_solver THEN 'First to guess in multiplayer Guess Who' ELSE 'Correct guess in multiplayer Guess Who' END)
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

-- === RPC: board state ===
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
      'started_at', v_match.started_at,
      'finished_at', v_match.finished_at
    ),
    'clues', v_clues,
    'players', v_players,
    'answer', v_answer
  );
END;
$$;

GRANT EXECUTE ON FUNCTION guess_who_match_create(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_join(text) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_leave(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_submit(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION guess_who_match_board(uuid) TO authenticated;
