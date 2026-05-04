/*
  # Teams and reporting chain

  Adds sub-teams under departments plus a manager chain on staff so the
  organization can be rendered as an organogram and managers can see
  their reports.

  1. New tables
    - `teams` — sub-team under a department with an optional team lead.

  2. Modified tables
    - `staff_members`: adds `manager_id` (self-reference) and `team_id`.
    - `departments`: adds `head_staff_id` linking to a real staff row.

  3. Security
    - Teams: authenticated users can read; writes require the
      `departments` admin section (via `private.admin_can(...)`).
*/

CREATE TABLE IF NOT EXISTS teams (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department_id uuid NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text DEFAULT '',
  lead_staff_id uuid REFERENCES staff_members(id) ON DELETE SET NULL,
  display_order int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS teams_department_idx ON teams(department_id);
CREATE INDEX IF NOT EXISTS teams_lead_idx ON teams(lead_staff_id);

ALTER TABLE teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read teams"
  ON teams FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "Admins insert teams"
  ON teams FOR INSERT TO authenticated
  WITH CHECK (private.admin_can('departments','write'));
CREATE POLICY "Admins update teams"
  ON teams FOR UPDATE TO authenticated
  USING (private.admin_can('departments','write'))
  WITH CHECK (private.admin_can('departments','write'));
CREATE POLICY "Admins delete teams"
  ON teams FOR DELETE TO authenticated
  USING (private.admin_can('departments','write'));

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='staff_members' AND column_name='manager_id') THEN
    ALTER TABLE staff_members ADD COLUMN manager_id uuid REFERENCES staff_members(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='staff_members' AND column_name='team_id') THEN
    ALTER TABLE staff_members ADD COLUMN team_id uuid REFERENCES teams(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='departments' AND column_name='head_staff_id') THEN
    ALTER TABLE departments ADD COLUMN head_staff_id uuid REFERENCES staff_members(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS staff_members_manager_idx ON staff_members(manager_id);
CREATE INDEX IF NOT EXISTS staff_members_team_idx ON staff_members(team_id);
