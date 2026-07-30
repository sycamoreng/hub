CREATE OR REPLACE FUNCTION public.wordle_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
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
           CASE WHEN p.user_id = v_uid OR v_match.status = 'finished'
                THEN to_jsonb(p.guesses) ELSE '[]'::jsonb END AS guesses,
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