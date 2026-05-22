/*
  # Add billing type and rate to contractors

  1. Modified Tables
    - `contractors`
      - Add `billing_type` text column (values: 'one_time', 'monthly') defaulting to 'monthly'
      - Add `rate` numeric column (nullable) to replace hourly_rate
      - Migrate existing hourly_rate data to rate column

  2. Notes
    - Contractors are not typically paid hourly; they receive either a one-time fee or monthly payment
    - The department field remains but is optional (contractors may not be tied to a single department)
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'contractors' AND column_name = 'billing_type'
  ) THEN
    ALTER TABLE contractors ADD COLUMN billing_type text NOT NULL DEFAULT 'monthly';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'contractors' AND column_name = 'rate'
  ) THEN
    ALTER TABLE contractors ADD COLUMN rate numeric;
    UPDATE contractors SET rate = hourly_rate WHERE hourly_rate IS NOT NULL;
  END IF;
END $$;
