/*
  # Performance Appraisals Phase 1

  1. New Tables
    - `performance_appraisals` — one row per (cycle, staff). Captures the staff member's primary appraiser, computed objective/behavioural/final scores, rating label, rating tag, 9-box position, status, and submission timestamps.

  2. New Functions
    - `compute_appraisal_score(appraisal_id)` — recalculates objective_score (weighted average of objective.progress * objective.weight), behavioural_score (avg of competency review ratings), and final_score (configurable blend, default 70/30). Updates rating_label using a 5-band scale.
    - `admin_reassign_appraiser(appraisal_id, new_appraiser_staff_id)` — security definer RPC; admins only. Reassigns the appraisal's primary appraiser AND updates any open manager-type review for that cycle/subject to the new reviewer (or creates one if missing).

  3. Security
    - RLS enabled. Subjects read their own appraisal; managers read appraisals where they are appraiser or manager-of-subject; admins manage all.
    - Reassign RPC enforces admin via private.admin_can('performance', 'update').
*/

CREATE TABLE IF NOT EXISTS performance_appraisals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id uuid NOT NULL REFERENCES performance_cycles(id) ON DELETE CASCADE,
  subject_staff_id uuid NOT NULL REFERENCES staff_members(id) ON DELETE CASCADE,
  appraiser_staff_id uuid REFERENCES staff_members(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'not_started',
  objective_score numeric(6,2) DEFAULT 0,
  behavioural_score numeric(6,2) DEFAULT 0,
  objective_weight numeric(5,2) NOT NULL DEFAULT 70,
  behavioural_weight numeric(5,2) NOT NULL DEFAULT 30,
  final_score numeric(6,2) DEFAULT 0,
  rating_label text DEFAULT '',
  rating_tag text DEFAULT '',
  nine_box_position text DEFAULT '',
  notes text DEFAULT '',
  submitted_at timestamptz,
  finalized_at timestamptz,
  finalized_by uuid REFERENCES staff_members(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT performance_appraisals_unique UNIQUE (cycle_id, subject_staff_id),
  CONSTRAINT performance_appraisals_status_chk CHECK (status IN ('not_started','in_progress','submitted','finalized','reopened'))
);

CREATE INDEX IF NOT EXISTS performance_appraisals_cycle_idx ON performance_appraisals(cycle_id);
CREATE INDEX IF NOT EXISTS performance_appraisals_subject_idx ON performance_appraisals(subject_staff_id);
CREATE INDEX IF NOT EXISTS performance_appraisals_appraiser_idx ON performance_appraisals(appraiser_staff_id);

ALTER TABLE performance_appraisals ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_appraisals' AND policyname='Subjects read own appraisal') THEN
    CREATE POLICY "Subjects read own appraisal"
      ON performance_appraisals FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM staff_members s WHERE s.id = subject_staff_id AND s.auth_user_id = auth.uid()));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_appraisals' AND policyname='Appraisers read assigned') THEN
    CREATE POLICY "Appraisers read assigned"
      ON performance_appraisals FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM staff_members s WHERE s.id = appraiser_staff_id AND s.auth_user_id = auth.uid()));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_appraisals' AND policyname='Admins read all appraisals') THEN
    CREATE POLICY "Admins read all appraisals"
      ON performance_appraisals FOR SELECT TO authenticated
      USING (private.admin_can('performance','read'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_appraisals' AND policyname='Admins insert appraisals') THEN
    CREATE POLICY "Admins insert appraisals"
      ON performance_appraisals FOR INSERT TO authenticated
      WITH CHECK (private.admin_can('performance','create'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_appraisals' AND policyname='Admins update appraisals') THEN
    CREATE POLICY "Admins update appraisals"
      ON performance_appraisals FOR UPDATE TO authenticated
      USING (private.admin_can('performance','update'))
      WITH CHECK (private.admin_can('performance','update'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_appraisals' AND policyname='Appraisers update own assigned') THEN
    CREATE POLICY "Appraisers update own assigned"
      ON performance_appraisals FOR UPDATE TO authenticated
      USING (EXISTS (SELECT 1 FROM staff_members s WHERE s.id = appraiser_staff_id AND s.auth_user_id = auth.uid()))
      WITH CHECK (EXISTS (SELECT 1 FROM staff_members s WHERE s.id = appraiser_staff_id AND s.auth_user_id = auth.uid()));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_appraisals' AND policyname='Admins delete appraisals') THEN
    CREATE POLICY "Admins delete appraisals"
      ON performance_appraisals FOR DELETE TO authenticated
      USING (private.admin_can('performance','delete'));
  END IF;
END $$;

-- Score computation -----------------------------------------------------------

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
BEGIN
  SELECT * INTO a FROM performance_appraisals WHERE id = p_appraisal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'appraisal not found'; END IF;

  -- Weighted objective score: sum(progress * weight) / sum(weight). Result on a 0-5 scale.
  SELECT
    COALESCE(SUM(progress * NULLIF(weight,0)),0),
    COALESCE(SUM(NULLIF(weight,0)),0)
  INTO v_obj, v_weights
  FROM performance_objectives
  WHERE cycle_id = a.cycle_id AND staff_id = a.subject_staff_id AND status <> 'dropped';

  IF v_weights > 0 THEN
    v_obj := (v_obj / v_weights) / 20.0; -- 100% -> 5
  ELSE
    v_obj := 0;
  END IF;

  -- Behavioural score: average score of all submitted reviews' competency ratings (objective_id IS NULL).
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

  UPDATE performance_appraisals
  SET objective_score = ROUND(v_obj,2),
      behavioural_score = ROUND(v_beh,2),
      final_score = COALESCE(v_final,0),
      rating_label = v_label,
      updated_at = now()
  WHERE id = p_appraisal_id
  RETURNING * INTO a;

  RETURN a;
END;
$$;

REVOKE ALL ON FUNCTION public.compute_appraisal_score(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_appraisal_score(uuid) TO authenticated;

-- Admin reassign appraiser ----------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_reassign_appraiser(p_appraisal_id uuid, p_new_appraiser_staff_id uuid)
RETURNS performance_appraisals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  a performance_appraisals;
  v_actor uuid;
BEGIN
  IF NOT private.admin_can('performance','update') THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO a FROM performance_appraisals WHERE id = p_appraisal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'appraisal not found'; END IF;

  UPDATE performance_appraisals
  SET appraiser_staff_id = p_new_appraiser_staff_id,
      updated_at = now()
  WHERE id = p_appraisal_id
  RETURNING * INTO a;

  -- Sync the manager-type review for this cycle/subject to the new appraiser.
  SELECT id INTO v_actor FROM staff_members WHERE auth_user_id = auth.uid() LIMIT 1;

  IF EXISTS (
    SELECT 1 FROM performance_reviews
    WHERE cycle_id = a.cycle_id
      AND subject_staff_id = a.subject_staff_id
      AND reviewer_type = 'manager'
      AND status NOT IN ('submitted','declined','cancelled')
  ) THEN
    UPDATE performance_reviews
    SET reviewer_staff_id = p_new_appraiser_staff_id,
        updated_at = now()
    WHERE cycle_id = a.cycle_id
      AND subject_staff_id = a.subject_staff_id
      AND reviewer_type = 'manager'
      AND status NOT IN ('submitted','declined','cancelled');
  ELSIF p_new_appraiser_staff_id IS NOT NULL THEN
    INSERT INTO performance_reviews (cycle_id, subject_staff_id, reviewer_staff_id, reviewer_type, status, invited_by, invited_at)
    VALUES (a.cycle_id, a.subject_staff_id, p_new_appraiser_staff_id, 'manager', 'invited', v_actor, now());
  END IF;

  RETURN a;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reassign_appraiser(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reassign_appraiser(uuid, uuid) TO authenticated;
