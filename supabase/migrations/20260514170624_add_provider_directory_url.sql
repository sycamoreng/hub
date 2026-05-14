/*
  # Add provider directory URL

  1. Changes
    - Add `directory_url` column to `hmo_providers` so admins can paste the
      provider-shared Excel/Sheets link listing covered hospitals. Staff
      will be redirected to this URL from their HMO screen.
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'hmo_providers' AND column_name = 'directory_url'
  ) THEN
    ALTER TABLE public.hmo_providers ADD COLUMN directory_url text NOT NULL DEFAULT '';
  END IF;
END $$;
