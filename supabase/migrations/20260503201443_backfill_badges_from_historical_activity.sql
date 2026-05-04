/*
  # Backfill badges from historical activity

  ## Summary
  After backfilling historical points, users who already crossed badge
  thresholds should receive those badges (and their bonus leaderboard
  points). This migration awards any missing badges based on current
  metric values, then writes matching `points_events` rows so the
  leaderboard reflects the bonuses.

  ## Supported metrics
  posts_count, comments_count, kudos_given_count, kudos_received_count,
  learning_count, spark_correct_count, points_total.

  ## Safety
  - Uses the unique(user_id, badge_id) on `user_badges` — ON CONFLICT DO NOTHING.
  - Only writes points_events when the user_badges row is newly inserted.
*/

with candidates as (
  -- posts_count
  select p.author_id as user_id, b.id as badge_id, b.name, b.points_award
  from badges b
  join posts p on b.metric = 'posts_count' and p.author_id is not null
  where b.is_active
  group by p.author_id, b.id, b.name, b.points_award, b.threshold
  having count(*) >= b.threshold

  union
  -- comments_count
  select c.user_id, b.id, b.name, b.points_award
  from badges b
  join comments c on b.metric = 'comments_count' and c.user_id is not null
  where b.is_active
  group by c.user_id, b.id, b.name, b.points_award, b.threshold
  having count(*) >= b.threshold

  union
  -- kudos_given_count
  select k.from_user_id, b.id, b.name, b.points_award
  from badges b
  join kudos k on b.metric = 'kudos_given_count' and k.from_user_id is not null
  where b.is_active
  group by k.from_user_id, b.id, b.name, b.points_award, b.threshold
  having count(*) >= b.threshold

  union
  -- kudos_received_count
  select k.to_user_id, b.id, b.name, b.points_award
  from badges b
  join kudos k on b.metric = 'kudos_received_count' and k.to_user_id is not null
  where b.is_active
  group by k.to_user_id, b.id, b.name, b.points_award, b.threshold
  having count(*) >= b.threshold

  union
  -- learning_count
  select op.user_id, b.id, b.name, b.points_award
  from badges b
  join onboarding_progress op on b.metric = 'learning_count'
    and op.user_id is not null and op.completed_at is not null
  where b.is_active
  group by op.user_id, b.id, b.name, b.points_award, b.threshold
  having count(*) >= b.threshold

  union
  -- spark_correct_count
  select sr.user_id, b.id, b.name, b.points_award
  from badges b
  join spark_responses sr on b.metric = 'spark_correct_count'
    and sr.user_id is not null and sr.is_correct
  where b.is_active
  group by sr.user_id, b.id, b.name, b.points_award, b.threshold
  having count(*) >= b.threshold

  union
  -- points_total
  select pe.user_id, b.id, b.name, b.points_award
  from badges b
  join points_events pe on b.metric = 'points_total' and pe.user_id is not null
  where b.is_active
  group by pe.user_id, b.id, b.name, b.points_award, b.threshold
  having sum(pe.points) >= b.threshold
),
inserted as (
  insert into user_badges (user_id, badge_id)
  select user_id, badge_id from candidates
  on conflict (user_id, badge_id) do nothing
  returning user_id, badge_id
)
insert into points_events (user_id, event_kind, ref_type, ref_id, points, note)
select i.user_id, 'badge_awarded', 'badge', i.badge_id::text, b.points_award, b.name
from inserted i
join badges b on b.id = i.badge_id
where coalesce(b.points_award, 0) > 0
  and not exists (
    select 1 from points_events pe
    where pe.user_id = i.user_id
      and pe.event_kind = 'badge_awarded'
      and pe.ref_type = 'badge'
      and pe.ref_id = i.badge_id::text
  );
