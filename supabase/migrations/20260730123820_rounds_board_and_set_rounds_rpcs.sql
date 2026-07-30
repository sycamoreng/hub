-- Update board RPCs to expose rounds + series info
CREATE OR REPLACE FUNCTION public.wordle_match_board(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
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
           p.series_points, p.series_wins,
           CASE WHEN p.user_id = v_uid OR v_match.status = 'finished' THEN to_jsonb(p.guesses) ELSE '[]'::jsonb END AS guesses,
           CASE WHEN p.user_id = v_uid OR v_match.status = 'finished' THEN p.results ELSE '[]'::jsonb END AS results,
           s.full_name, s.role
    FROM wordle_match_participants p
    LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
    WHERE p.match_id = p_match_id
    ORDER BY (p.series_points + coalesce(p.points_awarded, 0)) DESC, p.won DESC, p.guess_count ASC, p.joined_at
  ) x;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id, 'code', v_match.code, 'status', v_match.status,
      'letter_count', v_match.letter_count, 'max_guesses', v_match.max_guesses,
      'max_players', v_match.max_players, 'host_user_id', v_match.host_user_id,
      'winner_user_id', v_match.winner_user_id, 'started_at', v_match.started_at,
      'finished_at', v_match.finished_at, 'time_limit_seconds', v_match.time_limit_seconds,
      'deadline_at', v_match.deadline_at,
      'total_rounds', v_match.total_rounds, 'current_round', v_match.current_round,
      'target', CASE WHEN v_match.status = 'finished' THEN v_match.target_word ELSE NULL END
    ),
    'players', v_players
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.guess_who_match_board(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
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
    SELECT p.user_id, p.status, p.guess_count, p.completed, p.won, p.points_awarded,
           p.series_points, p.series_wins, p.joined_at, p.finished_at,
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
      'clues_revealed', v_match.clues_revealed, 'total_clues', jsonb_array_length(v_match.clues),
      'time_limit_seconds', v_match.time_limit_seconds, 'deadline_at', v_match.deadline_at,
      'started_at', v_match.started_at, 'finished_at', v_match.finished_at,
      'total_rounds', v_match.total_rounds, 'current_round', v_match.current_round
    ),
    'clues', v_clues, 'players', v_players, 'answer', v_answer
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.dino_match_board(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match dino_matches;
  v_players jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM dino_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v_players
  FROM (
    SELECT p.user_id, p.status, p.score, p.duration_ms, p.points_awarded,
           p.series_points, p.series_wins, p.joined_at, p.finished_at,
           s.full_name, s.role
    FROM dino_match_participants p
    LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
    WHERE p.match_id = p_match_id
    ORDER BY (p.series_points + coalesce(p.points_awarded, 0)) DESC, p.score DESC, p.duration_ms DESC, p.joined_at
  ) x;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id, 'code', v_match.code, 'status', v_match.status,
      'max_players', v_match.max_players, 'host_user_id', v_match.host_user_id,
      'time_limit_seconds', v_match.time_limit_seconds, 'deadline_at', v_match.deadline_at,
      'started_at', v_match.started_at, 'finished_at', v_match.finished_at,
      'total_rounds', v_match.total_rounds, 'current_round', v_match.current_round
    ),
    'players', v_players
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.codebreaker_match_board(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
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
           p.series_points, p.series_wins, p.joined_at, p.finished_at,
           CASE WHEN p.user_id = v_uid OR v_match.status = 'finished' THEN p.guesses ELSE '[]'::jsonb END AS guesses,
           CASE WHEN p.user_id = v_uid OR v_match.status = 'finished' THEN p.feedback ELSE '[]'::jsonb END AS feedback,
           s.full_name, s.role
    FROM codebreaker_match_participants p
    LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
    WHERE p.match_id = p_match_id
    ORDER BY (p.series_points + coalesce(p.points_awarded, 0)) DESC, p.won DESC, p.guess_count ASC, p.joined_at
  ) x;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id, 'code', v_match.code, 'status', v_match.status,
      'max_guesses', v_match.max_guesses, 'max_players', v_match.max_players,
      'host_user_id', v_match.host_user_id, 'winner_user_id', v_match.winner_user_id,
      'time_limit_seconds', v_match.time_limit_seconds, 'deadline_at', v_match.deadline_at,
      'started_at', v_match.started_at, 'finished_at', v_match.finished_at,
      'total_rounds', v_match.total_rounds, 'current_round', v_match.current_round,
      'secret_code', CASE WHEN v_match.status = 'finished' THEN to_jsonb(v_match.secret_code) ELSE NULL END
    ),
    'players', v_players
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.crossword_match_board(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
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
           p.time_seconds, p.points_awarded,
           p.series_points, p.series_wins, p.joined_at, p.finished_at,
           s.full_name, s.role
    FROM crossword_match_participants p
    LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
    WHERE p.match_id = p_match_id
    ORDER BY (p.series_points + coalesce(p.points_awarded, 0)) DESC, p.won DESC, p.time_seconds ASC, p.joined_at
  ) x;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id, 'code', v_match.code, 'status', v_match.status,
      'max_players', v_match.max_players, 'host_user_id', v_match.host_user_id,
      'winner_user_id', v_match.winner_user_id, 'time_limit_seconds', v_match.time_limit_seconds,
      'deadline_at', v_match.deadline_at, 'started_at', v_match.started_at,
      'finished_at', v_match.finished_at,
      'total_rounds', v_match.total_rounds, 'current_round', v_match.current_round
    ),
    'puzzle', jsonb_build_object('grid', v_puzzle.grid, 'clues_across', v_puzzle.clues_across, 'clues_down', v_puzzle.clues_down),
    'players', v_players
  );
