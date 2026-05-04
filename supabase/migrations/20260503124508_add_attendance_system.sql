/*
  # Attendance & clock-in system

  Adds a staff attendance module: admins can assign weekly schedules
  per staff, optionally mark day overrides (holidays, days off), and
  staff can clock in / clock out of their scheduled shift.

  1. New tables
    - `staff_schedules` — per-staff weekly pattern. One row per weekday.
      Columns: staff_id, weekday (0=Sunday..6=Saturday), start_time,
      end_time, location_id, is_working.
    - `attendance_days` — date-based overrides (holiday, closed, special).
      Applies to all staff unless staff_id is set.
    - `attendance_records` — actual clock-in/out events per staff per
      calendar day. Unique (staff_id, work_date).

  2. Security
    - RLS enabled on every new table.
    - Staff can SELECT + UPSERT their own `attendance_records`.
    - Staff can SELECT their own `staff_schedules` and all
      `attendance_days` (so they can see holidays).
    - Admins with `attendance` section (or super_admin) manage everything.

  3. Notes
    1. `work_date` stored as `date` so a single day has one record
       even if the user clocks in across midnight edge cases.
    2. Minutes-late and total-hours are computed client-side from
       timestamps and the schedule; not stored to keep this simple.
*/

CREATE TABLE IF NOT EXISTS staff_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES staff_members(id) ON DELETE CASCADE,
  weekday int NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  is_working boolean DEFAULT true,
  start_time time DEFAULT '09:00',
  end_time time DEFAULT '17:00',
  location_id uuid REFERENCES locations(id) ON DELETE SET NULL,
  notes text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (staff_id, weekday)
);

CREATE INDEX IF NOT EXISTS staff_schedules_staff_idx ON staff_schedules(staff_id);

CREATE TABLE IF NOT EXISTS attendance_days (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  day date NOT NULL,
  staff_id uuid REFERENCES staff_members(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'holiday' CHECK (kind IN ('holiday','closed','leave','custom')),
  label text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  UNIQUE (day, staff_id)
);

CREATE INDEX IF NOT EXISTS attendance_days_day_idx ON attendance_days(day);

CREATE TABLE IF NOT EXISTS attendance_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES staff_members(id) ON DELETE CASCADE,
  work_date date NOT NULL,
  clock_in_at timestamptz,
  clock_out_at timestamptz,
  expected_start time,
  expected_end time,
  notes text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (staff_id, work_date)
);

CREATE INDEX IF NOT EXISTS attendance_records_staff_date_idx ON attendance_records(staff_id, work_date);
CREATE INDEX IF NOT EXISTS attendance_records_date_idx ON attendance_records(work_date);

ALTER TABLE staff_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_days ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;

-- helper: admin with attendance section
CREATE OR REPLACE FUNCTION is_attendance_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users au
    WHERE lower(au.email) = lower(coalesce(auth.jwt() ->> 'email',''))
      AND (au.role = 'super_admin' OR 'attendance' = ANY(au.sections))
  );
$$;

REVOKE ALL ON FUNCTION is_attendance_admin() FROM public;
GRANT EXECUTE ON FUNCTION is_attendance_admin() TO authenticated;

-- staff_schedules policies
CREATE POLICY "Admins read schedules"
  ON staff_schedules FOR SELECT TO authenticated
  USING (is_attendance_admin());
CREATE POLICY "Staff read own schedule"
  ON staff_schedules FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM staff_members sm WHERE sm.id = staff_schedules.staff_id AND sm.auth_user_id = auth.uid()));
CREATE POLICY "Admins insert schedules"
  ON staff_schedules FOR INSERT TO authenticated
  WITH CHECK (is_attendance_admin());
CREATE POLICY "Admins update schedules"
  ON staff_schedules FOR UPDATE TO authenticated
  USING (is_attendance_admin())
  WITH CHECK (is_attendance_admin());
CREATE POLICY "Admins delete schedules"
  ON staff_schedules FOR DELETE TO authenticated
  USING (is_attendance_admin());

-- attendance_days policies
CREATE POLICY "Authenticated read attendance days"
  ON attendance_days FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "Admins insert attendance days"
  ON attendance_days FOR INSERT TO authenticated
  WITH CHECK (is_attendance_admin());
CREATE POLICY "Admins update attendance days"
  ON attendance_days FOR UPDATE TO authenticated
  USING (is_attendance_admin())
  WITH CHECK (is_attendance_admin());
CREATE POLICY "Admins delete attendance days"
  ON attendance_days FOR DELETE TO authenticated
  USING (is_attendance_admin());

-- attendance_records policies
CREATE POLICY "Admins read all records"
  ON attendance_records FOR SELECT TO authenticated
  USING (is_attendance_admin());
CREATE POLICY "Staff read own records"
  ON attendance_records FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM staff_members sm WHERE sm.id = attendance_records.staff_id AND sm.auth_user_id = auth.uid()));
CREATE POLICY "Staff insert own records"
  ON attendance_records FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM staff_members sm WHERE sm.id = attendance_records.staff_id AND sm.auth_user_id = auth.uid()));
CREATE POLICY "Staff update own records"
  ON attendance_records FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM staff_members sm WHERE sm.id = attendance_records.staff_id AND sm.auth_user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM staff_members sm WHERE sm.id = attendance_records.staff_id AND sm.auth_user_id = auth.uid()));
CREATE POLICY "Admins update records"
  ON attendance_records FOR UPDATE TO authenticated
  USING (is_attendance_admin())
  WITH CHECK (is_attendance_admin());
CREATE POLICY "Admins delete records"
  ON attendance_records FOR DELETE TO authenticated
  USING (is_attendance_admin());
