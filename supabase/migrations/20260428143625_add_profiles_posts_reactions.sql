/*
  # Add user profiles, posts, and reactions

  1. New Tables
    - `user_profiles`
      - `user_id` (uuid PK, FK auth.users) — owner of the profile
      - `bio` (text) — short freeform bio
      - `theme` (text) — selected color theme key (e.g. sycamore, sunset, forest, midnight, rose, ocean)
      - `linkedin_url`, `twitter_url`, `github_url`, `website_url`, `instagram_url` (text)
      - `created_at`, `updated_at` (timestamptz)
    - `posts`
      - `id` (uuid PK), `author_id` (uuid FK auth.users), `content` (text), `is_published` (bool default true)
      - `created_at`, `updated_at` (timestamptz)
    - `reactions` — polymorphic table for announcements and posts
      - `id` (uuid PK), `target_type` (text — 'announcement' | 'post'), `target_id` (uuid)
      - `user_id` (uuid FK auth.users), `emoji` (text — short identifier, not unicode), `created_at`
      - UNIQUE(target_type, target_id, user_id, emoji)

  2. Modified Tables
    - `staff_members` — added nullable `auth_user_id` (uuid FK auth.users) so a directory entry
      can be tied to a logged-in user. Owners (matched by email) can claim their record via the
      `claim_staff_member()` SECURITY DEFINER function. Names / phone / email remain admin-only
      because writes on `staff_members` are still gated by `admin_can('staff', 'update')`.

  3. Functions
    - `public.claim_staff_member()` — SECURITY DEFINER. Updates the caller's matching
      `staff_members.auth_user_id` if it is currently NULL and the email matches the JWT email.

  4. Security
    - RLS enabled on all new tables.
    - `user_profiles`: any authenticated user can read profiles (directory transparency); only the
      profile owner can insert / update / delete their own row.
    - `posts`: any authenticated user can read published posts or their own drafts; insert / update
      / delete restricted to the author.
    - `reactions`: any authenticated user can read; insert and delete restricted to the user owning
      the reaction; updates are not permitted (delete + reinsert if needed).
    - The new `staff_members.auth_user_id` column is writable only via the
      `claim_staff_member()` function (SECURITY DEFINER), so end-users still cannot edit
      their name / phone / email or anyone else's row.
*/

-- ============================================================================
-- user_profiles
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  bio text NOT NULL DEFAULT '',
  theme text NOT NULL DEFAULT 'sycamore',
  linkedin_url text NOT NULL DEFAULT '',
  twitter_url text NOT NULL DEFAULT '',
  github_url text NOT NULL DEFAULT '',
  website_url text NOT NULL DEFAULT '',
  instagram_url text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view profiles" ON public.user_profiles;
CREATE POLICY "Authenticated users can view profiles"
  ON public.user_profiles FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Users insert own profile" ON public.user_profiles;
CREATE POLICY "Users insert own profile"
  ON public.user_profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users update own profile" ON public.user_profiles;
CREATE POLICY "Users update own profile"
  ON public.user_profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users delete own profile" ON public.user_profiles;
CREATE POLICY "Users delete own profile"
  ON public.user_profiles FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ============================================================================
-- posts
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.posts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content text NOT NULL DEFAULT '',
  is_published boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS posts_created_at_idx ON public.posts (created_at DESC);
CREATE INDEX IF NOT EXISTS posts_author_idx ON public.posts (author_id);

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users view published posts" ON public.posts;
CREATE POLICY "Authenticated users view published posts"
  ON public.posts FOR SELECT
  TO authenticated
  USING (is_published = true OR author_id = auth.uid());

DROP POLICY IF EXISTS "Authors insert own posts" ON public.posts;
CREATE POLICY "Authors insert own posts"
  ON public.posts FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "Authors update own posts" ON public.posts;
CREATE POLICY "Authors update own posts"
  ON public.posts FOR UPDATE
  TO authenticated
  USING (auth.uid() = author_id)
  WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "Authors delete own posts" ON public.posts;
CREATE POLICY "Authors delete own posts"
  ON public.posts FOR DELETE
  TO authenticated
  USING (auth.uid() = author_id);

-- ============================================================================
-- reactions (polymorphic on announcements + posts)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type text NOT NULL CHECK (target_type IN ('announcement','post')),
  target_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  emoji text NOT NULL CHECK (emoji IN ('like','celebrate','heart','insight','support')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (target_type, target_id, user_id, emoji)
);

CREATE INDEX IF NOT EXISTS reactions_target_idx ON public.reactions (target_type, target_id);
CREATE INDEX IF NOT EXISTS reactions_user_idx ON public.reactions (user_id);

ALTER TABLE public.reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users view reactions" ON public.reactions;
CREATE POLICY "Authenticated users view reactions"
  ON public.reactions FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Users insert own reactions" ON public.reactions;
CREATE POLICY "Users insert own reactions"
  ON public.reactions FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users delete own reactions" ON public.reactions;
CREATE POLICY "Users delete own reactions"
  ON public.reactions FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ============================================================================
-- staff_members.auth_user_id link + claim function
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='staff_members' AND column_name='auth_user_id'
  ) THEN
    ALTER TABLE public.staff_members
      ADD COLUMN auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS staff_members_auth_user_idx ON public.staff_members (auth_user_id);

CREATE OR REPLACE FUNCTION public.claim_staff_member()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text := lower(coalesce((auth.jwt() ->> 'email'), ''));
  v_id uuid;
BEGIN
  IF v_uid IS NULL OR v_email = '' THEN
    RETURN NULL;
  END IF;

  UPDATE public.staff_members
    SET auth_user_id = v_uid
    WHERE lower(email) = v_email
      AND (auth_user_id IS NULL OR auth_user_id = v_uid)
    RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_staff_member() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_staff_member() TO authenticated;
