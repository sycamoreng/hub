/*
  # Backfill leaderboard points from historical activity

  ## Summary
  Gamification was added after users had already been posting, commenting,
  giving kudos, completing learning steps and answering Daily Sparks. Those
  actions never wrote a row into `points_events`, so those team members were
  invisible on the leaderboard. This migration seeds `points_events` from
  existing activity using each event kind's configured weight.

  ## What gets backfilled
  1. `post_created` — one event per published post (author_id).
  2. `comment_posted` — one event per comment (user_id).
  3. `reaction_received` — one event per reaction, credited to the owner of
     the reacted post or comment.
  4. `kudos_given` — one event per kudos (from_user_id).
  5. `kudos_received` — one event per kudos (to_user_id).
  6. `onboarding_step_completed` — one event per completed learning step.
  7. `spark_correct` / `spark_participated` — one event per spark response.

  ## Safety
  - All inserts use `WHERE NOT EXISTS` guards against `points_events`
    (user_id, event_kind, ref_type, ref_id), so re-running is idempotent.
  - No destructive changes. Uses the active weight from `point_weights`
    at migration time; zero-weight kinds are skipped.
*/

-- 1. post_created
insert into points_events (user_id, event_kind, ref_type, ref_id, points, note, created_at)
select p.author_id,
       'post_created',
       'post',
       p.id::text,
       pw.points,
       'Shared a post',
       p.created_at
from posts p
cross join lateral (
  select points from point_weights where event_kind = 'post_created' and is_active limit 1
) pw
where p.author_id is not null
  and coalesce(p.is_published, true) = true
  and pw.points > 0
  and not exists (
    select 1 from points_events e
    where e.user_id = p.author_id
      and e.event_kind = 'post_created'
      and e.ref_type = 'post'
      and e.ref_id = p.id::text
  );

-- 2. comment_posted
insert into points_events (user_id, event_kind, ref_type, ref_id, points, note, created_at)
select c.user_id,
       'comment_posted',
       'comment',
       c.id::text,
       pw.points,
       'Commented on a post',
       c.created_at
from comments c
cross join lateral (
  select points from point_weights where event_kind = 'comment_posted' and is_active limit 1
) pw
where c.user_id is not null
  and pw.points > 0
  and not exists (
    select 1 from points_events e
    where e.user_id = c.user_id
      and e.event_kind = 'comment_posted'
      and e.ref_type = 'comment'
      and e.ref_id = c.id::text
  );

-- 3. reaction_received (credit to owner of the reacted target, skip self-reactions)
insert into points_events (user_id, event_kind, ref_type, ref_id, points, note, created_at)
select owner_id,
       'reaction_received',
       'reaction',
       r.id::text,
       pw.points,
       'Received a reaction',
       r.created_at
from (
  select r.id, r.created_at, r.user_id as reactor_id,
         case when r.target_type = 'post' then p.author_id
              when r.target_type = 'comment' then c.user_id
         end as owner_id
  from reactions r
  left join posts p on r.target_type = 'post' and p.id = r.target_id
  left join comments c on r.target_type = 'comment' and c.id = r.target_id
) r
cross join lateral (
  select points from point_weights where event_kind = 'reaction_received' and is_active limit 1
) pw
where r.owner_id is not null
  and r.owner_id <> r.reactor_id
  and pw.points > 0
  and not exists (
    select 1 from points_events e
    where e.user_id = r.owner_id
      and e.event_kind = 'reaction_received'
      and e.ref_type = 'reaction'
      and e.ref_id = r.id::text
  );

-- 4. kudos_given
insert into points_events (user_id, event_kind, ref_type, ref_id, points, note, created_at)
select k.from_user_id,
       'kudos_given',
       'kudos',
       k.id::text,
       pw.points,
       'Gave kudos',
       k.created_at
from kudos k
cross join lateral (
  select points from point_weights where event_kind = 'kudos_given' and is_active limit 1
) pw
where k.from_user_id is not null
  and pw.points > 0
  and not exists (
    select 1 from points_events e
    where e.user_id = k.from_user_id
      and e.event_kind = 'kudos_given'
      and e.ref_type = 'kudos'
      and e.ref_id = k.id::text
  );

-- 5. kudos_received
insert into points_events (user_id, event_kind, ref_type, ref_id, points, note, created_at)
select k.to_user_id,
       'kudos_received',
       'kudos',
       k.id::text,
       pw.points,
       'Received kudos',
       k.created_at
from kudos k
cross join lateral (
  select points from point_weights where event_kind = 'kudos_received' and is_active limit 1
) pw
where k.to_user_id is not null
  and pw.points > 0
  and not exists (
    select 1 from points_events e
    where e.user_id = k.to_user_id
      and e.event_kind = 'kudos_received'
      and e.ref_type = 'kudos'
      and e.ref_id = k.id::text
  );

-- 6. onboarding_step_completed
insert into points_events (user_id, event_kind, ref_type, ref_id, points, note, created_at)
select op.user_id,
       'onboarding_step_completed',
       'onboarding_step',
       op.step_id::text,
       pw.points,
       'Completed a learning step',
       coalesce(op.completed_at, op.created_at)
from onboarding_progress op
cross join lateral (
  select points from point_weights where event_kind = 'onboarding_step_completed' and is_active limit 1
) pw
where op.user_id is not null
  and op.completed_at is not null
  and pw.points > 0
  and not exists (
    select 1 from points_events e
    where e.user_id = op.user_id
      and e.event_kind = 'onboarding_step_completed'
      and e.ref_type = 'onboarding_step'
      and e.ref_id = op.step_id::text
  );

-- 7. daily spark responses
insert into points_events (user_id, event_kind, ref_type, ref_id, points, note, created_at)
select sr.user_id,
       case when sr.is_correct then 'spark_correct' else 'spark_participated' end,
       'spark',
       sr.spark_id::text,
       pw.points,
       case when sr.is_correct then 'Correct Daily Spark' else 'Played Daily Spark' end,
       sr.created_at
from spark_responses sr
cross join lateral (
  select points from point_weights
  where event_kind = case when sr.is_correct then 'spark_correct' else 'spark_participated' end
    and is_active
  limit 1
) pw
where sr.user_id is not null
  and pw.points > 0
  and not exists (
    select 1 from points_events e
    where e.user_id = sr.user_id
      and e.event_kind = case when sr.is_correct then 'spark_correct' else 'spark_participated' end
      and e.ref_type = 'spark'
      and e.ref_id = sr.spark_id::text
  );
