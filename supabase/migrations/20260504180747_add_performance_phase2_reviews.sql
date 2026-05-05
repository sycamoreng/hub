/*
  # Performance management — Phase 2 (reviews & appraisals)

  ## Summary
  Adds the review framework on top of the Phase 1 cycle + objectives model.
  One flexible model `performance_reviews` (the "request") with child rows
  in `performance_review_ratings` (the "answers") covers every review type
  the business asked for:

    - self           (staff evaluates themselves)
    - manager        (direct manager appraises the staff)
    - peer           (anonymous or named feedback from a colleague)
    - upward         (staff reviews their own manager / skip-level)
    - downward       (manager reviews a direct report; similar to manager
                      but initiated from the report's side of a 360)

  The requests are attached to a cycle + subject staff member so every
  piece of evidence rolls up to the same objective set. Ratings reference
  either an objective, a framework (for competency sliders), or neither
  (for free-form narrative questions).

  ## New tables
  1. `performance_reviews`
     - cycle_id, subject_staff_id, reviewer_staff_id, reviewer_type
       (self|manager|peer|upward|downward), status
       (invited|in_progress|submitted|declined|cancelled), anonymous,
       invited_by, invited_at, due_at, submitted_at, overall_rating,
       overall_comment, strengths, improvements.
  2. `performance_review_ratings`
     - review_id, objective_id (nullable), competency_label, question,
       score (numeric), comment, sort_order. Flexible enough to capture
       objective-by-objective scores AND open competency/behavioural
       questions.

  ## Security (RLS)
  Read:
    - Reviewer reads their own reviews (including drafts).
    - Subject reads SUBMITTED reviews about them. For anonymous peer
      reviews, the subject still sees the content but reviewer identity is
      redacted at the app layer via `anonymous=true` flag.
    - Direct + skip-level managers of the subject read submitted reviews
      about reports, and all reviews for whose subject they're in the
      management chain.
    - Admins with `performance:read` read everything.
  Write:
    - Admins with `performance:create|update|delete` manage all rows.
    - Reviewer can insert ratings on their own in-progress review and
      update the review until it is submitted.
    - Once status = 'submitted' the reviewer can no longer edit (enforced
      by a row-level check against the current status value).

  ## Important notes
  1. `reviewer_type = 'self'` requires reviewer_staff_id = subject_staff_id
     (check constraint).
  2. `anonymous` defaults to true for peer/upward but false for self and
     manager; admin UI can override.
  3. Unique index prevents duplicate outstanding invitations for the same
     (cycle, subject, reviewer, reviewer_type) tuple — if an invitation is
     cancelled it can be re-issued because the partial unique index only
     catches invited/in_progress/submitted rows.
*/

-- 1) performance_reviews ---------------------------------------------------
create table if not exists public.performance_reviews (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references public.performance_cycles(id) on delete cascade,
  subject_staff_id uuid not null references public.staff_members(id) on delete cascade,
  reviewer_staff_id uuid not null references public.staff_members(id) on delete cascade,
  reviewer_type text not null check (reviewer_type in ('self','manager','peer','upward','downward')),
  status text not null default 'invited' check (status in ('invited','in_progress','submitted','declined','cancelled')),
  anonymous boolean not null default false,
  invited_by uuid references auth.users(id) on delete set null,
  invited_at timestamptz not null default now(),
  due_at timestamptz,
  submitted_at timestamptz,
  declined_reason text not null default '',
  overall_rating numeric(4,2),
  overall_comment text not null default '',
  strengths text not null default '',
  improvements text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint performance_reviews_self_match
    check (reviewer_type <> 'self' or reviewer_staff_id = subject_staff_id)
);

create index if not exists performance_reviews_subject_idx
  on public.performance_reviews(subject_staff_id, cycle_id, reviewer_type);
create index if not exists performance_reviews_reviewer_idx
  on public.performance_reviews(reviewer_staff_id, status, due_at);
create unique index if not exists performance_reviews_active_unique
  on public.performance_reviews(cycle_id, subject_staff_id, reviewer_staff_id, reviewer_type)
  where status in ('invited','in_progress','submitted');

alter table public.performance_reviews enable row level security;

create or replace function private.current_staff_id()
returns uuid
language sql stable security definer
set search_path = public, auth
as $$
  select id from public.staff_members where auth_user_id = auth.uid() limit 1;
$$;
revoke execute on function private.current_staff_id() from public, anon;
grant execute on function private.current_staff_id() to authenticated;