END;
$$;

-- Set-rounds RPC (host only, before or during a series)
CREATE OR REPLACE FUNCTION public.wordle_match_set_rounds(p_match_id uuid, p_total_rounds int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_total_rounds < 1 OR p_total_rounds > 10 THEN RAISE EXCEPTION 'rounds must be 1-10'; END IF;
  UPDATE wordle_matches SET total_rounds = GREATEST(p_total_rounds, current_round)
    WHERE id = p_match_id AND host_user_id = v_uid AND status IN ('pending','active','finished');
  IF NOT FOUND THEN RAISE EXCEPTION 'cannot update rounds'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.guess_who_match_set_rounds(p_match_id uuid, p_total_rounds int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_total_rounds < 1 OR p_total_rounds > 10 THEN RAISE EXCEPTION 'rounds must be 1-10'; END IF;
  UPDATE guess_who_matches SET total_rounds = GREATEST(p_total_rounds, current_round)
    WHERE id = p_match_id AND host_user_id = v_uid AND status IN ('pending','active','finished');
  IF NOT FOUND THEN RAISE EXCEPTION 'cannot update rounds'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.dino_match_set_rounds(p_match_id uuid, p_total_rounds int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_total_rounds < 1 OR p_total_rounds > 10 THEN RAISE EXCEPTION 'rounds must be 1-10'; END IF;
  UPDATE dino_matches SET total_rounds = GREATEST(p_total_rounds, current_round)
    WHERE id = p_match_id AND host_user_id = v_uid AND status IN ('pending','active','finished');
  IF NOT FOUND THEN RAISE EXCEPTION 'cannot update rounds'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.codebreaker_match_set_rounds(p_match_id uuid, p_total_rounds int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_total_rounds < 1 OR p_total_rounds > 10 THEN RAISE EXCEPTION 'rounds must be 1-10'; END IF;
  UPDATE codebreaker_matches SET total_rounds = GREATEST(p_total_rounds, current_round)
    WHERE id = p_match_id AND host_user_id = v_uid AND status IN ('pending','active','finished');
  IF NOT FOUND THEN RAISE EXCEPTION 'cannot update rounds'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.crossword_match_set_rounds(p_match_id uuid, p_total_rounds int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_total_rounds < 1 OR p_total_rounds > 10 THEN RAISE EXCEPTION 'rounds must be 1-10'; END IF;
  UPDATE crossword_matches SET total_rounds = GREATEST(p_total_rounds, current_round)
    WHERE id = p_match_id AND host_user_id = v_uid AND status IN ('pending','active','finished');
  IF NOT FOUND THEN RAISE EXCEPTION 'cannot update rounds'; END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.wordle_match_set_rounds(uuid,int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.guess_who_match_set_rounds(uuid,int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dino_match_set_rounds(uuid,int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.codebreaker_match_set_rounds(uuid,int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.crossword_match_set_rounds(uuid,int) TO authenticated;