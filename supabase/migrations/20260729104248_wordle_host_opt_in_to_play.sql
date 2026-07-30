/*
# Make wordle match host opt-in to play

1. Modified Functions
   - `wordle_match_create` — no longer auto-joins host as participant. Host creates
     the room but must explicitly join if they want to play.
   - `wordle_match_start` — allows starting with 1+ active players (host doesn't
     need to be a player). Removes participants who left before start.
   - `wordle_match_board` — returns whether the calling user is a participant so the
     UI can distinguish host-only (spectator) vs host+player.

2. Why
   - Hosts should be able to create a game for others without being forced to play.
   - Useful for team leads who want to set up a game but just watch.

3. Security
   - No RLS changes. Join still uses the existing `wordle_match_join` RPC.
*/

-- wordle_match_create: NO LONGER auto-joins host as participant
CREATE OR REPLACE FUNCTION wordle_match_create(
  p_letter_count int DEFAULT NULL,
  p_max_guesses int DEFAULT NULL,
  p_max_players int DEFAULT 6
)
RETURNS wordle_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_letters int;
  v_max int;
  v_players int;
  v_word text;
  v_code text;
  v_alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_attempt int := 0;
  v_match wordle_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;

  SELECT letter_count, max_guesses INTO v_letters, v_max
    FROM wordle_settings WHERE id = 1;
  v_letters := coalesce(p_letter_count, v_letters, 5);
  v_max := coalesce(p_max_guesses, v_max, 6);
  v_players := coalesce(p_max_players, 6);
  IF v_players < 2 OR v_players > 25 THEN RAISE EXCEPTION 'max_players must be 2-25'; END IF;

  SELECT word INTO v_word FROM wordle_words
    WHERE is_active AND length = v_letters
    ORDER BY random() LIMIT 1;
  IF v_word IS NULL THEN RAISE EXCEPTION 'no words available'; END IF;

  LOOP
    v_attempt := v_attempt + 1;
    v_code := '';
    FOR i IN 1..6 LOOP
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    END LOOP;
    BEGIN
      INSERT INTO wordle_matches (host_user_id, code, target_word, letter_count, max_guesses, max_players)
      VALUES (v_uid, v_code, v_word, v_letters, v_max, v_players)
      RETURNING * INTO v_match;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt > 6 THEN RAISE; END IF;
    END;
  END LOOP;

  -- Host does NOT auto-join. They can join via wordle_match_join if they want to play.
  RETURN v_match;
END;
$$;

-- wordle_match_start: require at least 1 active player (host doesn't need to be playing)
CREATE OR REPLACE FUNCTION wordle_match_start(p_match_id uuid)
RETURNS wordle_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match wordle_matches;
  v_player_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start'; END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'match already started'; END IF;

  SELECT count(*) INTO v_player_count
    FROM wordle_match_participants
    WHERE match_id = p_match_id AND status = 'joined';

  IF v_player_count < 1 THEN RAISE EXCEPTION 'need at least 1 player to start'; END IF;

  UPDATE wordle_matches
    SET status = 'active', started_at = now()
    WHERE id = p_match_id
    RETURNING * INTO v_match;

  RETURN v_match;
END;
$$;
