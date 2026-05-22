/*
  # Copy objectives between performance cycles

  ## Summary
  Adds an RPC function that allows admins to copy all objectives (and their
  child measures) from one performance cycle to another. This enables quick
  setup of a new cycle by carrying forward objectives from the previous one.

  ## New functions
  1. `copy_objectives_between_cycles(p_source_cycle_id, p_target_cycle_id, p_include_measures, p_reset_progress)`
     - Copies all objectives from source cycle to target cycle
     - Optionally copies child measures
     - Optionally resets progress/status to draft/0
     - Returns the count of objectives copied
     - Only accessible by admins with performance:create permission

  ## Security
  - Function is SECURITY DEFINER to bypass RLS for bulk insert
  - Execute permission restricted to authenticated users
  - Internal check ensures caller has admin performance:create permission

  ## Important notes
  1. Objectives are copied with new UUIDs
  2. Measures are re-linked to the new objective UUIDs
  3. Progress and status are reset by default so the new cycle starts clean
  4. Existing objectives in the target cycle are NOT removed
*/

CREATE OR REPLACE FUNCTION public.copy_objectives_between_cycles(
  p_source_cycle_id uuid,
  p_target_cycle_id uuid,
  p_include_measures boolean DEFAULT true,
  p_reset_progress boolean DEFAULT true
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_count integer := 0;
  v_obj record;
  v_new_obj_id uuid;
BEGIN
  -- Verify caller is an admin with performance:create
  IF NOT private.admin_can('performance', 'create') THEN
    RAISE EXCEPTION 'Permission denied: requires performance:create admin permission';
  END IF;

  -- Verify both cycles exist
  IF NOT EXISTS (SELECT 1 FROM performance_cycles WHERE id = p_source_cycle_id) THEN
    RAISE EXCEPTION 'Source cycle not found';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM performance_cycles WHERE id = p_target_cycle_id) THEN
    RAISE EXCEPTION 'Target cycle not found';
  END IF;

  -- Loop through objectives in the source cycle
  FOR v_obj IN
    SELECT * FROM performance_objectives WHERE cycle_id = p_source_cycle_id
  LOOP
    v_new_obj_id := gen_random_uuid();

    INSERT INTO performance_objectives (
      id, cycle_id, staff_id, framework_id, kind, title, description,
      category, weight, target_value, status, progress, rating,
      manager_notes, staff_notes, sort_order, created_by
    ) VALUES (
      v_new_obj_id,
      p_target_cycle_id,
      v_obj.staff_id,
      v_obj.framework_id,
      v_obj.kind,
      v_obj.title,
      v_obj.description,
      v_obj.category,
      v_obj.weight,
      v_obj.target_value,
      CASE WHEN p_reset_progress THEN 'draft' ELSE v_obj.status END,
      CASE WHEN p_reset_progress THEN 0 ELSE v_obj.progress END,
      CASE WHEN p_reset_progress THEN NULL ELSE v_obj.rating END,
      '',
      '',
      v_obj.sort_order,
      auth.uid()
    );

    -- Copy measures if requested
    IF p_include_measures THEN
      INSERT INTO performance_measures (
        objective_id, label, description, unit, baseline_value,
        target_value, current_value, weight, progress, status, sort_order
      )
      SELECT
        v_new_obj_id,
        m.label,
        m.description,
        m.unit,
        m.baseline_value,
        m.target_value,
        CASE WHEN p_reset_progress THEN '' ELSE m.current_value END,
        m.weight,
        CASE WHEN p_reset_progress THEN 0 ELSE m.progress END,
        CASE WHEN p_reset_progress THEN 'pending' ELSE m.status END,
        m.sort_order
      FROM performance_measures m
      WHERE m.objective_id = v_obj.id;
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.copy_objectives_between_cycles(uuid, uuid, boolean, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.copy_objectives_between_cycles(uuid, uuid, boolean, boolean) TO authenticated;
