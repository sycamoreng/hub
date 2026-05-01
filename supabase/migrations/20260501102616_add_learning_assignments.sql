/*
  # Learning assignments

  1. New Tables
    - `learning_assignments`
      - `id` (uuid, pk)
      - `step_id` (uuid, fk -> onboarding_steps, cascade)
      - `scope_type` (text) one of: 'user' | 'department' | 'organization'
      - `scope_id` (uuid, nullable) -- auth user id, department id, or null for organization
      - `due_date` (date, nullable)
      - `assigned_by` (uuid, nullable) -- auth user id of admin who created it
      - `created_at` (timestamptz)

  2. Security
    - Enable RLS
    - SELECT: authenticated users can read assignments that apply to them
      (organization-wide, their department, or their user id)
    - INSERT/UPDATE/DELETE: gated by admin_can('onboarding', action)

  3. Notes
    - `step_id` + `scope_type` + `scope_id` is unique to prevent duplicates
    - Indexed by step_id and by (scope_type, scope_id) for fast lookup
*/

CREATE TABLE IF NOT EXISTS learning_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id uuid NOT NULL REFERENCES onboarding_steps(id) ON DELETE CASCADE,
  scope_type text NOT NULL CHECK (scope_type IN ('user','department','organization')),
  scope_id uuid,
  due_date date,
  assigned_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS learning_assignments_unique_idx
  ON learning_assignments (step_id, scope_type, COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE INDEX IF NOT EXISTS learning_assignments_scope_idx
  ON learning_assignments (scope_type, scope_id);

CREATE INDEX IF NOT EXISTS learning_assignments_step_idx
  ON learning_assignments (step_id);

ALTER TABLE learning_assignments ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='learning_assignments' AND policyname='Authenticated can read applicable assignments') THEN
    CREATE POLICY "Authenticated can read applicable assignments"
      ON learning_assignments FOR SELECT
      TO authenticated
      USING (
        scope_type = 'organization'
        OR (scope_type = 'user' AND scope_id = auth.uid())
        OR (
          scope_type = 'department'
          AND EXISTS (
            SELECT 1 FROM staff_members sm
            WHERE sm.auth_user_id = auth.uid()
              AND sm.department_id = learning_assignments.scope_id
          )
        )
        OR private.admin_can('onboarding','view')
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='learning_assignments' AND policyname='Admins insert assignments') THEN
    CREATE POLICY "Admins insert assignments"
      ON learning_assignments FOR INSERT
      TO authenticated
      WITH CHECK (private.admin_can('onboarding','create'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='learning_assignments' AND policyname='Admins update assignments') THEN
    CREATE POLICY "Admins update assignments"
      ON learning_assignments FOR UPDATE
      TO authenticated
      USING (private.admin_can('onboarding','update'))
      WITH CHECK (private.admin_can('onboarding','update'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='learning_assignments' AND policyname='Admins delete assignments') THEN
    CREATE POLICY "Admins delete assignments"
      ON learning_assignments FOR DELETE
      TO authenticated
      USING (private.admin_can('onboarding','delete'));
  END IF;
END $$;