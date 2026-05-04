/*
  # Schedule templates (organization and group)

  Admins can now create reusable schedule templates: one organization-wide
  default plus per-department and per-location group schedules. Staff's
  effective schedule is resolved in the UI as:

    per-staff override → department template → location template → org default

  1. New tables
    - `schedule_templates` — one row per template (org / department / location)
      with a default flag per scope.
    - `schedule_template_days` — weekly pattern rows (0=Sunday..6=Saturday)
      belonging to a template.

  2. Security
    - Authenticated users can read templates (needed so staff can see their
      effective schedule when no personal override exists).
    - Writes restricted to attendance admins (via `is_attendance_admin()`).
*/

CREATE TABLE IF NOT EXISTS schedule_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  scope text NOT NULL DEFAULT 'organization' CHECK (scope IN ('organization','department','location')),
  department_id uuid REFERENCES departments(id) ON DELETE CASCADE,
  location_id uuid REFERENCES locations(id) ON DELETE CASCADE,
  is_default boolean DEFAULT false,
  notes text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS schedule_templates_scope_idx ON schedule_templates(scope);
CREATE INDEX IF NOT EXISTS schedule_templates_department_idx ON schedule_templates(department_id);
CREATE INDEX IF NOT EXISTS schedule_templates_location_idx ON schedule_templates(location_id);

CREATE TABLE IF NOT EXISTS schedule_template_days (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid NOT NULL REFERENCES schedule_templates(id) ON DELETE CASCADE,
  weekday int NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  is_working boolean DEFAULT true,
  start_time time DEFAULT '09:00',
  end_time time DEFAULT '17:00',
  UNIQUE (template_id, weekday)
);

ALTER TABLE schedule_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE schedule_template_days ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read templates"
  ON schedule_templates FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "Admins insert templates"
  ON schedule_templates FOR INSERT TO authenticated
  WITH CHECK (is_attendance_admin());
CREATE POLICY "Admins update templates"
  ON schedule_templates FOR UPDATE TO authenticated
  USING (is_attendance_admin())
  WITH CHECK (is_attendance_admin());
CREATE POLICY "Admins delete templates"
  ON schedule_templates FOR DELETE TO authenticated
  USING (is_attendance_admin());

CREATE POLICY "Authenticated read template days"
  ON schedule_template_days FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "Admins insert template days"
  ON schedule_template_days FOR INSERT TO authenticated
  WITH CHECK (is_attendance_admin());
CREATE POLICY "Admins update template days"
  ON schedule_template_days FOR UPDATE TO authenticated
  USING (is_attendance_admin())
  WITH CHECK (is_attendance_admin());
CREATE POLICY "Admins delete template days"
  ON schedule_template_days FOR DELETE TO authenticated
  USING (is_attendance_admin());
