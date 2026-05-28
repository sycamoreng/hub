/*
  # Add server-side validation for dino runner scores

  1. New Function
    - `dino_submit_score(p_score, p_duration_ms)` - Validates score against duration,
      inserts into dino_runner_scores, and awards capped points

  2. Validation Rules
    - Score must be positive
    - Duration must be at least 2 seconds
    - Score cannot exceed theoretical max for the given duration
      (based on game physics: speed starts at 360 px/s, increases 12/s, score = distance/10)
    - Daily point cap of 100 for dino runs

  3. Important Notes
    - Direct inserts to dino_runner_scores still work via RLS but won't award points
    - Points are only awarded through this RPC with proper validation
    - Max ~20 points per run, capped at 100/day total
*/

CREATE OR REPLACE FUNCTION public.dino_submit_score(
  p_score int,
  p_duration_ms int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_duration_s numeric;
  v_max_score numeric;
  v_points int := 0;
  v_today_total int := 0;
  v_remaining int;
  v_daily_cap int := 100;
  v_prev_best int;
  v_is_pb boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF p_score <= 0 THEN
    RAISE EXCEPTION 'invalid score';
  END IF;

  IF p_duration_ms < 2000 THEN
    RAISE EXCEPTION 'duration too short';
  END IF;

  -- Validate score against duration
  -- Game physics: speed starts 360, increases ~12/s, score = cumulative_distance / 10
  -- Max theoretical score for given duration with generous tolerance (2x)
  v_duration_s := p_duration_ms::numeric / 1000.0;
  -- Integral of (360 + 12*t) from 0 to t = 360t + 6t^2, divided by 10
  v_max_score := ((360.0 * v_duration_s) + (6.0 * v_duration_s * v_duration_s)) / 10.0;
  -- Apply 2x tolerance for timing variations
  v_max_score := v_max_score * 2.0;

  IF p_score > v_max_score THEN
    RAISE EXCEPTION 'score exceeds maximum for duration';
  END IF;

  -- Insert score
  INSERT INTO dino_runner_scores (user_id, score, duration_ms)
  VALUES (v_uid, p_score, p_duration_ms);

  -- Check personal best
  SELECT COALESCE(MAX(score), 0) INTO v_prev_best
  FROM dino_runner_scores
  WHERE user_id = v_uid AND score < p_score;

  v_is_pb := p_score > v_prev_best;

  -- Calculate points (capped at 20 per run)
  v_points := LEAST(20, GREATEST(1, p_score / 100));

  -- Daily cap
  SELECT COALESCE(SUM(points), 0) INTO v_today_total
  FROM points_events
  WHERE user_id = v_uid
    AND event_kind = 'dino_run_completed'
    AND created_at >= date_trunc('day', now());

  v_remaining := GREATEST(0, v_daily_cap - v_today_total);
  v_points := LEAST(v_points, v_remaining);

  IF v_points > 0 THEN
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    VALUES (
      v_uid,
      'dino_run_completed',
      'dino_run',
      v_uid::text || '-' || extract(epoch from now())::text,
      v_points,
      'Sycamore Run score ' || p_score
    );
  END IF;

  RETURN jsonb_build_object(
    'score', p_score,
    'is_personal_best', v_is_pb,
    'points_awarded', v_points,
    'daily_remaining', GREATEST(0, v_remaining - v_points)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dino_submit_score(int, int) FROM public;
GRANT EXECUTE ON FUNCTION public.dino_submit_score(int, int) TO authenticated, service_role;
