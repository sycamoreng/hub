/*
  # Performance management — Phase 1 (foundation)

  ## Summary
  Introduces the foundation for the performance management system: cycles,
  frameworks (OKR / KPI / competencies), objectives belonging to a cycle for
  a staff member, and child "measures" (key results for OKR, metrics for
  KPI, rated competencies). Later phases (appraisals, 360s, PIPs) will
  reference these tables so everything stays intertwined.

  ## New tables
  1. `performance_cycles`
     - A named review period (e.g. "2026 H1"). Controls when setting,
       self-eval, manager-eval and 360 phases are open.
     - Fields: name, period_start, period_end, status (draft|planning|active|in_review|closed),
       default_framework (okr|kpi|mixed), phase_* date ranges, is_primary.
  2. `performance_frameworks`
     - Re-usable framework definitions that can be applied to cycles and
       specific objectives. kind: okr | kpi | competency. Configurable
       scoring scale (min/max/labels) stored in JSON.
  3. `performance_objectives`
     - One row per staff member per objective per cycle. Tracks title,
       description, weight (0-100 so totals can be normalised), category
       (business|personal|team|company), framework_id, target_value,
       status (draft|active|at_risk|on_track|completed|dropped), progress
       (0-100), rating (null until scored), and the owning cycle.
  4. `performance_measures`
     - Child rows for objectives. For OKRs these are Key Results, for
       KPIs these are the individual metrics, for competencies these are
       the competency descriptors. Fields: label, target, current_value,
       unit, weight, status, progress.

  ## Security
  - RLS enabled on all tables.
  - Read access: the subject staff member reads their own objectives/measures;
    their direct manager (via staff_members.manager_id chain) can also read;
    admins with section `performance:read` read all.
  - Write access: admins with `performance:create|update|delete` on all
    tables; staff may `update` progress + current_value on their own
    objectives/measures during the setting and active phases (gated by
    a simple status check inside the policy). Framework + cycle are admin
    only.

  ## Important notes
  1. No existing data is touched.
  2. Weight totals are not enforced in SQL — the UI will surface a warning
     if an employee's active objectives don't sum to ~100 so we don't
     block legitimate interim states.
  3. `is_primary` on `performance_cycles` is kept unique via a partial
     index so exactly one cycle can be flagged as the "current" one in
     the UI.
  4. Touch triggers keep `updated_at` fresh on updates.
*/

-- 1) Cycles -----------------------------------------------------------------
create table if not exists public.performance_cycles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','planning','active','in_review','closed')),
  default_framework text not null default 'okr' check (default_framework in ('okr','kpi','mixed','competency')),
  objective_setting_start date,
  objective_setting_end date,
  self_eval_start date,
  self_eval_end date,
  manager_eval_start date,
  manager_eval_end date,
  peer_review_start date,
  peer_review_end date,
  is_primary boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists performance_cycles_primary_unique
  on public.performance_cycles(is_primary) where is_primary = true;
create index if not exists performance_cycles_status_idx
  on public.performance_cycles(status, period_start desc);

alter table public.performance_cycles enable row level security;

create policy "Authenticated read performance cycles"
  on public.performance_cycles for select to authenticated using (true);
create policy "Admins insert performance cycles"
  on public.performance_cycles for insert to authenticated
  with check (private.admin_can('performance','create'));
create policy "Admins update performance cycles"
  on public.performance_cycles for update to authenticated
  using (private.admin_can('performance','update'))
  with check (private.admin_can('performance','update'));
create policy "Admins delete performance cycles"
  on public.performance_cycles for delete to authenticated
  using (private.admin_can('performance','delete'));

