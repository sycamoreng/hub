/*
  # Allow managers to award recognition to their reports

  ## Summary
  Managers (direct reports only, via `private.is_manager_of`) can now create
  recognition records for staff they manage, without needing HR admin rights.
  This unlocks the "give recognition" action on the client-side team tab.

  ## Security changes
  1. Adds INSERT policy on `performance_recognitions` for managers where
     `awarded_by` matches their own staff id AND they manage the subject.
  2. Existing admin insert/update/delete policies remain untouched.
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'performance_recognitions'
      AND policyname = 'Manager inserts recognitions'
  ) THEN
    CREATE POLICY "Manager inserts recognitions"
      ON public.performance_recognitions FOR INSERT TO authenticated
      WITH CHECK (
        awarded_by = private.current_staff_id()
        AND private.is_manager_of(subject_staff_id)
      );
  END IF;
END $$;
