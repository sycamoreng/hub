/*
  # Add points_award to badges and backfill leaderboard points

  ## Summary
  Badges and milestones were previously awarded via `user_badges` but did not
  contribute any points to `points_events`, so they never appeared on the
  leaderboard. This migration adds a `points_award` column to each badge and
  backfills `points_events` with one `badge_awarded` event per already-granted
  badge, using the badge id as the dedupe key.

  ## Changes
  1. `badges.points_award` — new int column, default 0, for the points granted
     when a user earns the badge.
  2. Seeded meaningful default values on the out-of-the-box badges.
  3. Backfilled `points_events` for all existing `user_badges` rows so past
     winners now show up on the leaderboard.

  ## Notes
  - No destructive operations.
  - Backfill uses `NOT EXISTS` so re-running is safe.
*/

alter table badges add column if not exists points_award int not null default 0;

update badges set points_award = case code
  when 'first_post' then 15
  when 'conversationalist' then 25
  when 'kudos_starter' then 25
  when 'celebrated' then 50
  when 'learner' then 30
  when 'century' then 50
  when 'champion' then 150
  when 'spark_streak' then 40
  else points_award
end
where points_award = 0;

insert into points_events (user_id, event_kind, ref_type, ref_id, points, note, created_at)
select ub.user_id,
       'badge_awarded',
       'badge',
       b.id::text,
       b.points_award,
       b.name,
       ub.awarded_at
from user_badges ub
join badges b on b.id = ub.badge_id
where b.points_award > 0
  and not exists (
    select 1 from points_events pe
    where pe.user_id = ub.user_id
      and pe.event_kind = 'badge_awarded'
      and pe.ref_type = 'badge'
      and pe.ref_id = b.id::text
  );
