/*
# Increase wordle multiplayer room cap to 25 players

Previously rooms were capped at 6 players. This raises the limit to 25 so
that larger group races are possible (e.g. team bonding sessions, department
challenges).

1. Modified Tables
- `wordle_matches`: change CHECK constraint on `max_players` from 2-6 to 2-25.

2. Modified Functions
- `wordle_match_create`: update validation check from 6 to 25.

3. Notes
- Existing rooms below 6 are unaffected. New rooms can be created with up to 25.
*/

ALTER TABLE wordle_matches DROP CONSTRAINT IF EXISTS wordle_matches_max_players_check;
ALTER TABLE wordle_matches ADD CONSTRAINT wordle_matches_max_players_check CHECK (max_players BETWEEN 2 AND 25);

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

  INSERT INTO wordle_match_participants (match_id, user_id, status)
  VALUES (v_match.id, v_uid, 'joined');

  RETURN v_match;
END;
$$;
