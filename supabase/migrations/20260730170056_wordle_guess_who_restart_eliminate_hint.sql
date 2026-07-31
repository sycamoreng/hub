-- Add eliminated flag to both games' participant tables
ALTER TABLE wordle_match_participants ADD COLUMN IF NOT EXISTS eliminated boolean NOT NULL DEFAULT false;
ALTER TABLE guess_who_match_participants ADD COLUMN IF NOT EXISTS eliminated boolean NOT NULL DEFAULT false;

-- ============ WORDLE ============

CREATE OR REPLACE FUNCTION public.wordle_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
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
p.series_points, p.series_wins, p.eliminated,
CASE WHEN p.user_id = v_uid OR v_match.status = 'finished' THEN to_jsonb(p.guesses) ELSE '[]'::jsonb END AS guesses,
CASE WHEN p.user_id = v_uid OR v_match.status = 'finished' THEN p.results ELSE '[]'::jsonb END AS results,
s.full_name, s.role
FROM wordle_match_participants p
LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
WHERE p.match_id = p_match_id
ORDER BY (p.series_points + coalesce(p.points_awarded, 0)) DESC, p.won DESC, p.guess_count ASC, p.joined_at
) x;

RETURN jsonb_build_object(
'match', jsonb_build_object(
'id', v_match.id, 'code', v_match.code, 'status', v_match.status,
'letter_count', v_match.letter_count, 'max_guesses', v_match.max_guesses,
'max_players', v_match.max_players, 'host_user_id', v_match.host_user_id,
'winner_user_id', v_match.winner_user_id, 'started_at', v_match.started_at,
'finished_at', v_match.finished_at, 'time_limit_seconds', v_match.time_limit_seconds,
'deadline_at', v_match.deadline_at,
'total_rounds', v_match.total_rounds, 'current_round', v_match.current_round,
'target', CASE WHEN v_match.status = 'finished' THEN v_match.target_word ELSE NULL END
),
'players', v_players
);
END;
$function$;

-- Modify start to auto-complete eliminated players
CREATE OR REPLACE FUNCTION public.wordle_match_start(p_match_id uuid)
RETURNS wordle_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_match wordle_matches;
v_count int;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id FOR UPDATE;
IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start'; END IF;
IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'already started'; END IF;

DELETE FROM wordle_match_participants WHERE match_id = p_match_id AND status = 'left';

SELECT count(*) INTO v_count FROM wordle_match_participants
WHERE match_id = p_match_id AND status = 'joined' AND NOT eliminated;
IF v_count < 1 THEN RAISE EXCEPTION 'need at least 1 active player'; END IF;

UPDATE wordle_match_participants SET completed = true, finished_at = now()
WHERE match_id = p_match_id AND eliminated;

UPDATE wordle_matches SET
status = 'active',
started_at = now(),
deadline_at = CASE WHEN time_limit_seconds IS NOT NULL THEN now() + (time_limit_seconds || ' seconds')::interval ELSE NULL END
WHERE id = p_match_id RETURNING * INTO v_match;

RETURN v_match;
END;
$function$;

-- Modify next_round to skip eliminated
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
winner_user_id = NULL,
started_at = now(),
finished_at = NULL,
deadline_at = v_deadline
WHERE id = p_match_id
RETURNING * INTO v_match;

RETURN jsonb_build_object('current_round', v_match.current_round, 'total_rounds', v_match.total_rounds, 'deadline_at', v_match.deadline_at);
END;
$function$;

