/*
# Add photo storage directly on staff records

1. Purpose
   - Until now, a staff member's photo could only be stored against a signed-in
     hub account (in `user_profiles`, keyed by the person's login). Staff who have
     never signed into the hub had no place to hold a photo, so pulling their
     Google photo in did nothing visible.
   - This migration lets every staff record hold its own photo, independent of
     whether the person has ever logged in.

2. Modified Tables
   - `staff_members`
     - `avatar_url` (text, nullable): the staff member's photo, e.g. pulled from
       Google. Shown in the directory and profile when the person has no signed-in
       hub photo of their own.
     - `avatar_source` (text, nullable): where the photo came from (e.g. 'google').

3. Security
   - No policy changes. Existing row-level security on `staff_members` already
     governs who can read these rows; the new columns are covered by it.

4. Notes
   1. Both columns are nullable with no default, so existing records are untouched
      and no data is lost.
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'staff_members' AND column_name = 'avatar_url'
  ) THEN
    ALTER TABLE staff_members ADD COLUMN avatar_url text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'staff_members' AND column_name = 'avatar_source'
  ) THEN
    ALTER TABLE staff_members ADD COLUMN avatar_source text;
  END IF;
END $$;
