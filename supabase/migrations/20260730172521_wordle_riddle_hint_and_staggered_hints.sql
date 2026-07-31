-- Cache the AI-generated riddle per wordle round
ALTER TABLE wordle_matches ADD COLUMN IF NOT EXISTS hint_riddle text;

-- Clear the riddle when the round advances or the game restarts
CREATE OR REPLACE FUNCTION public.wordle_match_next_round(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
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
completed = eliminated,
won = false,
points_awarded = 0,
finished_at = CASE WHEN eliminated THEN now() ELSE NULL END,
status = CASE WHEN status = 'left' THEN 'left' ELSE 'joined' END
WHERE match_id = p_match_id;

IF v_match.time_limit_seconds IS NOT NULL AND v_match.time_limit_seconds > 0 THEN
v_deadline := now() + (v_match.time_limit_seconds || ' seconds')::interval;
END IF;

UPDATE wordle_matches SET
current_round = current_round + 1,
status = 'active',
target_word = v_word,
hint_riddle = NULL,
winner_user_id = NULL,
started_at = now(),
finished_at = NULL,
deadline_at = v_deadline
WHERE id = p_match_id
RETURNING * INTO v_match;

RETURN jsonb_build_object('current_round', v_match.current_round, 'total_rounds', v_match.total_rounds, 'deadline_at', v_match.deadline_at);
END;
$function$;

CREATE OR REPLACE FUNCTION public.wordle_match_restart(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_match wordle_matches;
v_word text;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id FOR UPDATE;
IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can restart'; END IF;
IF v_match.status <> 'finished' THEN RAISE EXCEPTION 'can only restart a finished game'; END IF;

SELECT word INTO v_word FROM wordle_words
WHERE length(word) = v_match.letter_count AND word <> v_match.target_word
ORDER BY random() LIMIT 1;
IF v_word IS NULL THEN RAISE EXCEPTION 'no word available'; END IF;

UPDATE wordle_match_participants SET
guesses = ARRAY[]::text[],
results = '[]'::jsonb,
guess_count = 0,
completed = false,
won = false,
points_awarded = 0,
series_points = 0,
series_wins = 0,
finished_at = NULL,
status = CASE WHEN status = 'left' THEN 'left' ELSE 'joined' END
WHERE match_id = p_match_id;

UPDATE wordle_matches SET
status = 'pending',
target_word = v_word,
hint_riddle = NULL,
current_round = 1,
winner_user_id = NULL,
started_at = NULL,
finished_at = NULL,
deadline_at = NULL
WHERE id = p_match_id;

RETURN jsonb_build_object('status', 'pending');
END;
$function$;

-- Rename the existing single-letter hint into a level-specific RPC, so we have a clean
-- two-tier hint system: level 1 = riddle (fetched via edge function), level 2 = a letter.
-- We keep the old signature as a thin wrapper so any lingering callers still work.
CREATE OR REPLACE FUNCTION public.wordle_match_hint_letter(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_match wordle_matches;
v_part wordle_match_participants;
v_letter text;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id;
IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
IF v_match.status <> 'active' THEN RAISE EXCEPTION 'not active'; END IF;
SELECT * INTO v_part FROM wordle_match_participants WHERE match_id = p_match_id AND user_id = v_uid;
IF NOT FOUND OR v_part.status = 'left' OR v_part.eliminated THEN RAISE EXCEPTION 'not participating'; END IF;
v_letter := upper(substr(v_match.target_word, floor(random() * length(v_match.target_word))::int + 1, 1));
RETURN jsonb_build_object('hint', 'The word contains the letter ' || v_letter, 'level', 2);
END;
$function$;

CREATE OR REPLACE FUNCTION public.wordle_match_hint(p_match_id uuid)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
SELECT public.wordle_match_hint_letter(p_match_id);
$function$;

GRANT EXECUTE ON FUNCTION public.wordle_match_hint_letter(uuid) TO authenticated;

-- Guess Who: split into level 1 (first name initial) and level 2 (last name initial)
DROP FUNCTION IF EXISTS public.guess_who_match_hint(uuid);

CREATE OR REPLACE FUNCTION public.guess_who_match_hint(p_match_id uuid, p_level int DEFAULT 2)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_match guess_who_matches;
v_part guess_who_match_participants;
v_name text;
v_first text;
v_last text;
v_initial text;
v_message text;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id;
IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
IF v_match.status <> 'active' THEN RAISE EXCEPTION 'not active'; END IF;
SELECT * INTO v_part FROM guess_who_match_participants WHERE match_id = p_match_id AND user_id = v_uid;
IF NOT FOUND OR v_part.status = 'left' OR v_part.eliminated THEN RAISE EXCEPTION 'not participating'; END IF;

SELECT full_name INTO v_name FROM staff_members WHERE id = v_match.staff_id;
IF v_name IS NULL THEN RAISE EXCEPTION 'no target'; END IF;

v_first := split_part(trim(v_name), ' ', 1);
v_last := split_part(trim(v_name), ' ', -1);
IF v_last IS NULL OR length(v_last) = 0 THEN v_last := v_name; END IF;
IF v_first IS NULL OR length(v_first) = 0 THEN v_first := v_name; END IF;

IF p_level = 1 THEN
v_initial := upper(substr(v_first, 1, 1));
v_message := 'Their first name starts with ' || v_initial;
ELSE
v_initial := upper(substr(v_last, 1, 1));
v_message := 'Their last name starts with ' || v_initial;
END IF;

RETURN jsonb_build_object('hint', v_message, 'level', p_level);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.guess_who_match_hint(uuid, int) TO authenticated;
