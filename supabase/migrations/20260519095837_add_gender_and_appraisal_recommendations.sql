/*
  # Add Gender Field and Appraisal Recommendations

  1. Modified Tables
    - `staff_members`
      - Add `gender` (text, nullable) - values: 'male', 'female', or null

    - `performance_appraisals`
      - Add `recommendation` (text, nullable) - values: 'promotion', 'pip', 'same_grade', 'termination'
      - Add `recommendation_notes` (text, nullable) - free text justification
      - Add `recommended_by` (uuid, nullable, FK to staff_members) - who made the recommendation

  2. Notes
    - Gender is used for workforce analytics (admin-only analytics page)
    - Recommendation allows appraisers to suggest outcomes based on performance
    - Recommendations are suggestions that require admin review/approval
*/

-- Add gender to staff_members
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'staff_members' AND column_name = 'gender'
  ) THEN
    ALTER TABLE staff_members ADD COLUMN gender text
      CHECK (gender IN ('male', 'female'));
  END IF;
END $$;

-- Add recommendation columns to performance_appraisals
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'performance_appraisals' AND column_name = 'recommendation'
  ) THEN
    ALTER TABLE performance_appraisals ADD COLUMN recommendation text
      CHECK (recommendation IN ('promotion', 'pip', 'same_grade', 'termination'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'performance_appraisals' AND column_name = 'recommendation_notes'
  ) THEN
    ALTER TABLE performance_appraisals ADD COLUMN recommendation_notes text DEFAULT '';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'performance_appraisals' AND column_name = 'recommended_by'
  ) THEN
    ALTER TABLE performance_appraisals ADD COLUMN recommended_by uuid REFERENCES staff_members(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_staff_members_gender ON staff_members(gender) WHERE gender IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_appraisals_recommendation ON performance_appraisals(recommendation) WHERE recommendation IS NOT NULL;
