-- Harden RLS policies and admin helper functions.
-- Replaces permissive USING(true)/WITH CHECK(true) write policies on every
-- public content table with checks against private.admin_can(section, action),
-- and moves SECURITY DEFINER helpers out of the public schema so they are not
-- exposed via PostgREST RPC.

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $func$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE email = lower(coalesce(auth.jwt() ->> 'email', ''))
      AND role = 'super_admin'
  );
$func$;

CREATE OR REPLACE FUNCTION private.admin_can(section text, action text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $func$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE email = lower(coalesce(auth.jwt() ->> 'email', ''))
      AND (
        role = 'super_admin'
        OR coalesce((permissions -> section ->> action)::boolean, false)
      )
  );
$func$;

REVOKE ALL ON FUNCTION private.is_super_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.admin_can(text, text) FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_super_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.admin_can(text, text) TO authenticated;

DO $do$
DECLARE
  section_map jsonb := jsonb_build_object(
    'announcements',        'announcements',
    'benefits_perks',       'benefits',
    'branding_guidelines',  'branding',
    'chatbot_settings',     'chatbot',
    'communication_tools',  'communication',
    'company_info',         'company',
    'departments',          'departments',
    'holidays_events',      'events',
    'key_contacts',         'contacts',
    'leadership',           'leadership',
    'locations',            'locations',
    'onboarding_steps',     'onboarding',
    'policies',             'policies',
    'products',             'products',
    'staff_members',        'staff',
    'tech_stack',           'technology'
  );
  tbl text;
  section text;
  pol record;
BEGIN
  FOR tbl, section IN SELECT key, value FROM jsonb_each_text(section_map) LOOP
    FOR pol IN
      SELECT policyname FROM pg_policies
      WHERE schemaname = 'public' AND tablename = tbl AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, tbl);
    END LOOP;

    EXECUTE format(
      'CREATE POLICY "Admins with create permission can insert" ON public.%I FOR INSERT TO authenticated WITH CHECK (private.admin_can(%L, %L))',
      tbl, section, 'create'
    );
    EXECUTE format(
      'CREATE POLICY "Admins with update permission can update" ON public.%I FOR UPDATE TO authenticated USING (private.admin_can(%L, %L)) WITH CHECK (private.admin_can(%L, %L))',
      tbl, section, 'update', section, 'update'
    );
    EXECUTE format(
      'CREATE POLICY "Admins with delete permission can delete" ON public.%I FOR DELETE TO authenticated USING (private.admin_can(%L, %L))',
      tbl, section, 'delete'
    );
  END LOOP;
END
$do$;

DO $do$
DECLARE
  pol record;
BEGIN
  FOR pol IN
    SELECT policyname, tablename FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename IN ('admin_users', 'admin_role_presets')
      AND (coalesce(qual, '') ILIKE '%is_super_admin()%' OR coalesce(with_check, '') ILIKE '%is_super_admin()%')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
  END LOOP;
END
$do$;

CREATE POLICY "Super admins can read all admins"
  ON public.admin_users FOR SELECT TO authenticated
  USING (private.is_super_admin());

CREATE POLICY "Super admins can insert admins"
  ON public.admin_users FOR INSERT TO authenticated
  WITH CHECK (private.is_super_admin());

CREATE POLICY "Super admins can update admins"
  ON public.admin_users FOR UPDATE TO authenticated
  USING (private.is_super_admin())
  WITH CHECK (private.is_super_admin());

CREATE POLICY "Super admins can delete admins"
  ON public.admin_users FOR DELETE TO authenticated
  USING (private.is_super_admin());

CREATE POLICY "Super admins can insert presets"
  ON public.admin_role_presets FOR INSERT TO authenticated
  WITH CHECK (private.is_super_admin());

CREATE POLICY "Super admins can update presets"
  ON public.admin_role_presets FOR UPDATE TO authenticated
  USING (private.is_super_admin())
  WITH CHECK (private.is_super_admin());

CREATE POLICY "Super admins can delete presets"
  ON public.admin_role_presets FOR DELETE TO authenticated
  USING (private.is_super_admin());

DROP FUNCTION IF EXISTS public.admin_can(text, text);
DROP FUNCTION IF EXISTS public.is_super_admin();
