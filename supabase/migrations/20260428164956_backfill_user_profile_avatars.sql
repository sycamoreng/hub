/*
  # Backfill user_profiles.avatar_url from auth metadata

  1. Purpose
    Users who signed in before the avatar sync was wired into the initial-session path
    have a `user_profiles` row with an empty (or null) `avatar_url`, even though their
    Google account provides one in `auth.users.raw_user_meta_data`. This migration
    copies that Google avatar URL into `user_profiles.avatar_url` for any user where
    the profile column is currently empty.

  2. Modified data
    - `public.user_profiles.avatar_url`: filled in (or row inserted) for users whose
      auth metadata has a non-empty `avatar_url` or `picture` and whose stored
      `avatar_url` is null or empty.

  3. Safety
    - Only updates rows where the current value is null or empty - never overwrites a
      user-supplied custom avatar.
    - If no `user_profiles` row exists yet, one is inserted with the avatar URL filled
      in and other fields at their declared defaults.
*/

UPDATE public.user_profiles p
SET avatar_url = COALESCE(
      NULLIF(u.raw_user_meta_data->>'avatar_url', ''),
      NULLIF(u.raw_user_meta_data->>'picture', '')
    ),
    updated_at = now()
FROM auth.users u
WHERE p.user_id = u.id
  AND COALESCE(p.avatar_url, '') = ''
  AND COALESCE(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture', '') <> '';

INSERT INTO public.user_profiles (user_id, avatar_url)
SELECT u.id,
       COALESCE(
         NULLIF(u.raw_user_meta_data->>'avatar_url', ''),
         NULLIF(u.raw_user_meta_data->>'picture', '')
       )
FROM auth.users u
WHERE COALESCE(u.raw_user_meta_data->>'avatar_url', u.raw_user_meta_data->>'picture', '') <> ''
  AND NOT EXISTS (SELECT 1 FROM public.user_profiles p WHERE p.user_id = u.id)
ON CONFLICT (user_id) DO NOTHING;
