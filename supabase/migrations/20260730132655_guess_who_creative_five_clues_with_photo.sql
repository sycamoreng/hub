/*
Rework Guess Who multiplayer clues:
- 5 distinct clues (not lookalikes)
- Clue 1 uses gender + tenure (creative fallback if either missing)
- Clue 5 is a blurred avatar photo (avatar_url on the clue object)
- Applies to guess_who_match_create and guess_who_match_next_round
*/

CREATE OR REPLACE FUNCTION public._guess_who_build_clues(p_staff_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_staff staff_members;
  v_dept_name text;
  v_location_name text;
  v_city text;
  v_manager_name text;
  v_direct_reports int;
  v_pronoun text;
  v_they text;
  v_gender_word text;
  v_joined date;
  v_joined_label text;
  v_tenure_years numeric;
  v_avatar_url text;
  v_name_len int;
  v_role_word text;
  v_clue1 text;
  v_clue2 text;
  v_clue3 text;
  v_clue4 text;
  v_clue5 text;
BEGIN
  SELECT * INTO v_staff FROM staff_members WHERE id = p_staff_id;
  IF NOT FOUND THEN RETURN '[]'::jsonb; END IF;

  SELECT name INTO v_dept_name FROM departments WHERE id = v_staff.department_id;
  SELECT name, city INTO v_location_name, v_city FROM locations WHERE id = v_staff.location_id;
  SELECT full_name INTO v_manager_name FROM staff_members WHERE id = v_staff.manager_id;
  SELECT count(*) INTO v_direct_reports FROM staff_members WHERE manager_id = v_staff.id AND is_active;
  SELECT avatar_url INTO v_avatar_url FROM user_profiles WHERE user_id = v_staff.auth_user_id;

  v_pronoun := CASE WHEN lower(v_staff.gender) = 'female' THEN 'She'
                    WHEN lower(v_staff.gender) = 'male' THEN 'He'
                    ELSE 'They' END;
  v_they := CASE WHEN lower(v_staff.gender) = 'female' THEN 'her'
                 WHEN lower(v_staff.gender) = 'male' THEN 'him'
                 ELSE 'them' END;
  v_gender_word := CASE WHEN lower(v_staff.gender) = 'female' THEN 'woman'
                        WHEN lower(v_staff.gender) = 'male' THEN 'man'
                        ELSE NULL END;

  v_joined := coalesce(v_staff.joined_date, v_staff.created_at::date);
  IF v_joined IS NOT NULL THEN
    v_tenure_years := extract(year from age(current_date, v_joined));
    v_joined_label := trim(to_char(v_joined, 'Month YYYY'));
  END IF;

  v_name_len := char_length(regexp_replace(coalesce(v_staff.full_name, ''), '\s+', '', 'g'));

  -- Clue 1: creative identity mix (gender + tenure or fun teaser)
  IF v_gender_word IS NOT NULL AND v_joined_label IS NOT NULL THEN
    v_clue1 := 'A ' || v_gender_word || ' who joined the Sycamore family in ' || v_joined_label || '.';
  ELSIF v_gender_word IS NOT NULL THEN
    v_clue1 := 'A ' || v_gender_word || ' on the Sycamore team.';
  ELSIF v_joined_label IS NOT NULL THEN
    v_clue1 := 'This teammate joined the Sycamore family in ' || v_joined_label || '.';
  ELSE
    v_clue1 := v_pronoun || ' has been part of the Sycamore story for a while.';
  END IF;
  IF v_tenure_years IS NOT NULL AND v_tenure_years >= 3 THEN
    v_clue1 := v_clue1 || ' A veteran with ' || v_tenure_years::int || '+ years here.';
  END IF;

  -- Clue 2: department / team (distinct from location)
  IF v_dept_name IS NOT NULL THEN
    v_clue2 := v_pronoun || ' works inside the ' || v_dept_name || ' department.';
  ELSE
    v_clue2 := v_pronoun || ' floats across a few teams instead of belonging to one department.';
  END IF;

  -- Clue 3: role / seniority (distinct from department)
  IF v_staff.role IS NOT NULL AND v_staff.level IS NOT NULL THEN
    v_clue3 := 'Job title hint: a ' || lower(v_staff.level) || '-level ' || v_staff.role || '.';
  ELSIF v_staff.role IS NOT NULL THEN
    v_clue3 := v_pronoun || ' goes by the title of ' || v_staff.role || '.';
  ELSIF v_staff.level IS NOT NULL THEN
    v_clue3 := 'Seniority level: ' || v_staff.level || '.';
  ELSE
    IF v_direct_reports > 0 THEN
      v_clue3 := v_pronoun || ' manages ' || v_direct_reports || ' teammate' || CASE WHEN v_direct_reports > 1 THEN 's' ELSE '' END || '.';
    ELSE
      v_clue3 := v_pronoun || ' is an individual contributor doing solid work.';
    END IF;
  END IF;

  -- Clue 4: location + connections (distinct from department & role)
  IF v_location_name IS NOT NULL AND v_manager_name IS NOT NULL THEN
    v_clue4 := 'Based at the ' || v_location_name || CASE WHEN v_city IS NOT NULL THEN ' in ' || v_city ELSE '' END || ', reporting to ' || v_manager_name || '.';
  ELSIF v_location_name IS NOT NULL THEN
    v_clue4 := 'You will spot ' || v_they || ' at the ' || v_location_name || CASE WHEN v_city IS NOT NULL THEN ' (' || v_city || ')' ELSE '' END || '.';
  ELSIF v_manager_name IS NOT NULL THEN
    v_clue4 := v_pronoun || ' reports to ' || v_manager_name || '.';
  ELSIF v_direct_reports > 0 THEN
    v_clue4 := v_pronoun || ' looks after a team of ' || v_direct_reports || '.';
  ELSE
    v_clue4 := 'Fun fact: ' || v_pronoun || ' has ' || v_name_len || ' letters in their full name (spaces removed).';
  END IF;

  -- Clue 5: the blurred photo reveal
  IF v_avatar_url IS NOT NULL AND length(v_avatar_url) > 0 THEN
    v_clue5 := 'Here is a blurred photo. Take a good look before you guess!';
  ELSE
    v_clue5 := 'Last hint: think back on everyone you have crossed paths with lately.';
  END IF;

  RETURN jsonb_build_array(
    jsonb_build_object('category', 'identity', 'text', v_clue1),
    jsonb_build_object('category', 'team', 'text', v_clue2),
    jsonb_build_object('category', 'role', 'text', v_clue3),
    jsonb_build_object('category', 'location', 'text', v_clue4),
    jsonb_build_object('category', 'photo', 'text', v_clue5, 'avatar_url', coalesce(v_avatar_url, ''))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public._guess_who_build_clues(uuid) TO authenticated;

-- Refresh match_create to always generate our own 5-clue set
CREATE OR REPLACE FUNCTION public.guess_who_match_create(p_staff_id uuid DEFAULT NULL, p_time_limit int DEFAULT NULL)
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

  v_clues := public._guess_who_build_clues(v_staff_id);

  LOOP
    v_code := upper(substr(md5(random()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM guess_who_matches WHERE code = v_code);
  END LOOP;

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

GRANT EXECUTE ON FUNCTION public.guess_who_match_create(uuid, int) TO authenticated;

-- Refresh next_round to use the same builder
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

  v_clues := public._guess_who_build_clues(v_staff_id);

  UPDATE guess_who_match_participants
    SET series_points = series_points + coalesce(points_awarded, 0),
        series_wins = series_wins + CASE WHEN won THEN 1 ELSE 0 END,
        guesses = '[]'::jsonb,
        guess_count = 0,
        completed = false,
        won = false,
        finished_at = NULL,
        points_awarded = 0
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
$$;

GRANT EXECUTE ON FUNCTION public.guess_who_match_next_round(uuid) TO authenticated;
