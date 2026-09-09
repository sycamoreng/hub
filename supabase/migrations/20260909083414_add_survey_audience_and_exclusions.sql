/*
  # Survey audience targeting, department exclusions, and access helper

  1. New Columns
    - `surveys.audience_type` (text) — who receives the survey: `all` (whole organisation),
      `departments` (only listed departments), or `staff` (only listed people). Default `all`.
    - `surveys.audience_department_ids` (jsonb) — array of department ids the survey targets when
      `audience_type = 'departments'`.
    - `surveys.audience_staff_ids` (jsonb) — array of auth user ids the survey targets when
      `audience_type = 'staff'`.
    - `survey_questions.excluded_department_ids` (jsonb) — for `department_rating` questions, the
      departments an admin chose NOT to be rated. Respondents never rate their own department either.

  2. New Function
    - `private.can_see_survey(uuid)` — SECURITY DEFINER helper returning true when the current user is
      inside a survey's audience AND the survey is open or closed. Used by RLS so staff only ever see
      surveys addressed to them. Runs as owner so it can read `surveys` and `staff_members` without
      recursing through their policies.

  3. Security
    - Rewrites the SELECT policies on `surveys` and `survey_questions` and the INSERT policy on
      `survey_responses` so non-admins are limited to surveys in their audience. Admins with the
      `surveys` permission keep full read access (including drafts).

  4. Notes
    1. Existing surveys default to `audience_type = 'all'`, so nothing already published changes who
       can see it.
    2. The helper treats an empty target list as "no one matches", which is the safe default.
*/

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'surveys' AND column_name = 'audience_type') THEN
    ALTER TABLE surveys ADD COLUMN audience_type text NOT NULL DEFAULT 'all' CHECK (audience_type IN ('all', 'departments', 'staff'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'surveys' AND column_name = 'audience_department_ids') THEN
    ALTER TABLE surveys ADD COLUMN audience_department_ids jsonb NOT NULL DEFAULT '[]'::jsonb;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'surveys' AND column_name = 'audience_staff_ids') THEN
    ALTER TABLE surveys ADD COLUMN audience_staff_ids jsonb NOT NULL DEFAULT '[]'::jsonb;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'survey_questions' AND column_name = 'excluded_department_ids') THEN
    ALTER TABLE survey_questions ADD COLUMN excluded_department_ids jsonb NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION private.can_see_survey(s_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.surveys s
    WHERE s.id = s_id
      AND s.status IN ('open', 'closed')
      AND (
        s.audience_type = 'all'
        OR (
          s.audience_type = 'departments'
          AND EXISTS (
            SELECT 1 FROM public.staff_members sm
            WHERE sm.auth_user_id = auth.uid()
              AND sm.department_id::text IN (SELECT jsonb_array_elements_text(s.audience_department_ids))
          )
        )
        OR (
          s.audience_type = 'staff'
          AND auth.uid()::text IN (SELECT jsonb_array_elements_text(s.audience_staff_ids))
        )
      )
  );
$function$;

REVOKE ALL ON FUNCTION private.can_see_survey(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.can_see_survey(uuid) TO authenticated;

DROP POLICY IF EXISTS "Staff can view open or closed surveys" ON surveys;
CREATE POLICY "Staff can view open or closed surveys"
  ON surveys FOR SELECT
  TO authenticated
  USING (private.admin_can('surveys', 'read') OR private.can_see_survey(id));

DROP POLICY IF EXISTS "Staff can view questions of visible surveys" ON survey_questions;
CREATE POLICY "Staff can view questions of visible surveys"
  ON survey_questions FOR SELECT
  TO authenticated
  USING (private.admin_can('surveys', 'read') OR private.can_see_survey(survey_id));

DROP POLICY IF EXISTS "Staff can submit to open surveys" ON survey_responses;
CREATE POLICY "Staff can submit to open surveys"
  ON survey_responses FOR INSERT
  TO authenticated
  WITH CHECK (
    respondent_id = auth.uid()
    AND private.can_see_survey(survey_id)
    AND EXISTS (
      SELECT 1 FROM surveys s
      WHERE s.id = survey_responses.survey_id AND s.status = 'open'
    )
  );
