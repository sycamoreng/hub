/*
  # Add Guess Who game RPCs and complete RLS policies

  1. Security
    - Add RLS policies for guess_who_attempts (select, insert, update own records)

  2. Functions
    - `guess_who_start_or_get()` - returns today's puzzle state for the user
    - `guess_who_submit(first_name, last_name)` - submit a guess
    - `guess_who_use_photo_hint()` - request blurred photo (costs points)

  3. Notes
    - Uses existing `guess_who_puzzles` and `guess_who_attempts` tables
    - Points awarded via `points_events` table
    - Max 5 guesses per day
    - Photo hint costs 3 points off final score
*/

-- RLS policies for attempts
CREATE POLICY "Users view own guess_who attempts"
  ON public.guess_who_attempts
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users insert own guess_who attempts"
  ON public.guess_who_attempts
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own guess_who attempts"
  ON public.guess_who_attempts
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- RPC: Start or get today's puzzle
CREATE OR REPLACE FUNCTION public.guess_who_start_or_get()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_puzzle guess_who_puzzles;
  v_attempt guess_who_attempts;
  v_result jsonb;
BEGIN
  -- Get today's puzzle
  SELECT * INTO v_puzzle FROM guess_who_puzzles WHERE puzzle_date = CURRENT_DATE;
  IF v_puzzle.id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_puzzle');
  END IF;

  -- Get or create user's attempt
  SELECT * INTO v_attempt FROM guess_who_attempts
    WHERE puzzle_id = v_puzzle.id AND user_id = auth.uid();

  IF v_attempt.id IS NULL THEN
    INSERT INTO guess_who_attempts (puzzle_id, user_id)
    VALUES (v_puzzle.id, auth.uid())
    RETURNING * INTO v_attempt;
  END IF;

  v_result := jsonb_build_object(
    'status', 'active',
    'puzzle_date', v_puzzle.puzzle_date,
    'clues', v_puzzle.clues,
    'has_avatar', v_puzzle.has_avatar,
    'guesses', v_attempt.guesses,
    'used_photo_hint', v_attempt.revealed_photo,
    'completed', v_attempt.completed,
    'won', v_attempt.won,
    'points_awarded', v_attempt.points_awarded,
    'max_guesses', 5
  );

  -- If completed, reveal the answer
  IF v_attempt.completed THEN
    v_result := v_result || jsonb_build_object(
      'answer', (SELECT jsonb_build_object(
        'full_name', s.full_name,
        'role', s.role,
        'department', d.name,
        'avatar_url', COALESCE(up.avatar_url, '')
      ) FROM staff_members s
        LEFT JOIN departments d ON d.id = s.department_id
        LEFT JOIN user_profiles up ON up.user_id = s.auth_user_id
        WHERE s.id = v_puzzle.staff_id)
    );
  END IF;

  RETURN v_result;
END;
$$;

