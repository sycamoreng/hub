/*
  # Leave Management System

  Adds a full leave workflow including dynamic leave types, per-staff
  annual balances, request submission with manager approval, public
  holiday management, and integration with the attendance schedule.

  1. New tables
    - `leave_types`
      - Dynamic catalog of leave kinds (Annual, Sick, Maternity, etc.)
      - `name`, `code`, `color`, `default_days_per_year`, `paid`,
        `requires_approval`, `is_active`, `sort_order`
    - `leave_balances`
      - Per (staff_id, leave_type_id, year) with `allocated_days`,
        `used_days`, `adjustment_days`
    - `leave_requests`
      - staff, leave_type, start_date, end_date, half_day_start/end,
        working_days (computed on submit), reason, attachment_url,
        status ('pending'|'approved'|'declined'|'cancelled'),
        approver, decided_at, decision_notes, notify_colleagues
    - `public_holidays`
      - date, name, country (default NG), recurring_yearly flag,
        is_active

  2. Security (RLS)
    - `leave_types`: authenticated can SELECT active; admins with
      `attendance` section manage all.
    - `public_holidays`: authenticated SELECT, admins manage.
    - `leave_balances`: staff see own, admins manage all.
    - `leave_requests`: staff see/create own; managers see their
      reports; admins see all; approvals require admin OR manager.

  3. Notes
    1. Leave requests, once approved, write `attendance_days` rows
       (kind='leave') so clock-in and the schedule views show the
       staff as on leave.
    2. Public holidays are excluded from working day counts in the
       application layer.
    3. Default seed leave types: Annual (21), Sick (14), Compassionate
       (5), Maternity (112), Paternity (14), Unpaid (0).
*/

CREATE TABLE IF NOT EXISTS leave_types (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  code text NOT NULL UNIQUE,
  color text NOT NULL DEFAULT '#16a34a',
  default_days_per_year numeric(5,2) NOT NULL DEFAULT 0,
  paid boolean NOT NULL DEFAULT true,
  requires_approval boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  description text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

INSERT INTO leave_types (name, code, color, default_days_per_year, paid, requires_approval, sort_order, description)
VALUES
  ('Annual Leave','annual','#16a34a',21,true,true,10,'Standard paid annual leave.'),
  ('Sick Leave','sick','#0ea5e9',14,true,false,20,'Short-term illness.'),
  ('Compassionate Leave','compassionate','#a16207',5,true,true,30,'Bereavement or urgent family matters.'),
  ('Maternity Leave','maternity','#db2777',112,true,true,40,'Statutory maternity leave.'),
  ('Paternity Leave','paternity','#0891b2',14,true,true,50,'Paid paternity leave.'),
  ('Unpaid Leave','unpaid','#64748b',0,false,true,60,'Leave without pay.')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS public_holidays (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  day date NOT NULL,
  name text NOT NULL,
  country text NOT NULL DEFAULT 'NG',
  recurring_yearly boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now(),
  UNIQUE (day, name, country)
);

CREATE INDEX IF NOT EXISTS public_holidays_day_idx ON public_holidays(day);

CREATE TABLE IF NOT EXISTS leave_balances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES staff_members(id) ON DELETE CASCADE,
  leave_type_id uuid NOT NULL REFERENCES leave_types(id) ON DELETE CASCADE,
  year int NOT NULL,
  allocated_days numeric(6,2) NOT NULL DEFAULT 0,
  used_days numeric(6,2) NOT NULL DEFAULT 0,
  adjustment_days numeric(6,2) NOT NULL DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (staff_id, leave_type_id, year)
);

CREATE INDEX IF NOT EXISTS leave_balances_staff_idx ON leave_balances(staff_id, year);

