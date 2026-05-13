/*
  # Fix typing match status values

  The deployed `typing_matches.status` constraint only permits
  `pending` / `active` / `finished` / `cancelled`, but
  `typing_match_start` was checking for `lobby` and writing `running`.
  Calling Start would always raise either "match cannot be started" or a
  check-constraint violation. This migration realigns the function to the
  table's allowed values.

  1. Changes
     - `typing_match_start` now requires `status = 'pending'` and writes
       `status = 'active'` plus `started_at = now()`.

  2. Safety
     - Function-only update; no data mutated.
*/

CREATE OR REPLACE FUNCTION public.typing_match_start(p_match_id uuid)
RETURNS typing_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match typing_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM typing_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start' USING ERRCODE='42501'; END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'match cannot be started'; END IF;

  UPDATE typing_matches SET status = 'active', started_at = now() WHERE id = p_match_id RETURNING * INTO v_match;
  RETURN v_match;
END;
$$;

GRANT EXECUTE ON FUNCTION public.typing_match_start(uuid) TO authenticated;
