/*
  # Add Guess Who multiplayer clue mode (shared vs solo)

  1. New columns
    - `guess_who_matches.clue_mode` text ('shared' | 'solo', default 'shared') controls
      whether wrong guesses reveal the next clue to everyone or only to the guessing player.
    - `guess_who_match_participants.clues_revealed` int (default 1) counts how many clues
      this specific participant has unlocked in solo mode.

  2. Updated RPCs
    - `guess_who_match_create` now accepts `p_clue_mode` ('shared' or 'solo').
    - `guess_who_match_submit` bumps either the match-wide `clues_revealed` (shared mode)
      or the participant's own `clues_revealed` (solo mode) on a wrong guess.
    - `guess_who_match_board` returns the clues visible to the requesting user based on
      the room's mode and includes `clue_mode` in the match payload.
    - `guess_who_match_next_round` and `guess_who_match_restart` reset each participant's
      `clues_revealed` back to 1.

  3. Notes
    - Existing rooms default to `shared` so behavior is unchanged for anyone already playing.
    - In solo mode the round still ends when the timer runs out or everyone has finished.
*/

-- 1. Columns
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='guess_who_matches' AND column_name='clue_mode'
  ) THEN
    ALTER TABLE public.guess_who_matches
      ADD COLUMN clue_mode text NOT NULL DEFAULT 'shared';
    ALTER TABLE public.guess_who_matches
      ADD CONSTRAINT guess_who_matches_clue_mode_check CHECK (clue_mode IN ('shared','solo'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='guess_who_match_participants' AND column_name='clues_revealed'
  ) THEN
    ALTER TABLE public.guess_who_match_participants
      ADD COLUMN clues_revealed int NOT NULL DEFAULT 1;
  END IF;
END $$;

-- 2. Recreate create RPC with new p_clue_mode param
DROP FUNCTION IF EXISTS public.guess_who_match_create(uuid, integer);
DROP FUNCTION IF EXISTS public.guess_who_match_create(uuid, integer, text);

CREATE OR REPLACE FUNCTION public.guess_who_match_create(
  p_staff_id uuid DEFAULT NULL,
  p_time_limit integer DEFAULT NULL,
  p_clue_mode text DEFAULT 'shared'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_staff_id uuid;
  v_code text;
  v_match guess_who_matches;
  v_clues jsonb := '[]'::jsonb;
  v_mode text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;

  v_mode := lower(coalesce(p_clue_mode, 'shared'));
  IF v_mode NOT IN ('shared','solo') THEN v_mode := 'shared'; END IF;

  IF p_staff_id IS NOT NULL THEN
    v_staff_id := p_staff_id;
  ELSE
    SELECT id INTO v_staff_id FROM staff_members
      WHERE is_active = true AND directory_visible = true
      ORDER BY random() LIMIT 1;
    IF v_staff_id IS NULL THEN RAISE EXCEPTION 'no staff available'; END IF;
  END IF;

  v_clues := public._guess_who_build_clues(v_staff_id);

  LOOP
    v_code := upper(substr(md5(random()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM guess_who_matches WHERE code = v_code);
  END LOOP;

  IF p_time_limit IS NOT NULL AND p_time_limit NOT IN (30, 60, 90, 120, 180) THEN
    p_time_limit := 90;
  END IF;

  INSERT INTO guess_who_matches (host_user_id, code, staff_id, clues, clues_revealed, time_limit_seconds, clue_mode)
    VALUES (v_uid, v_code, v_staff_id, v_clues, 1, p_time_limit, v_mode)
    RETURNING * INTO v_match;

  RETURN jsonb_build_object(
    'id', v_match.id,
    'code', v_match.code,
    'status', v_match.status,
    'time_limit_seconds', v_match.time_limit_seconds,
    'clue_mode', v_match.clue_mode
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.guess_who_match_create(uuid, integer, text) TO authenticated;

-- 3. Submit RPC: bump per-player clues in solo mode, match-wide in shared mode
CREATE OR REPLACE FUNCTION public.guess_who_match_submit(p_match_id uuid, p_first_name text, p_last_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_new_solo_revealed int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'room not active'; END IF;

  IF v_match.deadline_at IS NOT NULL AND now() > v_match.deadline_at THEN
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

  IF v_correct AND v_match.winner_user_id IS NULL THEN
    v_first_solver := true;
    v_points := GREATEST(5, 15 - (jsonb_array_length(v_guesses) - 1) * 3);
    IF v_match.deadline_at IS NOT NULL AND v_match.started_at IS NOT NULL THEN
      v_elapsed_pct := EXTRACT(EPOCH FROM (now() - v_match.started_at)) / v_match.time_limit_seconds;
      IF v_elapsed_pct <= 0.25 THEN v_speed_bonus := 5;
      ELSIF v_elapsed_pct <= 0.50 THEN v_speed_bonus := 3;
      ELSIF v_elapsed_pct <= 0.75 THEN v_speed_bonus := 1;
      END IF;
      v_points := v_points + v_speed_bonus;
    END IF;
    UPDATE guess_who_matches SET winner_user_id = v_uid WHERE id = v_match.id;
  ELSIF v_correct THEN
    v_points := 3;
  END IF;

  -- Reveal next clue on wrong guess: match-wide in shared mode, per-player in solo mode
  IF NOT v_correct THEN
    IF v_match.clue_mode = 'solo' THEN
      v_new_solo_revealed := LEAST(v_p.clues_revealed + 1, jsonb_array_length(v_match.clues));
    ELSE
      IF v_match.clues_revealed < jsonb_array_length(v_match.clues) THEN
        UPDATE guess_who_matches SET clues_revealed = clues_revealed + 1 WHERE id = v_match.id;
      END IF;
    END IF;
  END IF;

  UPDATE guess_who_match_participants SET
    guesses = v_guesses,
    guess_count = jsonb_array_length(v_guesses),
    won = v_correct,
    completed = v_correct OR jsonb_array_length(v_guesses) >= v_match.max_guesses,
    points_awarded = v_points,
    status = CASE WHEN v_correct OR jsonb_array_length(v_guesses) >= v_match.max_guesses THEN 'finished' ELSE status END,
    finished_at = CASE WHEN v_correct OR jsonb_array_length(v_guesses) >= v_match.max_guesses THEN now() ELSE NULL END,
    clues_revealed = CASE
      WHEN v_match.clue_mode = 'solo' AND NOT v_correct
        THEN v_new_solo_revealed
      ELSE clues_revealed
    END
    WHERE match_id = p_match_id AND user_id = v_uid;

  IF v_correct THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
      VALUES (v_uid, 'guess_who_multi', 'guess_who_match', v_match.id::text, v_points,
        CASE WHEN v_first_solver THEN 'First to guess in multiplayer Guess Who' || CASE WHEN v_speed_bonus > 0 THEN ' (+' || v_speed_bonus || ' speed bonus)' ELSE '' END
        ELSE 'Correct guess in multiplayer Guess Who' END)
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

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
$function$;

-- 4. Board RPC: return clues visible to the caller based on mode
CREATE OR REPLACE FUNCTION public.guess_who_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_match guess_who_matches;
  v_players jsonb;
  v_clues jsonb;
  v_answer jsonb := null;
  v_my_revealed int;
  v_visible int;
  v_total int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

  IF v_match.status = 'active' AND v_match.deadline_at IS NOT NULL AND now() > v_match.deadline_at THEN
    UPDATE guess_who_match_participants SET completed = true, status = 'finished', finished_at = now()
      WHERE match_id = p_match_id AND completed = false;
    UPDATE guess_who_matches SET status = 'finished', finished_at = now()
      WHERE id = p_match_id AND status = 'active'
      RETURNING * INTO v_match;
  END IF;

  v_total := jsonb_array_length(v_match.clues);

  -- In solo mode each player sees their own clue count. In shared mode use the match counter.
  IF v_match.clue_mode = 'solo' THEN
    SELECT clues_revealed INTO v_my_revealed
      FROM guess_who_match_participants
      WHERE match_id = p_match_id AND user_id = v_uid;
    IF v_my_revealed IS NULL THEN v_my_revealed := 1; END IF;
    -- If the round is over show everything so the answer/history make sense
    IF v_match.status = 'finished' THEN v_my_revealed := v_total; END IF;
    v_visible := LEAST(v_my_revealed, v_total);
  ELSE
    v_visible := LEAST(v_match.clues_revealed, v_total);
    IF v_match.status = 'finished' THEN v_visible := v_total; END IF;
  END IF;

  v_clues := '[]'::jsonb;
  IF v_visible > 0 THEN
    FOR i IN 0..(v_visible - 1) LOOP
      v_clues := v_clues || jsonb_build_array(v_match.clues -> i);
    END LOOP;
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v_players
  FROM (
    SELECT p.user_id, p.status, p.guess_count, p.completed, p.won, p.points_awarded,
      p.series_points, p.series_wins, p.joined_at, p.finished_at, p.eliminated,
      p.clues_revealed,
      CASE WHEN p.user_id = v_uid OR v_match.status = 'finished' THEN p.guesses ELSE '[]'::jsonb END AS guesses,
      s.full_name, s.role
    FROM guess_who_match_participants p
    LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
    WHERE p.match_id = p_match_id
    ORDER BY (p.series_points + coalesce(p.points_awarded, 0)) DESC, p.won DESC, p.guess_count ASC, p.joined_at
  ) x;

  IF v_match.status = 'finished' THEN
    SELECT jsonb_build_object('full_name', s.full_name, 'role', s.role, 'department', d.name, 'avatar_url', coalesce(up.avatar_url, ''))
      INTO v_answer
      FROM staff_members s
      LEFT JOIN departments d ON d.id = s.department_id
      LEFT JOIN user_profiles up ON up.user_id = s.auth_user_id
      WHERE s.id = v_match.staff_id;
  END IF;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id, 'code', v_match.code, 'status', v_match.status,
      'max_guesses', v_match.max_guesses, 'max_players', v_match.max_players,
      'host_user_id', v_match.host_user_id, 'winner_user_id', v_match.winner_user_id,
      'clues_revealed', v_visible, 'total_clues', v_total,
      'time_limit_seconds', v_match.time_limit_seconds, 'deadline_at', v_match.deadline_at,
      'started_at', v_match.started_at, 'finished_at', v_match.finished_at,
      'total_rounds', v_match.total_rounds, 'current_round', v_match.current_round,
      'clue_mode', v_match.clue_mode
    ),
    'clues', v_clues, 'players', v_players, 'answer', v_answer
  );
END;
$function$;

-- 5. Reset per-player clues on round reset / restart
CREATE OR REPLACE FUNCTION public.guess_who_match_next_round(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_match guess_who_matches;
  v_staff_id uuid;
  v_clues jsonb := '[]'::jsonb;
  v_deadline timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can advance'; END IF;
  IF v_match.status <> 'finished' THEN RAISE EXCEPTION 'round not finished'; END IF;
  IF v_match.current_round >= v_match.total_rounds THEN RAISE EXCEPTION 'series complete'; END IF;

  SELECT id INTO v_staff_id FROM staff_members
    WHERE is_active = true AND directory_visible = true AND id <> v_match.staff_id
    ORDER BY random() LIMIT 1;
  IF v_staff_id IS NULL THEN RAISE EXCEPTION 'no staff available'; END IF;

  v_clues := public._guess_who_build_clues(v_staff_id);

  UPDATE guess_who_match_participants
    SET series_points = series_points + coalesce(points_awarded, 0),
      series_wins = series_wins + CASE WHEN won THEN 1 ELSE 0 END,
      guesses = '[]'::jsonb,
      guess_count = 0,
      completed = eliminated,
      won = false,
      finished_at = CASE WHEN eliminated THEN now() ELSE NULL END,
      points_awarded = 0,
      clues_revealed = 1
    WHERE match_id = p_match_id;

  IF v_match.time_limit_seconds IS NOT NULL THEN
    v_deadline := now() + (v_match.time_limit_seconds || ' seconds')::interval;
  END IF;

  UPDATE guess_who_matches SET
    staff_id = v_staff_id,
    clues = v_clues,
    clues_revealed = 1,
    status = 'active',
    winner_user_id = NULL,
    started_at = now(),
    finished_at = NULL,
    deadline_at = v_deadline,
    current_round = current_round + 1
    WHERE id = p_match_id RETURNING * INTO v_match;

  RETURN jsonb_build_object(
    'current_round', v_match.current_round,
    'total_rounds', v_match.total_rounds,
    'deadline_at', v_match.deadline_at
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.guess_who_match_restart(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_match guess_who_matches;
  v_staff_id uuid;
  v_clues jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can restart'; END IF;
  IF v_match.status <> 'finished' THEN RAISE EXCEPTION 'can only restart a finished game'; END IF;

  SELECT id INTO v_staff_id FROM staff_members
    WHERE is_active = true AND directory_visible = true AND id <> v_match.staff_id
    ORDER BY random() LIMIT 1;
  IF v_staff_id IS NULL THEN RAISE EXCEPTION 'no staff available'; END IF;
  v_clues := public._guess_who_build_clues(v_staff_id);

  UPDATE guess_who_match_participants SET
    guesses = '[]'::jsonb,
    guess_count = 0,
    completed = false,
    won = false,
    points_awarded = 0,
    series_points = 0,
    series_wins = 0,
    finished_at = NULL,
    clues_revealed = 1,
    status = CASE WHEN status = 'left' THEN 'left' ELSE 'joined' END
    WHERE match_id = p_match_id;

  UPDATE guess_who_matches SET
    status = 'pending',
    staff_id = v_staff_id,
    clues = v_clues,
    clues_revealed = 1,
    current_round = 1,
    winner_user_id = NULL,
    started_at = NULL,
    finished_at = NULL,
    deadline_at = NULL
    WHERE id = p_match_id;

  RETURN jsonb_build_object('status', 'pending');
END;
$function$;

GRANT EXECUTE ON FUNCTION public.guess_who_match_submit(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.guess_who_match_board(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.guess_who_match_next_round(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.guess_who_match_restart(uuid) TO authenticated;