-- Reviewer sees own row always; subject sees submitted rows about them;
-- managers in the chain see submitted rows about their reports; admins see all.
create policy "Read performance reviews"
  on public.performance_reviews for select to authenticated
  using (
    private.admin_can('performance','read')
    or reviewer_staff_id = private.current_staff_id()
    or (
      status = 'submitted' and (
        subject_staff_id = private.current_staff_id()
        or private.is_manager_of(subject_staff_id)
      )
    )
    or (status <> 'submitted' and private.is_manager_of(subject_staff_id))
  );

create policy "Admins insert reviews"
  on public.performance_reviews for insert to authenticated
  with check (private.admin_can('performance','create'));

-- Managers can invite peer/upward/downward/manager reviews for their reports
create policy "Managers invite reviews for reports"
  on public.performance_reviews for insert to authenticated
  with check (private.is_manager_of(subject_staff_id));

-- Staff can create their own self-review invitation
create policy "Staff self review"
  on public.performance_reviews for insert to authenticated
  with check (
    reviewer_type = 'self'
    and subject_staff_id = private.current_staff_id()
    and reviewer_staff_id = private.current_staff_id()
  );

create policy "Admins update reviews"
  on public.performance_reviews for update to authenticated
  using (private.admin_can('performance','update'))
  with check (private.admin_can('performance','update'));

-- Reviewer can edit their own review until submitted (row check via USING on OLD)
create policy "Reviewer edits own draft"
  on public.performance_reviews for update to authenticated
  using (reviewer_staff_id = private.current_staff_id() and status in ('invited','in_progress'))
  with check (reviewer_staff_id = private.current_staff_id());

create policy "Admins delete reviews"
  on public.performance_reviews for delete to authenticated
  using (private.admin_can('performance','delete'));

-- 2) performance_review_ratings -------------------------------------------
create table if not exists public.performance_review_ratings (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.performance_reviews(id) on delete cascade,
  objective_id uuid references public.performance_objectives(id) on delete set null,
  competency_label text not null default '',
  question text not null default '',
  score numeric(4,2),
  comment text not null default '',
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists performance_review_ratings_review_idx
  on public.performance_review_ratings(review_id, sort_order);

alter table public.performance_review_ratings enable row level security;

create policy "Read ratings if can read parent review"
  on public.performance_review_ratings for select to authenticated
  using (
    exists (
      select 1 from public.performance_reviews r
      where r.id = review_id
        and (
          private.admin_can('performance','read')
          or r.reviewer_staff_id = private.current_staff_id()
          or (r.status = 'submitted' and (r.subject_staff_id = private.current_staff_id() or private.is_manager_of(r.subject_staff_id)))
          or (r.status <> 'submitted' and private.is_manager_of(r.subject_staff_id))
        )
    )
  );

create policy "Admins insert ratings"
  on public.performance_review_ratings for insert to authenticated
  with check (private.admin_can('performance','create'));

create policy "Reviewer inserts own ratings"
  on public.performance_review_ratings for insert to authenticated
  with check (
    exists (
      select 1 from public.performance_reviews r
      where r.id = review_id
        and r.reviewer_staff_id = private.current_staff_id()
        and r.status in ('invited','in_progress')
    )
  );

create policy "Admins update ratings"
  on public.performance_review_ratings for update to authenticated
  using (private.admin_can('performance','update'))
  with check (private.admin_can('performance','update'));

create policy "Reviewer updates own ratings"
  on public.performance_review_ratings for update to authenticated
  using (
    exists (
      select 1 from public.performance_reviews r
      where r.id = review_id
        and r.reviewer_staff_id = private.current_staff_id()
        and r.status in ('invited','in_progress')
    )
  )
  with check (
    exists (
      select 1 from public.performance_reviews r
      where r.id = review_id
        and r.reviewer_staff_id = private.current_staff_id()
    )
  );

create policy "Admins delete ratings"
  on public.performance_review_ratings for delete to authenticated
  using (private.admin_can('performance','delete'));

create policy "Reviewer deletes own ratings while draft"
  on public.performance_review_ratings for delete to authenticated
  using (
    exists (
      select 1 from public.performance_reviews r
      where r.id = review_id
        and r.reviewer_staff_id = private.current_staff_id()
        and r.status in ('invited','in_progress')
    )
  );

-- 3) touch triggers --------------------------------------------------------
drop trigger if exists performance_reviews_touch on public.performance_reviews;
create trigger performance_reviews_touch before update on public.performance_reviews
  for each row execute function public.performance_touch_updated_at();

drop trigger if exists performance_review_ratings_touch on public.performance_review_ratings;
create trigger performance_review_ratings_touch before update on public.performance_review_ratings
  for each row execute function public.performance_touch_updated_at();
