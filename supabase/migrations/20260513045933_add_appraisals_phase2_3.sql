/*
  # Performance Appraisals Phase 2 & 3

  1. New Tables
    - `performance_objective_templates` — reusable Company / Departmental objective templates that staff and managers can adopt into a cycle.
    - `performance_core_values` — core values used in behavioural assessments (name, description, behaviour anchors, weight, sort order).

  2. Updates
    - `compute_appraisal_score` now also auto-fills `nine_box_position` and `rating_tag` (only when blank) from final & behavioural scores.

  3. Security
    - Templates: authenticated read; admin manage.
    - Core values: authenticated read; admin manage.
*/

-- Objective templates ---------------------------------------------------------

CREATE TABLE IF NOT EXISTS performance_objective_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid REFERENCES performance_cycles(id) ON DELETE CASCADE,
  scope text NOT NULL DEFAULT 'company',
  department_id uuid REFERENCES departments(id) ON DELETE CASCADE,
  framework_id uuid REFERENCES performance_frameworks(id) ON DELETE SET NULL,
  kind text NOT NULL DEFAULT 'okr',
  category text NOT NULL DEFAULT 'company',
  title text NOT NULL,
  description text DEFAULT '',
  default_weight numeric(5,2) DEFAULT 10,
  target_value text DEFAULT '',
  sort_order int DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT performance_objective_templates_scope_chk CHECK (scope IN ('company','department'))
);

CREATE INDEX IF NOT EXISTS performance_objective_templates_cycle_idx ON performance_objective_templates(cycle_id);
CREATE INDEX IF NOT EXISTS performance_objective_templates_department_idx ON performance_objective_templates(department_id);

