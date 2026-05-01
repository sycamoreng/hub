/*
  # Learning assignments

  Morphs onboarding into a full LMS where admins can assign lessons to a
  specific user, to a whole department, or to the entire organization.

  1. New Tables
    - `learning_assignments`
      - `id` (uuid, primary key)
      - `step_id` (uuid, fk onboarding_steps, cascade delete)
      - `scope_type` (text: 'user' | 'department' | 'organization')
      - `scope_id` (uuid, nullable — user_profile id, department id, or null for organization)
      - `due_date` (date, nullable)
      - `assigned_by` (uuid, nullable, fk auth.users)
      - `created_at` (timestamptz, default now())
    - Unique (step_id, scope_type, coalesce(scope_id, '00000000-...'))

  2. Security
    - RLS enabled.
    - Authenticated users can SELECT assignments that concern them (their own
      user id, their department, or organization-scope rows).
    - Only admins with `onboarding` section permission can INSERT/UPDATE/DELETE.

  3. Helpers
    - `public.user_assigned_step_ids()` returns the set of step ids visible to
      the current auth user based on their staff_members.department_id and
      user_profiles.id. Returned set also implicitly includes org-wide rows.

  4. Notes
    - Existing onboarding_steps/onboarding_resources are untouched.
    - If there are NO assignments for a step at all, that step is NOT shown to
      users — admins must assign it. Admins still see everything via the
      admin page.
*/

CREATE TABLE IF NOT EXISTS public.learning_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id uuid NOT NULL REFERENCES public.onboarding_steps(id) ON DELETE CASCADE,
  scope_type text NOT NULL CHECK (scope_type IN ('user', 'department', 'organization')),
  scope_id uuid,
  due_date date,
  assigned_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT learning_assignments_scope_check CHECK (
    (scope_type = 'organization' AND scope_id IS NULL)
    OR (scope_type IN ('user', 'department') AND scope_id IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS learning_assignments_unique_idx
  ON public.learning_assignments (step_id, scope_type, COALESCE(scope_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE INDEX IF NOT EXISTS learning_assignments_step_idx ON public.learning_assignments(step_id);
CREATE INDEX IF NOT EXISTS learning_assignments_scope_idx ON public.learning_assignments(scope_type, scope_id);

ALTER TABLE public.learning_assignments ENABLE ROW LEVEL SECURITY;

-- SELECT: users see assignments that target them (user, their dept, or org-wide)
DROP POLICY IF EXISTS "Users read assignments that apply to them" ON public.learning_assignments;
CREATE POLICY "Users read assignments that apply to them"
  ON public.learning_assignments
  FOR SELECT
  TO authenticated
  USING (
    scope_type = 'organization'
    OR (
      scope_type = 'user'
      AND scope_id IN (SELECT id FROM public.user_profiles WHERE id = auth.uid())
    )
    OR (
      scope_type = 'department'
      AND scope_id IN (
        SELECT sm.department_id
        FROM public.staff_members sm
        WHERE sm.auth_user_id = auth.uid()
          AND sm.department_id IS NOT NULL
      )
    )
    OR private.admin_can('onboarding', 'read')
  );

DROP POLICY IF EXISTS "Onboarding admins insert assignments" ON public.learning_assignments;
CREATE POLICY "Onboarding admins insert assignments"
  ON public.learning_assignments
  FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('onboarding', 'create'));

DROP POLICY IF EXISTS "Onboarding admins update assignments" ON public.learning_assignments;
CREATE POLICY "Onboarding admins update assignments"
  ON public.learning_assignments
  FOR UPDATE
  TO authenticated
  USING (private.admin_can('onboarding', 'update'))
  WITH CHECK (private.admin_can('onboarding', 'update'));

DROP POLICY IF EXISTS "Onboarding admins delete assignments" ON public.learning_assignments;
CREATE POLICY "Onboarding admins delete assignments"
  ON public.learning_assignments
  FOR DELETE
  TO authenticated
  USING (private.admin_can('onboarding', 'delete'));

-- Helper RPC: step ids visible to current user via any assignment path.
CREATE OR REPLACE FUNCTION public.user_assigned_step_ids()
RETURNS TABLE(step_id uuid, due_date date)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH me AS (
    SELECT auth.uid() AS uid
  ),
  my_dept AS (
    SELECT DISTINCT sm.department_id
    FROM public.staff_members sm, me
    WHERE sm.auth_user_id = me.uid
      AND sm.department_id IS NOT NULL
  )
  SELECT la.step_id, MIN(la.due_date) AS due_date
  FROM public.learning_assignments la, me
  WHERE la.scope_type = 'organization'
     OR (la.scope_type = 'user' AND la.scope_id = me.uid)
     OR (la.scope_type = 'department' AND la.scope_id IN (SELECT department_id FROM my_dept))
  GROUP BY la.step_id;
$$;

REVOKE ALL ON FUNCTION public.user_assigned_step_ids() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.user_assigned_step_ids() TO authenticated;