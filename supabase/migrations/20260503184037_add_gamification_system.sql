/*
  # Gamification system: kudos, points, badges, daily spark

  1. New Tables
    - `kudos` — peer-to-peer recognition (from user → to user, with value tag and note)
    - `kudos_values` — configurable recognition tags (e.g. Teamwork, Excellence)
    - `points_events` — append-only ledger of every point-earning action
    - `badges` — catalog of badges with criteria
    - `user_badges` — per-user awarded badges
    - `daily_sparks` — rotating daily engagement cards (trivia / poll / guess-the-colleague)
    - `spark_responses` — user responses to daily sparks
    - `point_weights` — admin-editable weights per event kind

  2. Security
    - RLS enabled on all tables
    - Everyone authenticated can read kudos, badges, leaderboard views
    - Users can only insert kudos as themselves, insert spark_responses as themselves
    - Admins (gamification section) manage badges, values, weights, sparks
*/

create table if not exists kudos_values (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  label text not null,
  emoji text not null default '',
  color text not null default 'emerald',
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table kudos_values enable row level security;

drop policy if exists "Anyone authenticated can read values" on kudos_values;
create policy "Anyone authenticated can read values"
  on kudos_values for select to authenticated
  using (is_active = true or private.admin_can('gamification', 'read'));

drop policy if exists "Admin insert values" on kudos_values;
create policy "Admin insert values"
  on kudos_values for insert to authenticated
  with check (private.admin_can('gamification', 'manage'));

drop policy if exists "Admin update values" on kudos_values;
create policy "Admin update values"
  on kudos_values for update to authenticated
  using (private.admin_can('gamification', 'manage'))
  with check (private.admin_can('gamification', 'manage'));

drop policy if exists "Admin delete values" on kudos_values;
create policy "Admin delete values"
  on kudos_values for delete to authenticated
  using (private.admin_can('gamification', 'manage'));

create table if not exists kudos (
  id uuid primary key default gen_random_uuid(),
  from_user_id uuid not null references auth.users(id) on delete cascade,
  to_user_id uuid not null references auth.users(id) on delete cascade,
  value_code text not null default 'teamwork',
  message text not null default '',
  is_public boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists kudos_to_idx on kudos(to_user_id, created_at desc);
create index if not exists kudos_from_idx on kudos(from_user_id, created_at desc);

alter table kudos enable row level security;

drop policy if exists "Authenticated can read public kudos" on kudos;
create policy "Authenticated can read public kudos"
  on kudos for select to authenticated
  using (
    is_public = true
    or from_user_id = auth.uid()
    or to_user_id = auth.uid()
    or private.admin_can('gamification', 'read')
  );

drop policy if exists "Users can give kudos as themselves" on kudos;
create policy "Users can give kudos as themselves"
  on kudos for insert to authenticated
  with check (from_user_id = auth.uid() and from_user_id <> to_user_id);

drop policy if exists "Admin can delete kudos" on kudos;
create policy "Admin can delete kudos"
  on kudos for delete to authenticated
  using (from_user_id = auth.uid() or private.admin_can('gamification', 'manage'));

create table if not exists point_weights (
  id uuid primary key default gen_random_uuid(),
  event_kind text unique not null,
  label text not null,
  points int not null default 1,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table point_weights enable row level security;

drop policy if exists "Authenticated can read weights" on point_weights;
create policy "Authenticated can read weights"
  on point_weights for select to authenticated using (true);

drop policy if exists "Admin manage weights insert" on point_weights;
create policy "Admin manage weights insert"
  on point_weights for insert to authenticated
  with check (private.admin_can('gamification', 'manage'));

drop policy if exists "Admin manage weights update" on point_weights;
create policy "Admin manage weights update"
  on point_weights for update to authenticated
  using (private.admin_can('gamification', 'manage'))
  with check (private.admin_can('gamification', 'manage'));

drop policy if exists "Admin manage weights delete" on point_weights;
create policy "Admin manage weights delete"
  on point_weights for delete to authenticated
  using (private.admin_can('gamification', 'manage'));

create table if not exists points_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_kind text not null,
  points int not null default 0,
  ref_type text not null default '',
  ref_id text not null default '',
  note text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists points_events_user_idx on points_events(user_id, created_at desc);
create index if not exists points_events_kind_idx on points_events(event_kind, created_at desc);
create unique index if not exists points_events_dedupe_idx on points_events(user_id, event_kind, ref_type, ref_id)
  where ref_id <> '';

alter table points_events enable row level security;

drop policy if exists "Authenticated can read all points" on points_events;
create policy "Authenticated can read all points"
  on points_events for select to authenticated using (true);

drop policy if exists "Users can award points to self" on points_events;
create policy "Users can award points to self"
  on points_events for insert to authenticated
  with check (user_id = auth.uid() or private.admin_can('gamification', 'manage'));

drop policy if exists "Admin can delete points" on points_events;
create policy "Admin can delete points"
  on points_events for delete to authenticated
  using (private.admin_can('gamification', 'manage'));

create table if not exists badges (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  description text not null default '',
  emoji text not null default '',
  color text not null default 'emerald',
  threshold int not null default 1,
  metric text not null default 'points_total',
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

alter table badges enable row level security;

drop policy if exists "Authenticated can read badges" on badges;
create policy "Authenticated can read badges"
  on badges for select to authenticated using (true);

drop policy if exists "Admin manage badges insert" on badges;
create policy "Admin manage badges insert"
  on badges for insert to authenticated
  with check (private.admin_can('gamification', 'manage'));

drop policy if exists "Admin manage badges update" on badges;
create policy "Admin manage badges update"
  on badges for update to authenticated
  using (private.admin_can('gamification', 'manage'))
  with check (private.admin_can('gamification', 'manage'));

drop policy if exists "Admin manage badges delete" on badges;
create policy "Admin manage badges delete"
  on badges for delete to authenticated
  using (private.admin_can('gamification', 'manage'));

create table if not exists user_badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references badges(id) on delete cascade,
  awarded_at timestamptz not null default now(),
  unique(user_id, badge_id)
);

create index if not exists user_badges_user_idx on user_badges(user_id, awarded_at desc);

alter table user_badges enable row level security;

drop policy if exists "Authenticated can read user badges" on user_badges;
create policy "Authenticated can read user badges"
  on user_badges for select to authenticated using (true);

drop policy if exists "Users can award own badges" on user_badges;
create policy "Users can award own badges"
  on user_badges for insert to authenticated
  with check (user_id = auth.uid() or private.admin_can('gamification', 'manage'));

drop policy if exists "Admin delete user badges" on user_badges;
create policy "Admin delete user badges"
  on user_badges for delete to authenticated
  using (private.admin_can('gamification', 'manage'));

create table if not exists daily_sparks (
  id uuid primary key default gen_random_uuid(),
  active_on date not null,
  kind text not null default 'trivia',
  question text not null,
  options jsonb not null default '[]'::jsonb,
  correct_index int,
  points_award int not null default 5,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists daily_sparks_active_on_idx on daily_sparks(active_on);

alter table daily_sparks enable row level security;

drop policy if exists "Authenticated can read sparks" on daily_sparks;
create policy "Authenticated can read sparks"
  on daily_sparks for select to authenticated using (true);

drop policy if exists "Admin manage sparks insert" on daily_sparks;
create policy "Admin manage sparks insert"
  on daily_sparks for insert to authenticated
  with check (private.admin_can('gamification', 'manage'));

drop policy if exists "Admin manage sparks update" on daily_sparks;
create policy "Admin manage sparks update"
  on daily_sparks for update to authenticated
  using (private.admin_can('gamification', 'manage'))
  with check (private.admin_can('gamification', 'manage'));

drop policy if exists "Admin manage sparks delete" on daily_sparks;
create policy "Admin manage sparks delete"
  on daily_sparks for delete to authenticated
  using (private.admin_can('gamification', 'manage'));

create table if not exists spark_responses (
  id uuid primary key default gen_random_uuid(),
  spark_id uuid not null references daily_sparks(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  choice_index int not null,
  is_correct boolean not null default false,
  created_at timestamptz not null default now(),
  unique(spark_id, user_id)
);

create index if not exists spark_responses_spark_idx on spark_responses(spark_id);

alter table spark_responses enable row level security;

drop policy if exists "Authenticated can read responses" on spark_responses;
create policy "Authenticated can read responses"
  on spark_responses for select to authenticated using (true);

drop policy if exists "Users can respond as themselves" on spark_responses;
create policy "Users can respond as themselves"
  on spark_responses for insert to authenticated
  with check (user_id = auth.uid());

-- Seed default weights
insert into point_weights (event_kind, label, points) values
  ('post_created', 'Shared a post', 5),
  ('comment_posted', 'Commented on a post', 2),
  ('reaction_received', 'Received a reaction', 1),
  ('kudos_given', 'Gave kudos', 3),
  ('kudos_received', 'Received kudos', 8),
  ('onboarding_step_completed', 'Completed a learning step', 10),
  ('attendance_clock_in', 'Clocked in', 2),
  ('spark_correct', 'Correct Daily Spark', 5),
  ('spark_participated', 'Played Daily Spark', 1),
  ('profile_completed', 'Completed profile', 20)
on conflict (event_kind) do nothing;

insert into kudos_values (code, label, emoji, color, sort_order) values
  ('teamwork', 'Teamwork', '🤝', 'emerald', 1),
  ('excellence', 'Excellence', '⭐', 'amber', 2),
  ('innovation', 'Innovation', '💡', 'sky', 3),
  ('ownership', 'Ownership', '🎯', 'rose', 4),
  ('kindness', 'Kindness', '💚', 'leaf', 5),
  ('growth', 'Growth', '🌱', 'teal', 6)
on conflict (code) do nothing;

insert into badges (code, name, description, emoji, color, threshold, metric, sort_order) values
  ('first_post', 'First Post', 'Shared your first post', '✍️', 'sycamore', 1, 'posts_count', 1),
  ('conversationalist', 'Conversationalist', 'Left 10 comments', '💬', 'sky', 10, 'comments_count', 2),
  ('kudos_starter', 'Kudos Starter', 'Gave 5 kudos', '🤝', 'emerald', 5, 'kudos_given_count', 3),
  ('celebrated', 'Celebrated', 'Received 10 kudos', '🌟', 'amber', 10, 'kudos_received_count', 4),
  ('learner', 'Learner', 'Completed 3 learning steps', '📚', 'teal', 3, 'learning_count', 5),
  ('century', 'Century', 'Reached 100 points', '💯', 'rose', 100, 'points_total', 6),
  ('champion', 'Champion', 'Reached 500 points', '🏆', 'amber', 500, 'points_total', 7),
  ('spark_streak', 'Spark Streak', 'Answered 5 Daily Sparks correctly', '⚡', 'sycamore', 5, 'spark_correct_count', 8)
on conflict (code) do nothing;
