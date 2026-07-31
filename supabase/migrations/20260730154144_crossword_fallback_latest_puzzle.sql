-- Make daily + match-create fall back to the latest available crossword puzzle
-- when today's has not yet been seeded, so the games never dead-end.

CREATE OR REPLACE FUNCTION public.crossword_daily_puzzle()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_puzzle crossword_puzzles;
v_attempt crossword_attempts;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_puzzle FROM crossword_puzzles WHERE puzzle_date = current_date;
IF NOT FOUND THEN
  SELECT * INTO v_puzzle FROM crossword_puzzles ORDER BY puzzle_date DESC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no puzzle available';
  END IF;
END IF;

SELECT * INTO v_attempt FROM crossword_attempts WHERE user_id = v_uid AND puzzle_id = v_puzzle.id;
IF NOT FOUND THEN
INSERT INTO crossword_attempts (user_id, puzzle_id) VALUES (v_uid, v_puzzle.id) RETURNING * INTO v_attempt;
END IF;

RETURN jsonb_build_object(
'puzzle_id', v_puzzle.id,
'puzzle_date', v_puzzle.puzzle_date,
'grid', v_puzzle.grid,
'clues_across', v_puzzle.clues_across,
'clues_down', v_puzzle.clues_down,
'attempt', jsonb_build_object(
'id', v_attempt.id,
'grid_state', v_attempt.grid_state,
'completed', v_attempt.completed,
'time_seconds', v_attempt.time_seconds
)
);
END;
$function$;

CREATE OR REPLACE FUNCTION public.crossword_match_create(p_time_limit integer DEFAULT NULL::integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_code text;
v_puzzle crossword_puzzles;
v_match crossword_matches;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
IF p_time_limit IS NOT NULL AND p_time_limit NOT IN (60, 90, 120, 180, 300) THEN p_time_limit := 120; END IF;
SELECT * INTO v_puzzle FROM crossword_puzzles WHERE puzzle_date = current_date;
IF NOT FOUND THEN
  SELECT * INTO v_puzzle FROM crossword_puzzles ORDER BY puzzle_date DESC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no puzzle available';
  END IF;
END IF;
LOOP
v_code := upper(substr(md5(random()::text), 1, 6));
EXIT WHEN NOT EXISTS (SELECT 1 FROM crossword_matches WHERE code = v_code);
END LOOP;
INSERT INTO crossword_matches (host_user_id, code, puzzle_id, time_limit_seconds)
VALUES (v_uid, v_code, v_puzzle.id, p_time_limit) RETURNING * INTO v_match;
RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status, 'time_limit_seconds', v_match.time_limit_seconds);
END;
$function$;
