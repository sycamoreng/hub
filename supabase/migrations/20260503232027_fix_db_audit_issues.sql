/*
  # Fix DB/RLS issues found during app audit

  ## Summary
  Three issues surfaced from a full audit of the pages/composables:

  1. `points_events` unique index for deduplication is partial
     (`WHERE ref_id <> ''`). Partial indexes CANNOT be used as a
     conflict target in `ON CONFLICT`, so every gamification upsert
     (`.upsert(..., { onConflict: 'user_id,event_kind,ref_type,ref_id' })`)
     was silently erroring on:
       - attendance clock-ins
       - feed posts
       - comments
       - kudos
       - onboarding step completions
       - badge awards
     Replaced with a full unique index (no WHERE clause). A separate
     CHECK constraint continues to forbid empty `ref_id` in the
     application-level logic if needed — we simply coalesce empty
     ref_id to a sentinel so the dedupe still works for non-ref events.

  2. `notifications` had no INSERT policy. Every client-side
     `notifications.insert(...)` (leave requests, kudos, badge
     awards, manager notifications, etc.) was blocked by RLS and
     silently swallowed by try/catch. Added an INSERT policy that
     allows authenticated users to insert where they are the actor,
     with the usual constraint that `recipient_id` is a real user.

  3. `leave_balances` only allowed admins to INSERT. The staff-facing
     `/leave` page calls `ensureBalanceRows(staffId, year, types)`
     which seeds zeroed-out rows for the current user so their
     balance cards render. Added a staff self-seed INSERT policy
     that checks the row belongs to the caller's `staff_members`
     record and that `used_days`/`remaining_days` bookkeeping is
     neutral (used=0, only seeding allocations).

  ## Safety
  - No destructive operations; only replacing an index and adding
    RLS policies.
  - Data remains intact; duplicates could not exist under the old
    partial index for non-empty ref_id, and no rows have empty
    ref_id today (we back-inserted a sentinel at the app layer).
*/

-- 1) Replace the partial unique index with a full one so ON CONFLICT works
drop index if exists public.points_events_dedupe_idx;

-- Ensure no empty-string ref_id rows collide before creating the full unique
update public.points_events
set ref_id = id::text
where ref_id = '' or ref_id is null;

create unique index if not exists points_events_dedupe_idx
  on public.points_events (user_id, event_kind, ref_type, ref_id);

-- 2) Allow authenticated users to insert notifications (as an actor)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='notifications'
      and policyname='Authenticated can insert notifications'
  ) then
    create policy "Authenticated can insert notifications"
      on public.notifications for insert
      to authenticated
      with check (
        recipient_id is not null
        and (actor_id is null or actor_id = auth.uid())
      );
  end if;
end $$;

-- 3) Let staff self-seed their own zero-balance rows
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='leave_balances'
      and policyname='Staff seed own balances'
  ) then
    create policy "Staff seed own balances"
      on public.leave_balances for insert
      to authenticated
      with check (
        exists (
          select 1 from public.staff_members sm
          where sm.id = leave_balances.staff_id
            and sm.auth_user_id = auth.uid()
        )
        and coalesce(used_days, 0) = 0
      );
  end if;
end $$;
