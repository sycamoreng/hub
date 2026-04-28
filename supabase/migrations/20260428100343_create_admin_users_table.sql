/*
  # Admin users and role-based permissions

  1. New tables
    - `admin_users` — registry of users with admin privileges
      - `email` (text, primary key, lowercase) — matches auth.jwt() email claim
      - `role` (text) — 'super_admin' or 'admin'
      - `display_name` (text) — friendly name for display in admin lists
      - `title` (text) — job title, e.g. "Head of HR"
      - `function` (text) — business function/department, e.g. "Human Resources"
      - `sections` (text[]) — list of section keys this admin can manage
        Ignored when role = 'super_admin' (they have access to everything)
      - `added_by` (text) — email of the super-admin who added this row
      - `created_at`, `updated_at` (timestamptz)

  2. Helper function
    - `is_super_admin()` — SECURITY DEFINER, returns true when the calling user's
      email matches a super_admin row. Used by RLS policies.

  3. Security
    - RLS enabled on admin_users
    - Authenticated users can SELECT only their own row (so the app can detect
      whether they have admin access)
    - Super-admins can SELECT all rows and INSERT/UPDATE/DELETE
    - No anonymous access

  4. Seed
    - tech@sycamore.ng and daniel.anyaegbu@sycamore.ng are inserted as
      super_admins (idempotent via ON CONFLICT)
*/

CREATE TABLE IF NOT EXISTS public.admin_users (
  email text PRIMARY KEY,
  role text NOT NULL DEFAULT 'admin' CHECK (role IN ('super_admin', 'admin')),
  display_name text DEFAULT '',
  title text DEFAULT '',
  function text DEFAULT '',
  sections text[] NOT NULL DEFAULT '{}',
  added_by text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE email = lower(coalesce(auth.jwt() ->> 'email', ''))
      AND role = 'super_admin'
  );
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'admin_users' AND policyname = 'Users can read own admin row') THEN
    CREATE POLICY "Users can read own admin row"
      ON public.admin_users FOR SELECT
      TO authenticated
      USING (email = lower(coalesce(auth.jwt() ->> 'email', '')));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'admin_users' AND policyname = 'Super admins can read all admins') THEN
    CREATE POLICY "Super admins can read all admins"
      ON public.admin_users FOR SELECT
      TO authenticated
      USING (public.is_super_admin());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'admin_users' AND policyname = 'Super admins can insert admins') THEN
    CREATE POLICY "Super admins can insert admins"
      ON public.admin_users FOR INSERT
      TO authenticated
      WITH CHECK (public.is_super_admin());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'admin_users' AND policyname = 'Super admins can update admins') THEN
    CREATE POLICY "Super admins can update admins"
      ON public.admin_users FOR UPDATE
      TO authenticated
      USING (public.is_super_admin())
      WITH CHECK (public.is_super_admin());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'admin_users' AND policyname = 'Super admins can delete admins') THEN
    CREATE POLICY "Super admins can delete admins"
      ON public.admin_users FOR DELETE
      TO authenticated
      USING (public.is_super_admin());
  END IF;
END $$;

INSERT INTO public.admin_users (email, role, display_name, title, function, sections, added_by)
VALUES
  ('tech@sycamore.ng', 'super_admin', 'Sycamore Tech', 'Technology', 'Technology', '{}', 'system'),
  ('daniel.anyaegbu@sycamore.ng', 'super_admin', 'Daniel Anyaegbu', 'Founder', 'Leadership', '{}', 'system')
ON CONFLICT (email) DO NOTHING;
