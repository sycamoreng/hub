/*
  # Bulk exempt appraisals

  ## Summary
  Adds `admin_bulk_exempt_appraisals(p_ids uuid[], p_reason text)` so HR can
  mark several appraisals as exempt in one round trip. Internally calls the
  same logic as `admin_exempt_appraisal`: flips status, prefixes notes with
  the reason and cancels any open reviews for that cycle/subject.

  ## Security
  - SECURITY DEFINER, admin-only via `is_admin()`.
  - EXECUTE granted to `authenticated`.
*/

CREATE OR REPLACE FUNCTION public.admin_bulk_exempt_appraisals(p_ids uuid[], p_reason text DEFAULT '')
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_count integer := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN 0;
  END IF;

  FOREACH v_id IN ARRAY p_ids LOOP
    BEGIN
      PERFORM public.admin_exempt_appraisal(v_id, p_reason);
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      -- skip rows that fail (e.g. deleted between selection and submit)
      CONTINUE;
    END;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bulk_exempt_appraisals(uuid[], text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bulk_exempt_appraisals(uuid[], text) TO authenticated;
