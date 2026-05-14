/*
  # Fix admin helper used by appraisal RPCs

  1. Problem
    - `admin_exempt_appraisal`, `admin_reset_appraisal`, and
      `admin_bulk_exempt_appraisals` referenced `public.is_admin()`,
      which does not exist in this project. The correct helpers are
      `private.admin_can(section, action)` and `public.is_super_admin()`.

  2. Changes
    - Recreate the three RPCs to gate access via
      `private.admin_can('performance','manage')`, falling back to
      `public.is_super_admin()`.
    - Behaviour otherwise unchanged.

  3. Security
    - Functions remain SECURITY DEFINER with fixed search_path.
    - Re-grant EXECUTE to authenticated.
*/

CREATE OR REPLACE FUNCTION public.admin_exempt_appraisal(p_appraisal_id uuid, p_reason text DEFAULT '')
RETURNS performance_appraisals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  a performance_appraisals;
BEGIN
  IF NOT (public.is_super_admin() OR private.admin_can('performance','manage')) THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  UPDATE public.performance_appraisals
  SET status = 'exempt',
      notes = CASE WHEN coalesce(p_reason,'') = '' THEN notes
                   ELSE 'Exempt: ' || p_reason END,
      updated_at = now()
  WHERE id = p_appraisal_id
  RETURNING * INTO a;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'appraisal not found';
  END IF;

  UPDATE public.performance_reviews
  SET status = 'cancelled',
      updated_at = now()
  WHERE cycle_id = a.cycle_id
    AND subject_staff_id = a.subject_staff_id
    AND status IN ('invited','in_progress');

  RETURN a;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_reset_appraisal(p_appraisal_id uuid)
RETURNS performance_appraisals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  a performance_appraisals;
BEGIN
  IF NOT (public.is_super_admin() OR private.admin_can('performance','manage')) THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  UPDATE public.performance_appraisals
  SET status = 'pending',
      self_score = NULL,
      manager_score = NULL,
      final_score = NULL,
      notes = NULL,
      submitted_at = NULL,
      reviewed_at = NULL,
      finalized_at = NULL,
      updated_at = now()
  WHERE id = p_appraisal_id
  RETURNING * INTO a;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'appraisal not found';
  END IF;

  UPDATE public.performance_reviews
  SET status = 'invited',
      updated_at = now()
  WHERE cycle_id = a.cycle_id
    AND subject_staff_id = a.subject_staff_id
    AND status IN ('cancelled','submitted');

  RETURN a;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_bulk_exempt_appraisals(p_ids uuid[], p_reason text DEFAULT '')
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  i uuid;
  c integer := 0;
BEGIN
  IF NOT (public.is_super_admin() OR private.admin_can('performance','manage')) THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  IF p_ids IS NULL THEN
    RETURN 0;
  END IF;

  FOREACH i IN ARRAY p_ids LOOP
    BEGIN
      PERFORM public.admin_exempt_appraisal(i, p_reason);
      c := c + 1;
    EXCEPTION WHEN OTHERS THEN
      -- swallow individual failures, continue batch
      NULL;
    END;
  END LOOP;

  RETURN c;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_exempt_appraisal(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reset_appraisal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_bulk_exempt_appraisals(uuid[], text) TO authenticated;
