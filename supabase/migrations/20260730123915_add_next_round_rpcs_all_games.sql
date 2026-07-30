-- Wordle next round
CREATE OR REPLACE FUNCTION public.wordle_match_next_round(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match wordle_matches;
  v_word text;
  v_deadline timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can advance'; END IF;
  IF v_match.status <> 'finished' THEN RAISE EXCEPTION 'round not finished'; END IF;
  IF v_match.current_round >= v_match.total_rounds THEN RAISE EXCEPTION 'series complete'; END IF;

  SELECT word INTO v_word FROM wordle_words
    WHERE length(word) = v_match.letter_count AND word <> v_match.target_word
    ORDER BY random() LIMIT 1;
  IF v_word IS NULL THEN RAISE EXCEPTION 'no word available'; END IF;

  UPDATE wordle_match_participants
    SET series_points = series_points + coalesce(points_awarded, 0),
        series_wins = series_wins + CASE WHEN won THEN 1 ELSE 0 END,
        guesses = ARRAY[]::text[],
        results = '[]'::jsonb,
        guess_count = 0,
        completed = false,
        won = false,
        points_awarded = 0,
        finished_at = NULL,
        status = CASE WHEN status = 'left' THEN 'left' ELSE 'joined' END
  WHERE match_id = p_match_id;

  IF v_match.time_limit_seconds IS NOT NULL AND v_match.time_limit_seconds > 0 THEN
    v_deadline := now() + (v_match.time_limit_seconds || ' seconds')::interval;
  END IF;

  UPDATE wordle_matches SET
    current_round = current_round + 1,
    status = 'active',
    target_word = v_word,
    winner_user_id = NULL,
    started_at = now(),
    finished_at = NULL,
    deadline_at = v_deadline
  WHERE id = p_match_id
  RETURNING * INTO v_match;

  RETURN jsonb_build_object('current_round', v_match.current_round, 'total_rounds', v_match.total_rounds, 'deadline_at', v_match.deadline_at);
END;
$$;

-- Guess Who next round
CREATE OR REPLACE FUNCTION public.guess_who_match_next_round(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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

  SELECT gp.clues INTO v_clues FROM guess_who_puzzles gp WHERE gp.staff_id = v_staff_id ORDER BY gp.puzzle_date DESC LIMIT 1;
  IF v_clues IS NULL OR jsonb_array_length(v_clues) = 0 THEN
    v_clues := jsonb_build_array(
      jsonb_build_object('category', 'role', 'text', (SELECT 'Works as ' || coalesce(role, 'a team member') FROM staff_members WHERE id = v_staff_id)),
      jsonb_build_object('category', 'team', 'text', (SELECT 'In the ' || coalesce(d.name, 'company') || ' department' FROM staff_members s LEFT JOIN departments d ON d.id = s.department_id WHERE s.id = v_staff_id)),
      jsonb_build_object('category', 'tenure', 'text', (SELECT 'Joined in ' || to_char(coalesce(joined_date, created_at), 'Month YYYY') FROM staff_members WHERE id = v_staff_id))
    );
  END IF;

  UPDATE guess_who_match_participants
    SET series_points = series_points + coalesce(points_awarded, 0),
        series_wins = series_wins + CASE WHEN won THEN 1 ELSE 0 END,
        guesses = '[]'::jsonb,
        guess_count = 0,
        completed = false,
        won = false,
        points_awarded = 0,
        finished_at = NULL,
        status = CASE WHEN status = 'left' THEN 'left' ELSE 'joined' END
  WHERE match_id = p_match_id;

  IF v_match.time_limit_seconds IS NOT NULL AND v_match.time_limit_seconds > 0 THEN
    v_deadline := now() + (v_match.time_limit_seconds || ' seconds')::interval;
  END IF;

  UPDATE guess_who_matches SET
    current_round = current_round + 1,
    status = 'active',
    staff_id = v_staff_id,
    clues = v_clues,
    clues_revealed = 1,
    winner_user_id = NULL,
    started_at = now(),
    finished_at = NULL,
    deadline_at = v_deadline
  WHERE id = p_match_id
  RETURNING * INTO v_match;

  RETURN jsonb_build_object('current_round', v_match.current_round, 'total_rounds', v_match.total_rounds, 'deadline_at', v_match.deadline_at);
END;
$$;

-- Dino next round
CREATE OR REPLACE FUNCTION public.dino_match_next_round(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match dino_matches;
  v_deadline timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM dino_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can advance'; END IF;
  IF v_match.status <> 'finished' THEN RAISE EXCEPTION 'round not finished'; END IF;
  IF v_match.current_round >= v_match.total_rounds THEN RAISE EXCEPTION 'series complete'; END IF;

  UPDATE dino_match_participants
    SET series_points = series_points + coalesce(points_awarded, 0),
        series_wins = series_wins + CASE WHEN status = 'crashed' AND score = (SELECT MAX(score) FROM dino_match_participants WHERE match_id = p_match_id AND status <> 'left') THEN 1 ELSE 0 END,
        score = 0,
        duration_ms = 0,
        points_awarded = 0,
        finished_at = NULL,
        status = CASE WHEN status = 'left' THEN 'left' ELSE 'playing' END
  WHERE match_id = p_match_id;

  IF v_match.time_limit_seconds IS NOT NULL AND v_match.time_limit_seconds > 0 THEN
    v_deadline := now() + (v_match.time_limit_seconds || ' seconds')::interval;
  END IF;

  UPDATE dino_matches SET
    current_round = current_round + 1,
    status = 'active',
    started_at = now(),
    finished_at = NULL,
    deadline_at = v_deadline
  WHERE id = p_match_id
  RETURNING * INTO v_match;

  RETURN jsonb_build_object('current_round', v_match.current_round, 'total_rounds', v_match.total_rounds, 'deadline_at', v_match.deadline_at);
END;
$$;

-- Codebreaker next round
CREATE OR REPLACE FUNCTION public.codebreaker_match_next_round(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match codebreaker_matches;
  v_deadline timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM codebreaker_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can advance'; END IF;
  IF v_match.status <> 'finished' THEN RAISE EXCEPTION 'round not finished'; END IF;
  IF v_match.current_round >= v_match.total_rounds THEN RAISE EXCEPTION 'series complete'; END IF;

  UPDATE codebreaker_match_participants
    SET series_points = series_points + coalesce(points_awarded, 0),
        series_wins = series_wins + CASE WHEN won THEN 1 ELSE 0 END,
        guesses = '[]'::jsonb,
        feedback = '[]'::jsonb,
        guess_count = 0,
        completed = false,
        won = false,
        points_awarded = 0,
        finished_at = NULL,
        status = CASE WHEN status = 'left' THEN 'left' ELSE 'joined' END
  WHERE match_id = p_match_id;

  IF v_match.time_limit_seconds IS NOT NULL AND v_match.time_limit_seconds > 0 THEN
    v_deadline := now() + (v_match.time_limit_seconds || ' seconds')::interval;
  END IF;

  UPDATE codebreaker_matches SET
    current_round = current_round + 1,
    status = 'active',
    secret_code = private.codebreaker_random_code(),
    winner_user_id = NULL,
    started_at = now(),
    finished_at = NULL,
    deadline_at = v_deadline
  WHERE id = p_match_id
  RETURNING * INTO v_match;

  RETURN jsonb_build_object('current_round', v_match.current_round, 'total_rounds', v_match.total_rounds, 'deadline_at', v_match.deadline_at);
END;
$$;

-- Crossword next round
CREATE OR REPLACE FUNCTION public.crossword_match_next_round(p_match_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match crossword_matches;
  v_puzzle_id uuid;
  v_total int;
  v_deadline timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM crossword_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can advance'; END IF;
  IF v_match.status <> 'finished' THEN RAISE EXCEPTION 'round not finished'; END IF;
  IF v_match.current_round >= v_match.total_rounds THEN RAISE EXCEPTION 'series complete'; END IF;

  SELECT id INTO v_puzzle_id FROM crossword_puzzles
    WHERE id <> v_match.puzzle_id
    ORDER BY random() LIMIT 1;
  IF v_puzzle_id IS NULL THEN v_puzzle_id := v_match.puzzle_id; END IF;

  SELECT count(*) INTO v_total FROM (
    SELECT 1 FROM crossword_puzzles p,
      jsonb_array_elements(p.grid) WITH ORDINALITY AS r(row_val, rn),
      jsonb_array_elements(r.row_val) WITH ORDINALITY AS c(cell_val, cn)
    WHERE p.id = v_puzzle_id AND c.cell_val <> 'null'::jsonb AND c.cell_val::text <> 'null'
  ) sub;

  UPDATE crossword_match_participants
    SET series_points = series_points + coalesce(points_awarded, 0),
        series_wins = series_wins + CASE WHEN won THEN 1 ELSE 0 END,
        cells_filled = 0,
        total_cells = v_total,
        completed = false,
        won = false,
        time_seconds = 0,
        points_awarded = 0,
        finished_at = NULL,
        status = CASE WHEN status = 'left' THEN 'left' ELSE 'playing' END
  WHERE match_id = p_match_id;

  IF v_match.time_limit_seconds IS NOT NULL AND v_match.time_limit_seconds > 0 THEN
    v_deadline := now() + (v_match.time_limit_seconds || ' seconds')::interval;
  END IF;

  UPDATE crossword_matches SET
    current_round = current_round + 1,
    status = 'active',
    puzzle_id = v_puzzle_id,
    winner_user_id = NULL,
    started_at = now(),
    finished_at = NULL,
    deadline_at = v_deadline
  WHERE id = p_match_id
  RETURNING * INTO v_match;

  RETURN jsonb_build_object('current_round', v_match.current_round, 'total_rounds', v_match.total_rounds, 'deadline_at', v_match.deadline_at);
END;
$$;

GRANT EXECUTE ON FUNCTION public.wordle_match_next_round(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.guess_who_match_next_round(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dino_match_next_round(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.codebreaker_match_next_round(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.crossword_match_next_round(uuid) TO authenticated;