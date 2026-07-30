CREATE OR REPLACE FUNCTION public.wordle_match_submit_guess(p_match_id uuid, p_guess text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
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
  v_new_guesses text[];
  v_new_results jsonb;
  v_new_count int;
  v_done boolean;
  v_elapsed_pct numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  v_g := lower(trim(p_guess));

  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'room not active'; END IF;

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

  IF length(v_g) <> v_match.letter_count THEN
    RAISE EXCEPTION 'guess must be % letters', v_match.letter_count;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM wordle_valid_guesses WHERE word = v_g) THEN
    RAISE EXCEPTION 'not a valid word';
  END IF;

  v_results := array_fill(''::text, ARRAY[v_match.letter_count]);
  FOR i IN 1..v_match.letter_count LOOP
    IF substr(v_g, i, 1) = substr(v_match.target_word, i, 1) THEN
      v_results[i] := 'hit';
    END IF;
  END LOOP;
  FOR i IN 1..v_match.letter_count LOOP
    IF v_results[i] = '' THEN
      DECLARE
        ch text := substr(v_g, i, 1);
        target_count int := 0;
        guess_hit_count int := 0;
        guess_near_before int := 0;
      BEGIN
        FOR j IN 1..v_match.letter_count LOOP
          IF substr(v_match.target_word, j, 1) = ch THEN target_count := target_count + 1; END IF;
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

  v_correct := v_g = v_match.target_word;

  v_new_guesses := coalesce(v_p.guesses, ARRAY[]::text[]) || v_g;
  v_new_results := coalesce(v_p.results, '[]'::jsonb) || jsonb_build_array(to_jsonb(v_results));
  v_new_count := array_length(v_new_guesses, 1);
  v_done := v_correct OR v_new_count >= v_match.max_guesses;

  IF v_correct AND v_match.winner_user_id IS NULL THEN
    v_first := true;
    v_points := GREATEST(5, 15 - v_p.guess_count * 3);
    IF v_match.deadline_at IS NOT NULL AND v_match.started_at IS NOT NULL AND v_match.time_limit_seconds IS NOT NULL AND v_match.time_limit_seconds > 0 THEN
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
    guesses = v_new_guesses,
    results = v_new_results,
    guess_count = v_new_count,
    won = v_correct,
    completed = v_done,
    status = CASE WHEN v_done THEN 'finished' ELSE status END,
    finished_at = CASE WHEN v_done THEN now() ELSE NULL END,
    points_awarded = v_points
  WHERE match_id = p_match_id AND user_id = v_uid;

  IF v_correct THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (v_uid, 'wordle_multi', 'wordle_match', v_match.id::text, v_points,
      CASE WHEN v_first THEN 'First to solve in multiplayer Wordle' || CASE WHEN v_speed_bonus > 0 THEN ' (+' || v_speed_bonus || ' speed bonus)' ELSE '' END
           ELSE 'Solved in multiplayer Wordle' END)
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

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
    'guesses', to_jsonb(v_new_guesses),
    'results', v_new_results,
    'completed', v_done,
    'won', v_correct,
    'points_awarded', v_points,
    'first_solver', v_first,
    'target', CASE WHEN v_done THEN v_match.target_word ELSE NULL END
  );
END;
$$;