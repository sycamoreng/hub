/*
# Fix max_players constraint and add auto-finish on deadline expiry

1. Schema Changes
   - `wordle_matches`: Updated check constraint from max 25 to max 30 players.

2. Modified Functions
   - `wordle_match_board`: Now auto-finishes the match (sets status='finished', 
     marks all incomplete participants as finished) if the deadline has passed.
     This ensures the target word is revealed immediately when time expires.
   - `guess_who_match_board`: Same auto-finish on deadline expiry. Reveals the 
     mystery person's identity when time runs out.
   - `codebreaker_match_board`: Same auto-finish on deadline expiry. Reveals 
     the secret code when time runs out.

3. Important Notes
   - Previously, timed matches could remain in 'active' status after deadline 
     passed if no one submitted a guess. The answer reveal only triggered on 
     'finished' status, causing players to never see the answer.
   - Now, any call to the board RPC after deadline triggers the transition, 
     so the client refresh at countdown=0 gets the finished state with answers.
*/

ALTER TABLE wordle_matches DROP CONSTRAINT IF EXISTS wordle_matches_max_players_check;
ALTER TABLE wordle_matches ADD CONSTRAINT wordle_matches_max_players_check CHECK (max_players >= 2 AND max_players <= 30);

CREATE OR REPLACE FUNCTION public.wordle_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match wordle_matches;
  v_players jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

  IF v_match.status = 'active' AND v_match.deadline_at IS NOT NULL AND now() > v_match.deadline_at THEN
    UPDATE wordle_match_participants SET completed = true, status = 'finished', finished_at = now()
      WHERE match_id = p_match_id AND completed = false;
    UPDATE wordle_matches SET status = 'finished', finished_at = now()
      WHERE id = p_match_id AND status = 'active'
      RETURNING * INTO v_match;
  END IF;

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
      'target', CASE WHEN v_match.status = 'finished' THEN v_match.target_word ELSE NULL END
    ),
    'players', v_players
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.guess_who_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
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

  IF v_match.status = 'active' AND v_match.deadline_at IS NOT NULL AND now() > v_match.deadline_at THEN
    UPDATE guess_who_match_participants SET completed = true, status = 'finished', finished_at = now()
      WHERE match_id = p_match_id AND completed = false;
    UPDATE guess_who_matches SET status = 'finished', finished_at = now()
      WHERE id = p_match_id AND status = 'active'
      RETURNING * INTO v_match;
  END IF;

  v_clues := '[]'::jsonb;
  FOR i IN 0..(v_match.clues_revealed - 1) LOOP
    v_clues := v_clues || jsonb_build_array(v_match.clues -> i);
  END LOOP;

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

CREATE OR REPLACE FUNCTION public.codebreaker_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match codebreaker_matches;
  v_players jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM codebreaker_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

  IF v_match.status = 'active' AND v_match.deadline_at IS NOT NULL AND now() > v_match.deadline_at THEN
    UPDATE codebreaker_match_participants SET completed = true, status = 'finished', finished_at = now()
      WHERE match_id = p_match_id AND completed = false;
    UPDATE codebreaker_matches SET status = 'finished', finished_at = now()
      WHERE id = p_match_id AND status = 'active'
      RETURNING * INTO v_match;
  END IF;

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