-- RPC: Submit a guess
CREATE OR REPLACE FUNCTION public.guess_who_submit(p_first_name text, p_last_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_puzzle guess_who_puzzles;
  v_attempt guess_who_attempts;
  v_target staff_members;
  v_correct boolean;
  v_guesses jsonb;
  v_points integer := 0;
  v_max_guesses integer := 5;
  v_target_first text;
  v_target_last text;
  v_name_parts text[];
BEGIN
  -- Get today's puzzle
  SELECT * INTO v_puzzle FROM guess_who_puzzles WHERE puzzle_date = CURRENT_DATE;
  IF v_puzzle.id IS NULL THEN
    RETURN jsonb_build_object('error', 'No puzzle today');
  END IF;

  -- Get user's attempt
  SELECT * INTO v_attempt FROM guess_who_attempts
    WHERE puzzle_id = v_puzzle.id AND user_id = auth.uid();
  IF v_attempt IS NULL THEN
    RETURN jsonb_build_object('error', 'Start the game first');
  END IF;
  IF v_attempt.completed THEN
    RETURN jsonb_build_object('error', 'Already completed');
  END IF;

  -- Check guess count
  IF jsonb_array_length(v_attempt.guesses) >= v_max_guesses THEN
    RETURN jsonb_build_object('error', 'No more guesses');
  END IF;

  -- Get target staff
  SELECT * INTO v_target FROM staff_members WHERE id = v_puzzle.staff_id;

  -- Parse first and last name from full_name
  v_name_parts := string_to_array(trim(v_target.full_name), ' ');
  v_target_first := v_name_parts[1];
  v_target_last := v_name_parts[array_length(v_name_parts, 1)];

  -- Check if guess is correct (case-insensitive)
  v_correct := (
    lower(trim(p_first_name)) = lower(v_target_first)
    AND lower(trim(p_last_name)) = lower(v_target_last)
  );

  -- Append guess
  v_guesses := v_attempt.guesses || jsonb_build_array(jsonb_build_object(
    'first_name', trim(p_first_name),
    'last_name', trim(p_last_name),
    'correct', v_correct
  ));

  -- Calculate points if correct
  IF v_correct THEN
    v_points := GREATEST(2, 10 - ((jsonb_array_length(v_guesses) - 1) * 2));
    IF v_attempt.revealed_photo THEN
      v_points := GREATEST(1, v_points - 3);
    END IF;

    UPDATE guess_who_attempts SET
      guesses = v_guesses,
      completed = true,
      won = true,
      points_awarded = v_points,
      updated_at = now()
    WHERE id = v_attempt.id;

    -- Award points
    INSERT INTO public.points_events (user_id, event_kind, points, ref_type, ref_id, note)
    VALUES (auth.uid(), 'guess_who_correct', v_points, 'guess_who_puzzle', v_puzzle.id::text, 'Guessed correctly in Guess Who')
    ON CONFLICT DO NOTHING;

  ELSIF jsonb_array_length(v_guesses) >= v_max_guesses THEN
    UPDATE guess_who_attempts SET
      guesses = v_guesses,
      completed = true,
      won = false,
      updated_at = now()
    WHERE id = v_attempt.id;
  ELSE
    UPDATE guess_who_attempts SET guesses = v_guesses, updated_at = now() WHERE id = v_attempt.id;
  END IF;

  RETURN public.guess_who_start_or_get();
END;
$$;

-- RPC: Use photo hint
CREATE OR REPLACE FUNCTION public.guess_who_use_photo_hint()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_puzzle guess_who_puzzles;
  v_attempt guess_who_attempts;
  v_avatar text;
BEGIN
  SELECT * INTO v_puzzle FROM guess_who_puzzles WHERE puzzle_date = CURRENT_DATE;
  IF v_puzzle.id IS NULL THEN
    RETURN jsonb_build_object('error', 'No puzzle today');
  END IF;

  SELECT * INTO v_attempt FROM guess_who_attempts
    WHERE puzzle_id = v_puzzle.id AND user_id = auth.uid();
  IF v_attempt IS NULL OR v_attempt.completed THEN
    RETURN jsonb_build_object('error', 'Cannot use hint now');
  END IF;

  IF NOT v_puzzle.has_avatar THEN
    RETURN jsonb_build_object('error', 'no_photo', 'message', 'No photo available for today''s mystery person');
  END IF;

  -- Mark hint as used
  UPDATE guess_who_attempts SET revealed_photo = true, updated_at = now() WHERE id = v_attempt.id;

  -- Get avatar URL
  SELECT COALESCE(up.avatar_url, '') INTO v_avatar
  FROM staff_members s
  LEFT JOIN user_profiles up ON up.user_id = s.auth_user_id
  WHERE s.id = v_puzzle.staff_id;

  RETURN jsonb_build_object(
    'photo_url', v_avatar,
    'used_photo_hint', true
  );
END;
$$;

-- Grant execute to authenticated
GRANT EXECUTE ON FUNCTION public.guess_who_start_or_get() TO authenticated;
GRANT EXECUTE ON FUNCTION public.guess_who_submit(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.guess_who_use_photo_hint() TO authenticated;
