/*
  # Wordle-style daily word game

  1. New Tables
    - `wordle_settings` — single-row config (letter_count, max_guesses). Admin editable.
    - `wordle_words` — pool of valid target words grouped by length. Seeded automatically.
    - `wordle_games` — per-user, per-date game state with guess list and outcome.

  2. Automation
    - `wordle_pick_word(p_date, p_length)` — deterministic daily word selection (date-seeded hash).
    - `wordle_start_or_get(p_date)` — creates or returns today's game for the caller.
    - `wordle_submit_guess(p_guess)` — validates length, appends guess, scores against target, awards points.

  3. Security
    - RLS on all tables. Users can only read/modify their own games.
    - Settings and word pool readable by authenticated; manage requires gamification admin.
    - Target word is never exposed to client until game completes — only via RPC that returns tile results.
*/

create table if not exists wordle_settings (
  id int primary key default 1,
  letter_count int not null default 5,
  max_guesses int not null default 6,
  updated_at timestamptz not null default now(),
  check (letter_count between 3 and 9),
  check (max_guesses between 3 and 10)
);

insert into wordle_settings (id, letter_count, max_guesses) values (1, 5, 6)
on conflict (id) do nothing;

alter table wordle_settings enable row level security;

drop policy if exists "Authenticated can read settings" on wordle_settings;
create policy "Authenticated can read settings"
  on wordle_settings for select to authenticated using (true);

drop policy if exists "Admin update settings" on wordle_settings;
create policy "Admin update settings"
  on wordle_settings for update to authenticated
  using (private.admin_can('gamification', 'manage'))
  with check (private.admin_can('gamification', 'manage'));

create table if not exists wordle_words (
  word text primary key,
  length int not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists wordle_words_length_idx on wordle_words(length) where is_active;

alter table wordle_words enable row level security;

drop policy if exists "Authenticated can read words" on wordle_words;
create policy "Authenticated can read words"
  on wordle_words for select to authenticated using (true);

drop policy if exists "Admin insert words" on wordle_words;
create policy "Admin insert words"
  on wordle_words for insert to authenticated
  with check (private.admin_can('gamification', 'manage'));

drop policy if exists "Admin update words" on wordle_words;
create policy "Admin update words"
  on wordle_words for update to authenticated
  using (private.admin_can('gamification', 'manage'))
  with check (private.admin_can('gamification', 'manage'));

drop policy if exists "Admin delete words" on wordle_words;
create policy "Admin delete words"
  on wordle_words for delete to authenticated
  using (private.admin_can('gamification', 'manage'));

create table if not exists wordle_games (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  puzzle_date date not null,
  letter_count int not null,
  target_word text not null,
  guesses text[] not null default '{}',
  results jsonb not null default '[]'::jsonb,
  completed boolean not null default false,
  won boolean not null default false,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(user_id, puzzle_date)
);

create index if not exists wordle_games_user_idx on wordle_games(user_id, puzzle_date desc);
create index if not exists wordle_games_date_idx on wordle_games(puzzle_date);

alter table wordle_games enable row level security;

drop policy if exists "Users read own games" on wordle_games;
create policy "Users read own games"
  on wordle_games for select to authenticated
  using (user_id = auth.uid() or private.admin_can('gamification', 'read'));

-- Inserts/updates happen via SECURITY DEFINER RPCs only. No direct insert policy.

create or replace function public.wordle_pick_word(p_date date, p_length int)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_word text;
  v_count bigint;
  v_idx bigint;
begin
  select count(*) into v_count from wordle_words where length = p_length and is_active;
  if v_count = 0 then
    return null;
  end if;
  v_idx := ('x' || substr(md5('sycamore-wordle-' || p_date::text || '-' || p_length::text), 1, 8))::bit(32)::bigint;
  v_idx := (v_idx % v_count + v_count) % v_count;
  select word into v_word
  from wordle_words
  where length = p_length and is_active
  order by word
  offset v_idx
  limit 1;
  return v_word;
end;
$$;

revoke all on function public.wordle_pick_word(date, int) from public;
grant execute on function public.wordle_pick_word(date, int) to authenticated, service_role;

create or replace function public.wordle_start_or_get()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_date date := (now() at time zone 'UTC')::date;
  v_len int;
  v_max int;
  v_word text;
  v_game wordle_games;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select letter_count, max_guesses into v_len, v_max from wordle_settings where id = 1;
  if v_len is null then v_len := 5; end if;
  if v_max is null then v_max := 6; end if;

  select * into v_game from wordle_games where user_id = v_uid and puzzle_date = v_date;
  if not found then
    v_word := public.wordle_pick_word(v_date, v_len);
    if v_word is null then
      raise exception 'no words available for length %', v_len;
    end if;
    insert into wordle_games (user_id, puzzle_date, letter_count, target_word)
    values (v_uid, v_date, v_len, v_word)
    returning * into v_game;
  end if;

  return jsonb_build_object(
    'puzzle_date', v_game.puzzle_date,
    'letter_count', v_game.letter_count,
    'max_guesses', v_max,
    'guesses', to_jsonb(v_game.guesses),
    'results', v_game.results,
    'completed', v_game.completed,
    'won', v_game.won,
    'target', case when v_game.completed then v_game.target_word else null end
  );
end;
$$;

revoke all on function public.wordle_start_or_get() from public;
grant execute on function public.wordle_start_or_get() to authenticated, service_role;

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

  -- First pass: count remaining letters for yellow scoring (skip exact matches)
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

  -- Second pass: build result row
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
    insert into points_events (user_id, event_kind, ref_type, ref_id, points, note)
    values (v_uid, 'wordle_won', 'wordle', v_date::text, v_points, 'Solved in ' || array_length(v_game.guesses, 1) || ' guesses')
    on conflict (user_id, event_kind, ref_type, ref_id) do nothing;
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

-- Seed a point weight so admin can tune later (separate from RPC-embedded scoring)
insert into point_weights (event_kind, label, points)
values ('wordle_won', 'Solved daily Wordle', 20)
on conflict (event_kind) do nothing;
