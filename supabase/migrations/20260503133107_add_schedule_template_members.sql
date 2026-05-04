/*
  # Schedule template members

  Adds an explicit membership table so admins can attach any set of
  staff members to a schedule template as an ad-hoc group. This does
  not replace scope (organization/department/location); it is an
  additional, highest-priority way to pick who a template applies to.

  Effective schedule resolution (client-side) becomes:
    personal override → explicit membership → department default →
    location default → organization default.

  1. New tables
    - `schedule_template_members` — (template_id, staff_id) pairs.

  2. Security
    - RLS enabled.
    - Authenticated users can read (needed so staff can see their
      own effective schedule).
    - Writes restricted to attendance admins.
*/

CREATE TABLE IF NOT EXISTS schedule_template_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid NOT NULL REFERENCES schedule_templates(id) ON DELETE CASCADE,
  staff_id uuid NOT NULL REFERENCES staff_members(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE (template_id, staff_id)
);

CREATE INDEX IF NOT EXISTS schedule_template_members_template_idx ON schedule_template_members(template_id);
CREATE INDEX IF NOT EXISTS schedule_template_members_staff_idx ON schedule_template_members(staff_id);

ALTER TABLE schedule_template_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read template members"
  ON schedule_template_members FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "Admins insert template members"
  ON schedule_template_members FOR INSERT TO authenticated
  WITH CHECK (is_attendance_admin());
CREATE POLICY "Admins delete template members"
  ON schedule_template_members FOR DELETE TO authenticated
  USING (is_attendance_admin());