ALTER TABLE performance_objective_templates ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_objective_templates' AND policyname='Authenticated read templates') THEN
    CREATE POLICY "Authenticated read templates"
      ON performance_objective_templates FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_objective_templates' AND policyname='Admins insert templates') THEN
    CREATE POLICY "Admins insert templates"
      ON performance_objective_templates FOR INSERT TO authenticated
      WITH CHECK (private.admin_can('performance','create'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_objective_templates' AND policyname='Admins update templates') THEN
    CREATE POLICY "Admins update templates"
      ON performance_objective_templates FOR UPDATE TO authenticated
      USING (private.admin_can('performance','update'))
      WITH CHECK (private.admin_can('performance','update'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_objective_templates' AND policyname='Admins delete templates') THEN
    CREATE POLICY "Admins delete templates"
      ON performance_objective_templates FOR DELETE TO authenticated
      USING (private.admin_can('performance','delete'));
  END IF;
END $$;

-- Core values -----------------------------------------------------------------

CREATE TABLE IF NOT EXISTS performance_core_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text DEFAULT '',
  behaviour_anchors text DEFAULT '',
  weight numeric(5,2) DEFAULT 1,
  sort_order int DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE performance_core_values ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_core_values' AND policyname='Authenticated read core values') THEN
    CREATE POLICY "Authenticated read core values"
      ON performance_core_values FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_core_values' AND policyname='Admins insert core values') THEN
    CREATE POLICY "Admins insert core values"
      ON performance_core_values FOR INSERT TO authenticated
      WITH CHECK (private.admin_can('performance','create'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_core_values' AND policyname='Admins update core values') THEN
    CREATE POLICY "Admins update core values"
      ON performance_core_values FOR UPDATE TO authenticated
      USING (private.admin_can('performance','update'))
      WITH CHECK (private.admin_can('performance','update'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_core_values' AND policyname='Admins delete core values') THEN
    CREATE POLICY "Admins delete core values"
      ON performance_core_values FOR DELETE TO authenticated
      USING (private.admin_can('performance','delete'));
  END IF;
END $$;

-- Compute score: now also fills 9-box and rating tag automatically -----------

CREATE OR REPLACE FUNCTION public.compute_appraisal_score(p_appraisal_id uuid)
RETURNS performance_appraisals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  a performance_appraisals;
  v_obj numeric;
  v_weights numeric;
  v_beh numeric;
  v_final numeric;
  v_label text;
  v_perf_band text;
  v_pot_band text;
  v_box text;
  v_tag text;
BEGIN
  SELECT * INTO a FROM performance_appraisals WHERE id = p_appraisal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'appraisal not found'; END IF;

  SELECT
    COALESCE(SUM(progress * NULLIF(weight,0)),0),
    COALESCE(SUM(NULLIF(weight,0)),0)
  INTO v_obj, v_weights
  FROM performance_objectives
  WHERE cycle_id = a.cycle_id AND staff_id = a.subject_staff_id AND status <> 'dropped';

  IF v_weights > 0 THEN
    v_obj := (v_obj / v_weights) / 20.0;
  ELSE
    v_obj := 0;
  END IF;

  SELECT COALESCE(AVG(rr.score), 0)
  INTO v_beh
  FROM performance_review_ratings rr
  JOIN performance_reviews r ON r.id = rr.review_id
  WHERE r.cycle_id = a.cycle_id
    AND r.subject_staff_id = a.subject_staff_id
    AND r.status = 'submitted'
    AND rr.objective_id IS NULL
    AND rr.score IS NOT NULL;

  v_final := ROUND(((v_obj * a.objective_weight) + (v_beh * a.behavioural_weight)) / NULLIF(a.objective_weight + a.behavioural_weight, 0), 2);

  v_label := CASE
    WHEN v_final IS NULL THEN ''
    WHEN v_final >= 4.5 THEN 'Outstanding'
    WHEN v_final >= 3.5 THEN 'Exceeds expectation'
    WHEN v_final >= 2.5 THEN 'Meets expectation'
    WHEN v_final >= 1.5 THEN 'Below expectation'
    ELSE 'Unsatisfactory'
  END;

  v_perf_band := CASE
    WHEN v_obj >= 3.5 THEN 'high'
    WHEN v_obj >= 2.5 THEN 'medium'
    ELSE 'low'
  END;
  v_pot_band := CASE
    WHEN v_beh >= 3.5 THEN 'high'
    WHEN v_beh >= 2.5 THEN 'medium'
    ELSE 'low'
  END;

  v_box := CASE v_perf_band || '/' || v_pot_band
    WHEN 'low/low' THEN 'Low Performer / Low Potential'
    WHEN 'medium/low' THEN 'Solid Performer / Low Potential'
    WHEN 'high/low' THEN 'High Performer / Low Potential'
    WHEN 'low/medium' THEN 'Low Performer / Medium Potential'
    WHEN 'medium/medium' THEN 'Core Player'
    WHEN 'high/medium' THEN 'High Performer / Medium Potential'
    WHEN 'low/high' THEN 'Enigma'
    WHEN 'medium/high' THEN 'Growth Employee'
    WHEN 'high/high' THEN 'Future Leader'
    ELSE ''
  END;

  v_tag := CASE
    WHEN v_perf_band = 'high' AND v_pot_band = 'high' THEN 'Consistent Star'
    WHEN v_perf_band = 'high' AND v_pot_band = 'medium' THEN 'Reliable Performer'
    WHEN v_perf_band = 'medium' AND v_pot_band = 'high' THEN 'Rising Talent'
    WHEN v_perf_band = 'medium' AND v_pot_band = 'medium' THEN 'Core Player'
    WHEN v_perf_band = 'low' AND v_pot_band = 'high' THEN 'Misaligned Talent'
    WHEN v_perf_band = 'low' AND v_pot_band = 'low' THEN 'Underperformer'
    ELSE 'Developing'
  END;

  UPDATE performance_appraisals
  SET objective_score = ROUND(v_obj,2),
      behavioural_score = ROUND(v_beh,2),
      final_score = COALESCE(v_final,0),
      rating_label = v_label,
      nine_box_position = CASE WHEN COALESCE(nine_box_position,'') = '' THEN v_box ELSE nine_box_position END,
      rating_tag = CASE WHEN COALESCE(rating_tag,'') = '' THEN v_tag ELSE rating_tag END,
      updated_at = now()
  WHERE id = p_appraisal_id
  RETURNING * INTO a;

  RETURN a;
END;
$$;

REVOKE ALL ON FUNCTION public.compute_appraisal_score(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_appraisal_score(uuid) TO authenticated;
