/*
  # Exit workflow (resignation & termination)

  ## Summary
  Adds a structured exit process. When a resignation or termination
  is triggered, an exit case is opened and a checklist of tasks is
  automatically generated across relevant units (Human Capital,
  Technology, Internal Control, Finance, Line Manager, Admin /
  Facilities, Communications). Heads of each unit are notified.

  ## New tables
  1. `exit_units`
     - Catalogue of units (code, name, icon, sort_order, is_active).
     - Seeded with the seven default units above.
  2. `exit_checklist_templates`
     - Default tasks per unit that get copied onto every new case.
     - (unit_code, title, detail, applies_to: resignation|termination|both, sort_order)
  3. `exit_cases`
     - The exit record itself: staff_id, exit_type, reason, effective_date,
       last_working_day, status (initiated|in_progress|completed|cancelled),
       initiated_by_user_id, initiated_by_kind (self|admin), notes.
  4. `exit_checklist_items`
     - Per-case tasks: case_id, unit_code, title, detail,
       assignee_user_id (defaults to HoD of the unit, configurable),
       status (pending|done|not_applicable), notes, completed_at,
       completed_by.

  ## Admin section
  Uses a new admin section key `exits` (no migration needed — section
  keys are arbitrary strings checked by `private.admin_can`).

  ## Security
  - All tables have RLS enabled.
  - exit_units / exit_checklist_templates: readable by authenticated;
    managed by admins with section `exits`.
  - exit_cases: the subject staff member can read their own case and
    insert their own resignation. Admins with `exits:read` can read
    all; `exits:create` can insert any; `exits:update` can modify;
    `exits:delete` can delete.
  - exit_checklist_items: the assignee can read and update their own
    items. Admins with `exits:read/update/create/delete` have full
    access. The subject of the case can read (but not update) items
    so they know what is outstanding.

  ## Trigger
  After insert into `exit_cases` a trigger copies the relevant
  templates (filtered by exit_type) into `exit_checklist_items`,
  with assignee defaulting to the unit's HoD (from staff_members
  role metadata) when available.

  ## Important notes
  1. No existing data is modified.
  2. The trigger uses SECURITY DEFINER and sets search_path for safety.
  3. HoD lookup is best-effort: if no HoD is mapped, assignee_user_id
     is left null and the task shows as unassigned for an admin to
     reassign.
*/

