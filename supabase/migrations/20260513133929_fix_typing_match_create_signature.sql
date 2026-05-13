/*
  # Fix typing_match_create signature

  Drops the legacy `typing_match_create(p_mode text, p_category_id uuid, p_max_players int, p_length_tier text)`
  function and recreates it with the multiplayer signature
  `typing_match_create(p_category_id uuid, p_prompt_id uuid, p_mode text)` used by the app.

  1. Changes
     - Drops legacy overload of public.typing_match_create
     - Recreates the new function with SECURITY DEFINER
  2. Security
     - REVOKE from PUBLIC, GRANT EXECUTE to authenticated only
*/

DROP FUNCTION IF EXISTS public.typing_match_create(text, uuid, integer, text);

CREATE OR REPLACE FUNCTION public.typing_match_create(
  p_category_id uuid,
  p_prompt_id uuid,
  p_mode text
)
RETURNS typing_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match typing_matches;
  v_text text;
  v_code text;
  v_attempt int := 0;
  v_duration int;
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_mode NOT IN ('timed_30s','timed_60s','timed_120s','sprint') THEN
    RAISE EXCEPTION 'invalid mode';
  END IF;
  v_duration := CASE p_mode
    WHEN 'timed_30s' THEN 30000
    WHEN 'timed_60s' THEN 60000
    WHEN 'timed_120s' THEN 120000
    ELSE 0
  END;

  IF p_prompt_id IS NOT NULL THEN
    SELECT text INTO v_text FROM typing_prompts WHERE id = p_prompt_id;
  END IF;
  IF v_text IS NULL THEN
    SELECT text INTO v_text FROM typing_prompts
    WHERE is_active
      AND (p_category_id IS NULL OR category_id = p_category_id)
    ORDER BY random() LIMIT 1;
  END IF;
  IF v_text IS NULL THEN
    RAISE EXCEPTION 'no prompts available';
  END IF;

  LOOP
    v_attempt := v_attempt + 1;
    v_code := '';
    FOR i IN 1..6 LOOP
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    END LOOP;
    BEGIN
      INSERT INTO typing_matches (host_user_id, code, category_id, prompt_id, prompt_text, mode, duration_ms)
      VALUES (v_uid, v_code, p_category_id, p_prompt_id, v_text, p_mode, v_duration)
      RETURNING * INTO v_match;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt > 6 THEN RAISE; END IF;
    END;
  END LOOP;

  INSERT INTO typing_match_participants (match_id, user_id, status, joined_at)
  VALUES (v_match.id, v_uid, 'joined', now());

  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.typing_match_create(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.typing_match_create(uuid, uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