-- Toggle-eliminated (host only, only between rounds)
CREATE OR REPLACE FUNCTION public.wordle_match_toggle_eliminated(p_match_id uuid, p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_match wordle_matches;
v_new boolean;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id;
IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can change players'; END IF;
IF v_match.status NOT IN ('pending','finished') THEN RAISE EXCEPTION 'can only change between rounds'; END IF;
UPDATE wordle_match_participants
SET eliminated = NOT eliminated
WHERE match_id = p_match_id AND user_id = p_user_id
RETURNING eliminated INTO v_new;
IF v_new IS NULL THEN RAISE EXCEPTION 'player not in room'; END IF;
RETURN jsonb_build_object('user_id', p_user_id, 'eliminated', v_new);
END;
$function$;

-- Restart the whole series in the same room
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
current_round = 1,
winner_user_id = NULL,
started_at = NULL,
finished_at = NULL,
deadline_at = NULL
WHERE id = p_match_id;

RETURN jsonb_build_object('status', 'pending');
END;
$function$;

-- Vague hint: a random letter that appears in the word
CREATE OR REPLACE FUNCTION public.wordle_match_hint(p_match_id uuid)
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
RETURN jsonb_build_object('hint', 'The word contains the letter ' || v_letter);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.wordle_match_toggle_eliminated(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wordle_match_restart(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.wordle_match_hint(uuid) TO authenticated;

-- ============ GUESS WHO ============

CREATE OR REPLACE FUNCTION public.guess_who_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_match guess_who_matches;
v_players jsonb;
v_clues jsonb;
v_answer jsonb := null;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id;
IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

IF v_match.status = 'active' AND v_match.deadline_at IS NOT NULL AND now() > v_match.deadline_at THEN
UPDATE guess_who_match_participants SET completed = true, status = 'finished', finished_at = now()
WHERE match_id = p_match_id AND completed = false;
UPDATE guess_who_matches SET status = 'finished', finished_at = now()
WHERE id = p_match_id AND status = 'active'
RETURNING * INTO v_match;
END IF;

v_clues := '[]'::jsonb;
FOR i IN 0..(v_match.clues_revealed - 1) LOOP
v_clues := v_clues || jsonb_build_array(v_match.clues -> i);
END LOOP;

SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v_players
FROM (
SELECT p.user_id, p.status, p.guess_count, p.completed, p.won, p.points_awarded,
p.series_points, p.series_wins, p.joined_at, p.finished_at, p.eliminated,
CASE WHEN p.user_id = v_uid OR v_match.status = 'finished' THEN p.guesses ELSE '[]'::jsonb END AS guesses,
s.full_name, s.role
FROM guess_who_match_participants p
LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
WHERE p.match_id = p_match_id
ORDER BY (p.series_points + coalesce(p.points_awarded, 0)) DESC, p.won DESC, p.guess_count ASC, p.joined_at
) x;

IF v_match.status = 'finished' THEN
SELECT jsonb_build_object('full_name', s.full_name, 'role', s.role, 'department', d.name, 'avatar_url', coalesce(up.avatar_url, ''))
INTO v_answer
FROM staff_members s
LEFT JOIN departments d ON d.id = s.department_id
LEFT JOIN user_profiles up ON up.user_id = s.auth_user_id
WHERE s.id = v_match.staff_id;
END IF;

RETURN jsonb_build_object(
'match', jsonb_build_object(
'id', v_match.id, 'code', v_match.code, 'status', v_match.status,
'max_guesses', v_match.max_guesses, 'max_players', v_match.max_players,
'host_user_id', v_match.host_user_id, 'winner_user_id', v_match.winner_user_id,
'clues_revealed', v_match.clues_revealed, 'total_clues', jsonb_array_length(v_match.clues),
'time_limit_seconds', v_match.time_limit_seconds, 'deadline_at', v_match.deadline_at,
'started_at', v_match.started_at, 'finished_at', v_match.finished_at,
'total_rounds', v_match.total_rounds, 'current_round', v_match.current_round
),
'clues', v_clues, 'players', v_players, 'answer', v_answer
);
END;
$function$;

CREATE OR REPLACE FUNCTION public.guess_who_match_start(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_match guess_who_matches;
v_count int;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id FOR UPDATE;
IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start'; END IF;
IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'already started'; END IF;

SELECT count(*) INTO v_count FROM guess_who_match_participants
WHERE match_id = p_match_id AND status = 'joined' AND NOT eliminated;
IF v_count < 1 THEN RAISE EXCEPTION 'need at least 1 active player'; END IF;

UPDATE guess_who_match_participants SET completed = true, finished_at = now()
WHERE match_id = p_match_id AND eliminated;

UPDATE guess_who_matches SET
status = 'active',
started_at = now(),
deadline_at = CASE WHEN time_limit_seconds IS NOT NULL THEN now() + (time_limit_seconds || ' seconds')::interval ELSE NULL END
WHERE id = p_match_id RETURNING * INTO v_match;

RETURN jsonb_build_object('id', v_match.id, 'status', v_match.status, 'deadline_at', v_match.deadline_at);
END;
$function$;

CREATE OR REPLACE FUNCTION public.guess_who_match_next_round(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
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
completed = eliminated,
won = false,
finished_at = CASE WHEN eliminated THEN now() ELSE NULL END,
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
$function$;

CREATE OR REPLACE FUNCTION public.guess_who_match_toggle_eliminated(p_match_id uuid, p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_match guess_who_matches;
v_new boolean;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id;
IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can change players'; END IF;
IF v_match.status NOT IN ('pending','finished') THEN RAISE EXCEPTION 'can only change between rounds'; END IF;
UPDATE guess_who_match_participants
SET eliminated = NOT eliminated
WHERE match_id = p_match_id AND user_id = p_user_id
RETURNING eliminated INTO v_new;
IF v_new IS NULL THEN RAISE EXCEPTION 'player not in room'; END IF;
RETURN jsonb_build_object('user_id', p_user_id, 'eliminated', v_new);
END;
$function$;

CREATE OR REPLACE FUNCTION public.guess_who_match_restart(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
v_uid uuid := auth.uid();
v_match guess_who_matches;
v_staff_id uuid;
v_clues jsonb;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id FOR UPDATE;
IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can restart'; END IF;
IF v_match.status <> 'finished' THEN RAISE EXCEPTION 'can only restart a finished game'; END IF;

SELECT id INTO v_staff_id FROM staff_members
WHERE is_active = true AND directory_visible = true AND id <> v_match.staff_id
ORDER BY random() LIMIT 1;
IF v_staff_id IS NULL THEN RAISE EXCEPTION 'no staff available'; END IF;
v_clues := public._guess_who_build_clues(v_staff_id);

UPDATE guess_who_match_participants SET
guesses = '[]'::jsonb,
guess_count = 0,
completed = false,
won = false,
points_awarded = 0,
series_points = 0,
series_wins = 0,
finished_at = NULL,
status = CASE WHEN status = 'left' THEN 'left' ELSE 'joined' END
WHERE match_id = p_match_id;

UPDATE guess_who_matches SET
status = 'pending',
staff_id = v_staff_id,
clues = v_clues,
clues_revealed = 1,
current_round = 1,
winner_user_id = NULL,
started_at = NULL,
finished_at = NULL,
deadline_at = NULL
WHERE id = p_match_id;

RETURN jsonb_build_object('status', 'pending');
END;
$function$;

CREATE OR REPLACE FUNCTION public.guess_who_match_hint(p_match_id uuid)
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
v_last text;
v_initial text;
BEGIN
IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
SELECT * INTO v_match FROM guess_who_matches WHERE id = p_match_id;
IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
IF v_match.status <> 'active' THEN RAISE EXCEPTION 'not active'; END IF;
SELECT * INTO v_part FROM guess_who_match_participants WHERE match_id = p_match_id AND user_id = v_uid;
IF NOT FOUND OR v_part.status = 'left' OR v_part.eliminated THEN RAISE EXCEPTION 'not participating'; END IF;

SELECT full_name INTO v_name FROM staff_members WHERE id = v_match.staff_id;
IF v_name IS NULL THEN RAISE EXCEPTION 'no target'; END IF;
v_last := split_part(trim(v_name), ' ', -1);
IF v_last IS NULL OR length(v_last) = 0 THEN v_last := v_name; END IF;
v_initial := upper(substr(v_last, 1, 1));
RETURN jsonb_build_object('hint', 'Their last name starts with ' || v_initial);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.guess_who_match_toggle_eliminated(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.guess_who_match_restart(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.guess_who_match_hint(uuid) TO authenticated;