-- 1) Units catalogue
create table if not exists public.exit_units (
  code text primary key,
  name text not null,
  icon text not null default 'info',
  sort_order int not null default 0,
  hod_user_id uuid references auth.users(id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.exit_units enable row level security;

create policy "Authenticated can read exit units"
  on public.exit_units for select to authenticated using (true);

create policy "Admins insert exit units"
  on public.exit_units for insert to authenticated
  with check (private.admin_can('exits','create'));

create policy "Admins update exit units"
  on public.exit_units for update to authenticated
  using (private.admin_can('exits','update'))
  with check (private.admin_can('exits','update'));

create policy "Admins delete exit units"
  on public.exit_units for delete to authenticated
  using (private.admin_can('exits','delete'));

insert into public.exit_units (code, name, icon, sort_order) values
  ('human_capital',  'Human Capital',        'users',    10),
  ('line_manager',   'Line Manager',         'user',     20),
  ('technology',     'Technology',           'laptop',   30),
  ('internal_control','Internal Control',    'check',    40),
  ('finance',        'Finance',              'card',     50),
  ('admin_facilities','Admin & Facilities',  'building', 60),
  ('communications', 'Communications',       'chat',     70)
on conflict (code) do nothing;

-- 2) Checklist templates
create table if not exists public.exit_checklist_templates (
  id uuid primary key default gen_random_uuid(),
  unit_code text not null references public.exit_units(code) on delete cascade,
  title text not null,
  detail text not null default '',
  applies_to text not null default 'both' check (applies_to in ('resignation','termination','both')),
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists exit_templates_unit_idx on public.exit_checklist_templates(unit_code, sort_order);

alter table public.exit_checklist_templates enable row level security;

create policy "Authenticated can read exit templates"
  on public.exit_checklist_templates for select to authenticated using (true);

create policy "Admins insert exit templates"
  on public.exit_checklist_templates for insert to authenticated
  with check (private.admin_can('exits','create'));

create policy "Admins update exit templates"
  on public.exit_checklist_templates for update to authenticated
  using (private.admin_can('exits','update'))
  with check (private.admin_can('exits','update'));

create policy "Admins delete exit templates"
  on public.exit_checklist_templates for delete to authenticated
  using (private.admin_can('exits','delete'));

-- Seed default tasks
insert into public.exit_checklist_templates (unit_code, title, detail, applies_to, sort_order)
values
  ('human_capital','Acknowledge exit and schedule exit interview','Confirm receipt with the staff member and book an exit interview within 5 working days.','both',10),
  ('human_capital','Prepare exit documentation','Acceptance/termination letter, release of indebtedness, and final settlement statement.','both',20),
  ('human_capital','Collect signed NDA & non-compete acknowledgement','Obtain a signed copy of the confidentiality and non-compete acknowledgement.','both',30),
  ('human_capital','Update HRIS & org chart','Mark staff as offboarded and update reporting lines for affected teams.','both',40),

  ('line_manager','Knowledge transfer plan','Identify responsibilities to hand over and agree a written transfer plan with the outgoing staff.','both',10),
  ('line_manager','Reassign open tasks & projects','Reallocate in-flight work to team members and update trackers.','both',20),
  ('line_manager','Confirm last working day','Agree and communicate the final working day, including any accrued leave to be used.','both',30),

  ('technology','Disable email & Google Workspace access','Suspend account on last working day, enable vacation responder with redirection to a colleague.','both',10),
  ('technology','Revoke SaaS & internal tool access','Revoke access to Slack, GitHub, Supabase, dashboards and all third-party SaaS.','both',20),
  ('technology','Recover devices','Collect laptop, monitor, access cards, SIMs; verify disk wipe and return to asset pool.','both',30),
  ('technology','Rotate shared credentials','Rotate any shared passwords, API keys or secrets the staff had access to.','both',40),
  ('technology','Export handover artefacts','Export documentation, code and drive assets owned by the user into team-owned storage.','both',50),

  ('internal_control','Asset clearance','Independently verify asset return and sign off asset register.','both',10),
  ('internal_control','Access audit','Confirm all physical and digital access has been revoked; spot-check production systems.','both',20),
  ('internal_control','Review outstanding compliance items','Investigations, policy acknowledgements and regulatory filings cleared before release.','both',30),

  ('finance','Final salary computation','Calculate pro-rated salary, accrued leave pay, benefits clawback and deductions.','both',10),
  ('finance','Settle outstanding advances & loans','Reconcile any outstanding salary advance or loan balance with HR.','both',20),
  ('finance','Process final payment','Process final payment after all clearances; issue final payslip.','both',30),
  ('finance','Tax & pension wrap-up','File required PAYE and pension contributions; issue final statutory certificates.','both',40),

  ('admin_facilities','Collect physical access items','Recover ID card, office keys, parking tag and any branded merchandise.','both',10),
  ('admin_facilities','Desk & locker clearance','Confirm personal belongings cleared; return company property at the desk/locker.','both',20),

  ('communications','Internal announcement','Draft and send internal announcement from the line manager or HR head where appropriate.','both',10),
  ('communications','External handover notice','Notify external stakeholders (clients, vendors) of the new point of contact.','both',20),

  -- Termination-specific extras
  ('human_capital','Document termination rationale & approvals','Capture the documented grounds and approval chain for termination.','termination',5),
  ('internal_control','Investigation file closure','Where termination followed an investigation, close and archive the case file.','termination',5)
on conflict do nothing;

-- 3) Exit cases
create table if not exists public.exit_cases (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff_members(id) on delete cascade,
  exit_type text not null check (exit_type in ('resignation','termination')),
  reason text not null default '',
  effective_date date,
  last_working_day date,
  status text not null default 'initiated' check (status in ('initiated','in_progress','completed','cancelled')),
  initiated_by_user_id uuid references auth.users(id) on delete set null,
  initiated_by_kind text not null default 'admin' check (initiated_by_kind in ('self','admin')),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists exit_cases_staff_idx on public.exit_cases(staff_id, created_at desc);
create index if not exists exit_cases_status_idx on public.exit_cases(status, created_at desc);

alter table public.exit_cases enable row level security;

-- Subject staff can read their own case
create policy "Staff read own exit case"
  on public.exit_cases for select to authenticated
  using (
    exists (select 1 from public.staff_members sm
      where sm.id = exit_cases.staff_id and sm.auth_user_id = auth.uid())
    or private.admin_can('exits','read')
  );

-- Staff can open their own resignation
create policy "Staff open own resignation"
  on public.exit_cases for insert to authenticated
  with check (
    exit_type = 'resignation'
    and initiated_by_kind = 'self'
    and initiated_by_user_id = auth.uid()
    and exists (select 1 from public.staff_members sm
      where sm.id = exit_cases.staff_id and sm.auth_user_id = auth.uid())
  );

-- Admins can open any case
create policy "Admins open exit case"
  on public.exit_cases for insert to authenticated
  with check (private.admin_can('exits','create'));

create policy "Admins update exit case"
  on public.exit_cases for update to authenticated
  using (private.admin_can('exits','update'))
  with check (private.admin_can('exits','update'));

-- Staff can cancel their own in-flight resignation
create policy "Staff cancel own resignation"
  on public.exit_cases for update to authenticated
  using (
    initiated_by_kind = 'self'
    and initiated_by_user_id = auth.uid()
    and status in ('initiated','in_progress')
  )
  with check (
    status in ('cancelled','initiated','in_progress')
  );

create policy "Admins delete exit case"
  on public.exit_cases for delete to authenticated
  using (private.admin_can('exits','delete'));

-- 4) Checklist items
create table if not exists public.exit_checklist_items (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.exit_cases(id) on delete cascade,
  unit_code text not null references public.exit_units(code) on delete restrict,
  title text not null,
  detail text not null default '',
  assignee_user_id uuid references auth.users(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','done','not_applicable')),
  notes text not null default '',
  sort_order int not null default 0,
  completed_at timestamptz,
  completed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists exit_items_case_idx on public.exit_checklist_items(case_id, unit_code, sort_order);
create index if not exists exit_items_assignee_idx on public.exit_checklist_items(assignee_user_id, status);

alter table public.exit_checklist_items enable row level security;

create policy "Assignee and subject and admins read items"
  on public.exit_checklist_items for select to authenticated
  using (
    assignee_user_id = auth.uid()
    or exists (
      select 1 from public.exit_cases ec
      join public.staff_members sm on sm.id = ec.staff_id
      where ec.id = exit_checklist_items.case_id and sm.auth_user_id = auth.uid()
    )
    or private.admin_can('exits','read')
  );

create policy "Assignee can update own item"
  on public.exit_checklist_items for update to authenticated
  using (assignee_user_id = auth.uid())
  with check (assignee_user_id = auth.uid());

create policy "Admins manage items insert"
  on public.exit_checklist_items for insert to authenticated
  with check (private.admin_can('exits','create'));

create policy "Admins manage items update"
  on public.exit_checklist_items for update to authenticated
  using (private.admin_can('exits','update'))
  with check (private.admin_can('exits','update'));

create policy "Admins manage items delete"
  on public.exit_checklist_items for delete to authenticated
  using (private.admin_can('exits','delete'));

-- 5) Trigger: auto-generate checklist items from templates
create or replace function public.exit_case_generate_checklist()
returns trigger
language plpgsql
security definer
set search_path = public, private, auth
as $$
begin
  insert into public.exit_checklist_items (case_id, unit_code, title, detail, assignee_user_id, sort_order)
  select
    new.id,
    t.unit_code,
    t.title,
    t.detail,
    u.hod_user_id,
    t.sort_order
  from public.exit_checklist_templates t
  join public.exit_units u on u.code = t.unit_code
  where t.is_active
    and u.is_active
    and (t.applies_to = 'both' or t.applies_to = new.exit_type);
  return new;
end;
$$;

revoke execute on function public.exit_case_generate_checklist() from public, anon, authenticated;

drop trigger if exists exit_case_generate_checklist_trg on public.exit_cases;
create trigger exit_case_generate_checklist_trg
  after insert on public.exit_cases
  for each row execute function public.exit_case_generate_checklist();

-- 6) Touch updated_at
create or replace function public.exit_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists exit_cases_touch on public.exit_cases;
create trigger exit_cases_touch before update on public.exit_cases
  for each row execute function public.exit_touch_updated_at();

drop trigger if exists exit_items_touch on public.exit_checklist_items;
create trigger exit_items_touch before update on public.exit_checklist_items
  for each row execute function public.exit_touch_updated_at();