CREATE TABLE IF NOT EXISTS leave_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES staff_members(id) ON DELETE CASCADE,
  requester_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  leave_type_id uuid NOT NULL REFERENCES leave_types(id) ON DELETE RESTRICT,
  start_date date NOT NULL,
  end_date date NOT NULL,
  half_day_start boolean NOT NULL DEFAULT false,
  half_day_end boolean NOT NULL DEFAULT false,
  working_days numeric(5,2) NOT NULL DEFAULT 0,
  reason text DEFAULT '',
  attachment_url text DEFAULT '',
  notify_colleagues boolean NOT NULL DEFAULT true,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','declined','cancelled')),
  approver_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  decided_at timestamptz,
  decision_notes text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CHECK (end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS leave_requests_staff_idx ON leave_requests(staff_id);
CREATE INDEX IF NOT EXISTS leave_requests_status_idx ON leave_requests(status);
CREATE INDEX IF NOT EXISTS leave_requests_dates_idx ON leave_requests(start_date, end_date);

ALTER TABLE leave_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public_holidays ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;

-- leave_types
DROP POLICY IF EXISTS "All can read leave types" ON leave_types;
CREATE POLICY "All can read leave types"
  ON leave_types FOR SELECT TO authenticated
  USING (is_active OR private.admin_can('attendance','read'));

DROP POLICY IF EXISTS "Admins insert leave types" ON leave_types;
CREATE POLICY "Admins insert leave types"
  ON leave_types FOR INSERT TO authenticated
  WITH CHECK (private.admin_can('attendance','create'));

DROP POLICY IF EXISTS "Admins update leave types" ON leave_types;
CREATE POLICY "Admins update leave types"
  ON leave_types FOR UPDATE TO authenticated
  USING (private.admin_can('attendance','update'))
  WITH CHECK (private.admin_can('attendance','update'));

DROP POLICY IF EXISTS "Admins delete leave types" ON leave_types;
CREATE POLICY "Admins delete leave types"
  ON leave_types FOR DELETE TO authenticated
  USING (private.admin_can('attendance','delete'));

-- public_holidays
DROP POLICY IF EXISTS "All read holidays" ON public_holidays;
CREATE POLICY "All read holidays"
  ON public_holidays FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admins insert holidays" ON public_holidays;
CREATE POLICY "Admins insert holidays"
  ON public_holidays FOR INSERT TO authenticated
  WITH CHECK (private.admin_can('attendance','create'));

DROP POLICY IF EXISTS "Admins update holidays" ON public_holidays;
CREATE POLICY "Admins update holidays"
  ON public_holidays FOR UPDATE TO authenticated
  USING (private.admin_can('attendance','update'))
  WITH CHECK (private.admin_can('attendance','update'));

DROP POLICY IF EXISTS "Admins delete holidays" ON public_holidays;
CREATE POLICY "Admins delete holidays"
  ON public_holidays FOR DELETE TO authenticated
  USING (private.admin_can('attendance','delete'));

-- leave_balances
DROP POLICY IF EXISTS "Staff read own balances" ON leave_balances;
CREATE POLICY "Staff read own balances"
  ON leave_balances FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM staff_members sm WHERE sm.id = leave_balances.staff_id AND sm.auth_user_id = auth.uid())
    OR private.admin_can('attendance','read')
  );

DROP POLICY IF EXISTS "Admins insert balances" ON leave_balances;
CREATE POLICY "Admins insert balances"
  ON leave_balances FOR INSERT TO authenticated
  WITH CHECK (private.admin_can('attendance','create'));

DROP POLICY IF EXISTS "Admins update balances" ON leave_balances;
CREATE POLICY "Admins update balances"
  ON leave_balances FOR UPDATE TO authenticated
  USING (private.admin_can('attendance','update'))
  WITH CHECK (private.admin_can('attendance','update'));

DROP POLICY IF EXISTS "Admins delete balances" ON leave_balances;
CREATE POLICY "Admins delete balances"
  ON leave_balances FOR DELETE TO authenticated
  USING (private.admin_can('attendance','delete'));

-- leave_requests
DROP POLICY IF EXISTS "Staff read own or managed leave requests" ON leave_requests;
CREATE POLICY "Staff read own or managed leave requests"
  ON leave_requests FOR SELECT TO authenticated
  USING (
    requester_user_id = auth.uid()
    OR private.admin_can('attendance','read')
    OR EXISTS (
      SELECT 1 FROM staff_members subj, staff_members mgr
      WHERE subj.id = leave_requests.staff_id
        AND subj.manager_id = mgr.id
        AND mgr.auth_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Staff create own leave request" ON leave_requests;
CREATE POLICY "Staff create own leave request"
  ON leave_requests FOR INSERT TO authenticated
  WITH CHECK (
    requester_user_id = auth.uid()
    OR private.admin_can('attendance','create')
  );

DROP POLICY IF EXISTS "Staff and managers update leave requests" ON leave_requests;
CREATE POLICY "Staff and managers update leave requests"
  ON leave_requests FOR UPDATE TO authenticated
  USING (
    (requester_user_id = auth.uid() AND status = 'pending')
    OR private.admin_can('attendance','update')
    OR EXISTS (
      SELECT 1 FROM staff_members subj, staff_members mgr
      WHERE subj.id = leave_requests.staff_id
        AND subj.manager_id = mgr.id
        AND mgr.auth_user_id = auth.uid()
    )
  )
  WITH CHECK (
    (requester_user_id = auth.uid() AND status IN ('pending','cancelled'))
    OR private.admin_can('attendance','update')
    OR EXISTS (
      SELECT 1 FROM staff_members subj, staff_members mgr
      WHERE subj.id = leave_requests.staff_id
        AND subj.manager_id = mgr.id
        AND mgr.auth_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Admins delete leave requests" ON leave_requests;
CREATE POLICY "Admins delete leave requests"
  ON leave_requests FOR DELETE TO authenticated
  USING (private.admin_can('attendance','delete'));
