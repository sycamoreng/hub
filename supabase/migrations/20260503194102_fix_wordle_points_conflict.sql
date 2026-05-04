/*
  # Fix wordle_submit_guess ON CONFLICT error

  The `points_events` table has a partial unique index on
  (user_id, event_kind, ref_type, ref_id) WHERE ref_id <> '',
  which Postgres cannot infer in an ON CONFLICT clause without
  including the matching WHERE predicate. Rewriting the insert
  as a NOT EXISTS guard avoids the problem entirely.
*/

create or replace function public.wordle_submit_guess(p_guess text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_date date := (now() at time zone 'UTC')::date;
  v_max int;
  v_game wordle_games;
  v_guess text := lower(trim(p_guess));
  v_target text;
  v_row jsonb := '[]'::jsonb;
  v_counts jsonb := '{}'::jsonb;
  v_letter text;
  i int;
  v_won boolean := false;
  v_completed boolean;
  v_points int := 0;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select max_guesses into v_max from wordle_settings where id = 1;
  if v_max is null then v_max := 6; end if;

  select * into v_game from wordle_games where user_id = v_uid and puzzle_date = v_date for update;
  if not found then
    raise exception 'no active game';
  end if;
  if v_game.completed then
    raise exception 'game already completed';
  end if;
  if length(v_guess) <> v_game.letter_count then
    raise exception 'guess must be % letters', v_game.letter_count;
  end if;
  if v_guess !~ '^[a-z]+$' then
    raise exception 'letters only';
  end if;

  v_target := v_game.target_word;

  for i in 1..v_game.letter_count loop
    v_letter := substr(v_target, i, 1);
    if substr(v_guess, i, 1) <> v_letter then
      v_counts := jsonb_set(
        v_counts,
        array[v_letter],
        to_jsonb(coalesce((v_counts ->> v_letter)::int, 0) + 1),
        true
      );
    end if;
  end loop;

  for i in 1..v_game.letter_count loop
    v_letter := substr(v_guess, i, 1);
    if substr(v_target, i, 1) = v_letter then
      v_row := v_row || to_jsonb('hit'::text);
    elsif coalesce((v_counts ->> v_letter)::int, 0) > 0 then
      v_row := v_row || to_jsonb('near'::text);
      v_counts := jsonb_set(v_counts, array[v_letter], to_jsonb((v_counts ->> v_letter)::int - 1), true);
    else
      v_row := v_row || to_jsonb('miss'::text);
    end if;
  end loop;

  if v_guess = v_target then
    v_won := true;
  end if;

  v_game.guesses := array_append(v_game.guesses, v_guess);
  v_game.results := v_game.results || jsonb_build_array(v_row);
  v_completed := v_won or array_length(v_game.guesses, 1) >= v_max;

  update wordle_games
  set guesses = v_game.guesses,
      results = v_game.results,
      won = v_won,
      completed = v_completed,
      completed_at = case when v_completed then now() else completed_at end
  where id = v_game.id;

  if v_won then
    v_points := greatest(10, (v_max - array_length(v_game.guesses, 1) + 1) * 5);
    if not exists (
      select 1 from points_events
      where user_id = v_uid
        and event_kind = 'wordle_won'
        and ref_type = 'wordle'
        and ref_id = v_date::text
    ) then
      insert into points_events (user_id, event_kind, ref_type, ref_id, points, note)
      values (v_uid, 'wordle_won', 'wordle', v_date::text, v_points,
              'Solved in ' || array_length(v_game.guesses, 1) || ' guesses');
    end if;
  end if;

  return jsonb_build_object(
    'puzzle_date', v_game.puzzle_date,
    'letter_count', v_game.letter_count,
    'max_guesses', v_max,
    'guesses', to_jsonb(v_game.guesses),
    'results', v_game.results,
    'completed', v_completed,
    'won', v_won,
    'points_awarded', v_points,
    'target', case when v_completed then v_target else null end
  );
end;
$$;

revoke all on function public.wordle_submit_guess(text) from public;
grant execute on function public.wordle_submit_guess(text) to authenticated, service_role;
