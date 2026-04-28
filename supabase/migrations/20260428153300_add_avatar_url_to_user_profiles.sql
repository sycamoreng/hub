/*
  # Add avatar_url to user_profiles

  1. Modified Tables
    - `user_profiles`
      - Added `avatar_url` (text, default '') so we can persist the user's profile
        picture (typically taken from their Google account on first sign-in).
        Stored alongside the rest of the profile so it survives sign-out and is
        readable by other authenticated users for display in the directory and feed.

  2. Notes
    - No data is removed.
    - The column is writable by the profile owner under the existing RLS update
      policy. No new policy is required.
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'avatar_url'
  ) THEN
    ALTER TABLE public.user_profiles
      ADD COLUMN avatar_url text NOT NULL DEFAULT '';
  END IF;
END $$;
