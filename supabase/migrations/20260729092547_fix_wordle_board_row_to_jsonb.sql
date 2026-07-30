/*
# Fix wordle_match_board function — replace row_to_jsonb with to_jsonb

The `wordle_match_board` RPC used `row_to_jsonb(x)` which does not exist in
PostgreSQL. The correct function is `to_jsonb(x)`. This caused the error
"function row_to_jsonb(record) does not exist" when calling the board endpoint.

1. Modified Functions
   - `wordle_match_board(uuid)` — replaced `row_to_jsonb(x)` with `to_jsonb(x)`.

2. Security
   - No changes to RLS or grants.
*/

CREATE OR REPLACE FUNCTION wordle_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match wordle_matches;
  v_players jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM wordle_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'match not found'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
    INTO v_players
    FROM (
      SELECT p.user_id,
             p.status,
             p.guess_count,
             p.completed,
             p.won,
             p.rank,
             p.joined_at,
             p.finished_at,
             p.results,
             CASE WHEN p.user_id = v_uid OR v_match.status = 'finished'
                  THEN to_jsonb(p.guesses)
                  ELSE '[]'::jsonb END AS guesses,
             s.full_name,
             s.role
      FROM wordle_match_participants p
      LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
      WHERE p.match_id = p_match_id
      ORDER BY (p.rank IS NULL), p.rank NULLS LAST, p.joined_at
    ) x;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id,
      'code', v_match.code,
      'status', v_match.status,
      'letter_count', v_match.letter_count,
      'max_guesses', v_match.max_guesses,
      'max_players', v_match.max_players,
      'host_user_id', v_match.host_user_id,
      'winner_user_id', v_match.winner_user_id,
      'started_at', v_match.started_at,
      'finished_at', v_match.finished_at,
      'target', CASE WHEN v_match.status = 'finished' THEN v_match.target_word ELSE NULL END
    ),
    'players', v_players
  );
END;
$$;
