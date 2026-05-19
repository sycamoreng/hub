/*
  # Add Recommendation Field to Performance Reviews

  1. Modified Tables
    - `performance_reviews`
      - Add `recommendation` (text, nullable) - appraiser's recommendation for the subject
        Values: 'promotion', 'pip', 'same_grade', 'termination'
      - Add `recommendation_notes` (text, nullable) - justification for the recommendation

  2. Notes
    - This allows individual reviewers (especially managers) to recommend an outcome
    - The final recommendation on performance_appraisals is set by admin after considering all reviews
    - Only manager and self review types typically provide recommendations
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'performance_reviews' AND column_name = 'recommendation'
  ) THEN
    ALTER TABLE performance_reviews ADD COLUMN recommendation text
      CHECK (recommendation IN ('promotion', 'pip', 'same_grade', 'termination'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'performance_reviews' AND column_name = 'recommendation_notes'
  ) THEN
    ALTER TABLE performance_reviews ADD COLUMN recommendation_notes text DEFAULT '';
  END IF;
END $$;