-- 2) Frameworks -------------------------------------------------------------
create table if not exists public.performance_frameworks (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  kind text not null check (kind in ('okr','kpi','competency')),
  description text not null default '',
  scoring_scale jsonb not null default '{"min":1,"max":5,"labels":["Needs work","Below","Meets","Exceeds","Outstanding"]}'::jsonb,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists performance_frameworks_kind_idx
  on public.performance_frameworks(kind, sort_order);

alter table public.performance_frameworks enable row level security;

create policy "Authenticated read performance frameworks"
  on public.performance_frameworks for select to authenticated using (true);
create policy "Admins insert performance frameworks"
  on public.performance_frameworks for insert to authenticated
  with check (private.admin_can('performance','create'));
create policy "Admins update performance frameworks"
  on public.performance_frameworks for update to authenticated
  using (private.admin_can('performance','update'))
  with check (private.admin_can('performance','update'));
create policy "Admins delete performance frameworks"
  on public.performance_frameworks for delete to authenticated
  using (private.admin_can('performance','delete'));

-- Seed a few default frameworks (idempotent)
insert into public.performance_frameworks (name, kind, description, sort_order)
select 'Objectives & Key Results', 'okr', 'Qualitative objective with 3–5 measurable Key Results.', 10
where not exists (select 1 from public.performance_frameworks where kind='okr');

insert into public.performance_frameworks (name, kind, description, sort_order)
select 'Key Performance Indicators', 'kpi', 'Quantitative metrics with targets and thresholds.', 20
where not exists (select 1 from public.performance_frameworks where kind='kpi');

insert into public.performance_frameworks (name, kind, description, sort_order)
select 'Core Competencies', 'competency', 'Rated behaviours aligned to company values.', 30
where not exists (select 1 from public.performance_frameworks where kind='competency');

-- 3) Objectives -------------------------------------------------------------
create table if not exists public.performance_objectives (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references public.performance_cycles(id) on delete cascade,
  staff_id uuid not null references public.staff_members(id) on delete cascade,
  framework_id uuid references public.performance_frameworks(id) on delete set null,
  kind text not null default 'okr' check (kind in ('okr','kpi','competency')),
  title text not null,
  description text not null default '',
  category text not null default 'business' check (category in ('business','personal','team','company','stretch')),
  weight numeric(5,2) not null default 0 check (weight >= 0 and weight <= 100),
  target_value text not null default '',
  status text not null default 'draft' check (status in ('draft','active','on_track','at_risk','off_track','completed','dropped')),
  progress numeric(5,2) not null default 0 check (progress >= 0 and progress <= 100),
  rating numeric(4,2),
  manager_notes text not null default '',
  staff_notes text not null default '',
  sort_order int not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists performance_objectives_cycle_staff_idx
  on public.performance_objectives(cycle_id, staff_id, sort_order);
create index if not exists performance_objectives_staff_idx
  on public.performance_objectives(staff_id, status);

alter table public.performance_objectives enable row level security;

-- Helper: is the current user the manager (any level up the chain) of a staff row
create or replace function private.is_manager_of(target_staff uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  with recursive chain as (
    select sm.id, sm.manager_id
    from public.staff_members sm
    where sm.id = target_staff
    union all
    select parent.id, parent.manager_id
    from public.staff_members parent
    join chain c on c.manager_id = parent.id
  )
  select exists (
    select 1
    from chain c
    join public.staff_members m on m.id = c.manager_id
    where m.auth_user_id = auth.uid()
  );
$$;

revoke execute on function private.is_manager_of(uuid) from public, anon;
grant execute on function private.is_manager_of(uuid) to authenticated;

create policy "Subject manager admin read objectives"
  on public.performance_objectives for select to authenticated
  using (
    private.admin_can('performance','read')
    or exists (
      select 1 from public.staff_members sm
      where sm.id = performance_objectives.staff_id and sm.auth_user_id = auth.uid()
    )
    or private.is_manager_of(performance_objectives.staff_id)
  );

create policy "Admins insert objectives"
  on public.performance_objectives for insert to authenticated
  with check (private.admin_can('performance','create'));

-- Managers can insert objectives for their reports
create policy "Managers insert objectives for reports"
  on public.performance_objectives for insert to authenticated
  with check (private.is_manager_of(staff_id));

create policy "Admins update objectives"
  on public.performance_objectives for update to authenticated
  using (private.admin_can('performance','update'))
  with check (private.admin_can('performance','update'));

create policy "Managers update objectives for reports"
  on public.performance_objectives for update to authenticated
  using (private.is_manager_of(staff_id))
  with check (private.is_manager_of(staff_id));

-- Staff can update progress + staff_notes on their own objectives while cycle is open
create policy "Staff update own objective progress"
  on public.performance_objectives for update to authenticated
  using (
    exists (
      select 1 from public.staff_members sm
      where sm.id = performance_objectives.staff_id and sm.auth_user_id = auth.uid()
    )
    and exists (
      select 1 from public.performance_cycles c
      where c.id = performance_objectives.cycle_id
        and c.status in ('planning','active','in_review')
    )
  )
  with check (
    exists (
      select 1 from public.staff_members sm
      where sm.id = performance_objectives.staff_id and sm.auth_user_id = auth.uid()
    )
  );

create policy "Admins delete objectives"
  on public.performance_objectives for delete to authenticated
  using (private.admin_can('performance','delete'));

-- 4) Measures ---------------------------------------------------------------
create table if not exists public.performance_measures (
  id uuid primary key default gen_random_uuid(),
  objective_id uuid not null references public.performance_objectives(id) on delete cascade,
  label text not null,
  description text not null default '',
  unit text not null default '',
  baseline_value text not null default '',
  target_value text not null default '',
  current_value text not null default '',
  weight numeric(5,2) not null default 0 check (weight >= 0 and weight <= 100),
  progress numeric(5,2) not null default 0 check (progress >= 0 and progress <= 100),
  status text not null default 'pending' check (status in ('pending','on_track','at_risk','off_track','done','dropped')),
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists performance_measures_objective_idx
  on public.performance_measures(objective_id, sort_order);

alter table public.performance_measures enable row level security;

create policy "Read measures if can read parent objective"
  on public.performance_measures for select to authenticated
  using (
    exists (
      select 1 from public.performance_objectives o
      where o.id = performance_measures.objective_id
        and (
          private.admin_can('performance','read')
          or private.is_manager_of(o.staff_id)
          or exists (
            select 1 from public.staff_members sm
            where sm.id = o.staff_id and sm.auth_user_id = auth.uid()
          )
        )
    )
  );

create policy "Admins insert measures"
  on public.performance_measures for insert to authenticated
  with check (private.admin_can('performance','create'));

create policy "Managers insert measures for reports"
  on public.performance_measures for insert to authenticated
  with check (
    exists (
      select 1 from public.performance_objectives o
      where o.id = objective_id and private.is_manager_of(o.staff_id)
    )
  );

create policy "Staff insert measures on own objectives"
  on public.performance_measures for insert to authenticated
  with check (
    exists (
      select 1 from public.performance_objectives o
      join public.staff_members sm on sm.id = o.staff_id
      join public.performance_cycles c on c.id = o.cycle_id
      where o.id = objective_id
        and sm.auth_user_id = auth.uid()
        and c.status in ('planning','active','in_review')
    )
  );

create policy "Admins update measures"
  on public.performance_measures for update to authenticated
  using (private.admin_can('performance','update'))
  with check (private.admin_can('performance','update'));

create policy "Managers update measures for reports"
  on public.performance_measures for update to authenticated
  using (
    exists (select 1 from public.performance_objectives o where o.id = objective_id and private.is_manager_of(o.staff_id))
  )
  with check (
    exists (select 1 from public.performance_objectives o where o.id = objective_id and private.is_manager_of(o.staff_id))
  );

create policy "Staff update measures on own objectives"
  on public.performance_measures for update to authenticated
  using (
    exists (
      select 1 from public.performance_objectives o
      join public.staff_members sm on sm.id = o.staff_id
      join public.performance_cycles c on c.id = o.cycle_id
      where o.id = performance_measures.objective_id
        and sm.auth_user_id = auth.uid()
        and c.status in ('planning','active','in_review')
    )
  )
  with check (
    exists (
      select 1 from public.performance_objectives o
      join public.staff_members sm on sm.id = o.staff_id
      where o.id = performance_measures.objective_id
        and sm.auth_user_id = auth.uid()
    )
  );

create policy "Admins delete measures"
  on public.performance_measures for delete to authenticated
  using (private.admin_can('performance','delete'));

create policy "Managers delete measures for reports"
  on public.performance_measures for delete to authenticated
  using (
    exists (select 1 from public.performance_objectives o where o.id = objective_id and private.is_manager_of(o.staff_id))
  );

-- 5) updated_at triggers ----------------------------------------------------
create or replace function public.performance_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists performance_cycles_touch on public.performance_cycles;
create trigger performance_cycles_touch before update on public.performance_cycles
  for each row execute function public.performance_touch_updated_at();

drop trigger if exists performance_frameworks_touch on public.performance_frameworks;
create trigger performance_frameworks_touch before update on public.performance_frameworks
  for each row execute function public.performance_touch_updated_at();

drop trigger if exists performance_objectives_touch on public.performance_objectives;
create trigger performance_objectives_touch before update on public.performance_objectives
  for each row execute function public.performance_touch_updated_at();

drop trigger if exists performance_measures_touch on public.performance_measures;
create trigger performance_measures_touch before update on public.performance_measures
  for each row execute function public.performance_touch_updated_at();
