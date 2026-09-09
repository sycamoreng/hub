/*
  # Add Staff Survey Feature

  1. New Tables
    - `surveys` — a survey an admin creates and runs.
      - `id` (uuid, pk)
      - `title` (text) — survey name shown to staff
      - `description` (text) — optional intro/instructions
      - `status` (text) — draft | open | closed. Only `open` surveys accept responses.
      - `is_anonymous` (boolean) — when true, admin results hide who answered
      - `created_by` (uuid) — admin who created it
      - `opens_at` / `closes_at` (timestamptz) — optional informational window
      - `created_at` (timestamptz)
    - `survey_questions` — the questions inside a survey.
      - `id` (uuid, pk)
      - `survey_id` (uuid, fk -> surveys)
      - `prompt` (text) — the question text
      - `type` (text) — rating | single_choice | multiple_choice | text | department_rating
      - `options` (jsonb) — array of option strings (choice types)
      - `scale_max` (int) — top of the rating scale (rating + department_rating)
      - `required` (boolean)
      - `sort_order` (int)
    - `survey_responses` — one submission per staff member per survey.
      - `id` (uuid, pk)
      - `survey_id` (uuid, fk -> surveys)
      - `respondent_id` (uuid) — the staff member who submitted
      - `submitted_at` (timestamptz)
      - unique (survey_id, respondent_id) prevents double submission
    - `survey_answers` — individual answers within a response.
      - `id` (uuid, pk)
      - `response_id` (uuid, fk -> survey_responses)
      - `question_id` (uuid, fk -> survey_questions)
      - `subject_department_id` (uuid, fk -> departments) — for department_rating: which department is being rated
      - `rating` (int) — numeric answer (rating / department_rating)
      - `choice` (text) — single-choice answer
      - `choices` (jsonb) — multiple-choice answers
      - `text_answer` (text) — free-text answer

  2. Security
    - Enable RLS on all four tables.
    - Surveys/questions: admins (surveys section) manage; any authenticated staff can read surveys that are open or closed (drafts stay admin-only).
    - Responses/answers: a staff member can create and read only their own submission; admins can read all. Responses can only be inserted while the survey is open.

  3. Notes
    1. The "rate every department except your own" behaviour is a property of the `department_rating` question type: the frontend lists every department except the respondent's own and records one answer row per department.
    2. Anonymity is enforced at the presentation layer — respondent_id is always stored so duplicate submissions and own-department exclusion work, but the admin results screen does not reveal identities for anonymous surveys.
*/

CREATE TABLE IF NOT EXISTS surveys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'open', 'closed')),
  is_anonymous boolean NOT NULL DEFAULT false,
  created_by uuid REFERENCES auth.users(id),
  opens_at timestamptz,
  closes_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE surveys ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff can view open or closed surveys" ON surveys;
CREATE POLICY "Staff can view open or closed surveys"
  ON surveys FOR SELECT
  TO authenticated
  USING (status IN ('open', 'closed') OR private.admin_can('surveys', 'read'));

DROP POLICY IF EXISTS "Admins can create surveys" ON surveys;
CREATE POLICY "Admins can create surveys"
  ON surveys FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('surveys', 'create'));

DROP POLICY IF EXISTS "Admins can update surveys" ON surveys;
CREATE POLICY "Admins can update surveys"
  ON surveys FOR UPDATE
  TO authenticated
  USING (private.admin_can('surveys', 'update'))
  WITH CHECK (private.admin_can('surveys', 'update'));

DROP POLICY IF EXISTS "Admins can delete surveys" ON surveys;
CREATE POLICY "Admins can delete surveys"
  ON surveys FOR DELETE
  TO authenticated
  USING (private.admin_can('surveys', 'delete'));

CREATE TABLE IF NOT EXISTS survey_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id uuid NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
  prompt text NOT NULL,
  type text NOT NULL DEFAULT 'rating' CHECK (type IN ('rating', 'single_choice', 'multiple_choice', 'text', 'department_rating')),
  options jsonb NOT NULL DEFAULT '[]'::jsonb,
  scale_max int NOT NULL DEFAULT 5,
  required boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE survey_questions ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_survey_questions_survey ON survey_questions(survey_id);

DROP POLICY IF EXISTS "Staff can view questions of visible surveys" ON survey_questions;
CREATE POLICY "Staff can view questions of visible surveys"
  ON survey_questions FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM surveys s
      WHERE s.id = survey_questions.survey_id
        AND (s.status IN ('open', 'closed') OR private.admin_can('surveys', 'read'))
    )
  );

DROP POLICY IF EXISTS "Admins can insert questions" ON survey_questions;
CREATE POLICY "Admins can insert questions"
  ON survey_questions FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('surveys', 'create'));

DROP POLICY IF EXISTS "Admins can update questions" ON survey_questions;
CREATE POLICY "Admins can update questions"
  ON survey_questions FOR UPDATE
  TO authenticated
  USING (private.admin_can('surveys', 'update'))
  WITH CHECK (private.admin_can('surveys', 'update'));

DROP POLICY IF EXISTS "Admins can delete questions" ON survey_questions;
CREATE POLICY "Admins can delete questions"
  ON survey_questions FOR DELETE
  TO authenticated
  USING (private.admin_can('surveys', 'delete'));

CREATE TABLE IF NOT EXISTS survey_responses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id uuid NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
  respondent_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (survey_id, respondent_id)
);

ALTER TABLE survey_responses ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_survey_responses_survey ON survey_responses(survey_id);

DROP POLICY IF EXISTS "Own or admin can view responses" ON survey_responses;
CREATE POLICY "Own or admin can view responses"
  ON survey_responses FOR SELECT
  TO authenticated
  USING (respondent_id = auth.uid() OR private.admin_can('surveys', 'read'));

DROP POLICY IF EXISTS "Staff can submit to open surveys" ON survey_responses;
CREATE POLICY "Staff can submit to open surveys"
  ON survey_responses FOR INSERT
  TO authenticated
  WITH CHECK (
    respondent_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM surveys s
      WHERE s.id = survey_responses.survey_id AND s.status = 'open'
    )
  );

CREATE TABLE IF NOT EXISTS survey_answers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  response_id uuid NOT NULL REFERENCES survey_responses(id) ON DELETE CASCADE,
  question_id uuid NOT NULL REFERENCES survey_questions(id) ON DELETE CASCADE,
  subject_department_id uuid REFERENCES departments(id) ON DELETE SET NULL,
  rating int,
  choice text,
  choices jsonb,
  text_answer text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE survey_answers ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_survey_answers_response ON survey_answers(response_id);
CREATE INDEX IF NOT EXISTS idx_survey_answers_question ON survey_answers(question_id);
CREATE INDEX IF NOT EXISTS idx_survey_answers_department ON survey_answers(subject_department_id);

DROP POLICY IF EXISTS "Own or admin can view answers" ON survey_answers;
CREATE POLICY "Own or admin can view answers"
  ON survey_answers FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM survey_responses r
      WHERE r.id = survey_answers.response_id
        AND (r.respondent_id = auth.uid() OR private.admin_can('surveys', 'read'))
    )
  );

DROP POLICY IF EXISTS "Staff can insert answers to own response" ON survey_answers;
CREATE POLICY "Staff can insert answers to own response"
  ON survey_answers FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM survey_responses r
      WHERE r.id = survey_answers.response_id
        AND r.respondent_id = auth.uid()
    )
  );
