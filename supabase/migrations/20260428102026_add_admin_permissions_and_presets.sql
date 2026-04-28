/*
  # Granular CRUD permissions and role presets for admins

  1. Schema changes
    - Add `permissions` JSONB column to `admin_users`
      Shape: { "<section_key>": { "create": bool, "read": bool, "update": bool, "delete": bool } }
      A section is omitted entirely if the admin has no access.
    - Migrate existing `sections` array values into the new `permissions` column,
      granting full CRUD for any section previously listed.

  2. New table
    - `admin_role_presets` — reusable templates of permissions per department/role
      - `id` (uuid, primary key)
      - `name` (text, unique) — e.g. "HR Admin"
      - `description` (text) — short summary
      - `permissions` (JSONB) — same shape as admin_users.permissions
      - `is_default` (bool) — flagged true for system-seeded presets
      - `created_at`, `updated_at`

  3. Helper function
    - `admin_can(section text, action text)` — returns true if the calling user
      has the requested CRUD action on the given section. Super-admins always pass.

  4. Security
    - RLS enabled on `admin_role_presets`
    - Authenticated users can SELECT presets (so admins can apply them in the UI)
    - Only super-admins can INSERT/UPDATE/DELETE presets

  5. Seed
    - Six default role presets covering common departments:
      Super Admin, HR Admin, Operations Admin, Marketing & Comms Admin,
      Tech Admin, Leadership Admin.
*/

ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS permissions jsonb NOT NULL DEFAULT '{}'::jsonb;

DO $$
DECLARE
  rec record;
  perms jsonb;
  sec text;
BEGIN
  FOR rec IN
    SELECT email, sections FROM public.admin_users
    WHERE permissions = '{}'::jsonb AND sections IS NOT NULL AND array_length(sections, 1) > 0
  LOOP
    perms := '{}'::jsonb;
    FOREACH sec IN ARRAY rec.sections LOOP
      perms := perms || jsonb_build_object(sec, jsonb_build_object('create', true, 'read', true, 'update', true, 'delete', true));
    END LOOP;
    UPDATE public.admin_users SET permissions = perms WHERE email = rec.email;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.admin_can(section text, action text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE email = lower(coalesce(auth.jwt() ->> 'email', ''))
      AND (
        role = 'super_admin'
        OR coalesce((permissions -> section ->> action)::boolean, false)
      )
  );
$$;

CREATE TABLE IF NOT EXISTS public.admin_role_presets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  description text DEFAULT '',
  permissions jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE public.admin_role_presets ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'admin_role_presets' AND policyname = 'Authenticated users can read presets') THEN
    CREATE POLICY "Authenticated users can read presets"
      ON public.admin_role_presets FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'admin_role_presets' AND policyname = 'Super admins can insert presets') THEN
    CREATE POLICY "Super admins can insert presets"
      ON public.admin_role_presets FOR INSERT
      TO authenticated
      WITH CHECK (public.is_super_admin());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'admin_role_presets' AND policyname = 'Super admins can update presets') THEN
    CREATE POLICY "Super admins can update presets"
      ON public.admin_role_presets FOR UPDATE
      TO authenticated
      USING (public.is_super_admin())
      WITH CHECK (public.is_super_admin());
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'admin_role_presets' AND policyname = 'Super admins can delete presets') THEN
    CREATE POLICY "Super admins can delete presets"
      ON public.admin_role_presets FOR DELETE
      TO authenticated
      USING (public.is_super_admin());
  END IF;
END $$;

INSERT INTO public.admin_role_presets (name, description, permissions, is_default) VALUES
  (
    'Super Admin',
    'Full access to every section, including managing other admins. Use sparingly.',
    '{}'::jsonb,
    true
  ),
  (
    'HR Admin',
    'Manages people-focused content: staff, onboarding, benefits, policies.',
    '{
      "staff":      {"create":true,"read":true,"update":true,"delete":true},
      "onboarding": {"create":true,"read":true,"update":true,"delete":true},
      "policies":   {"create":true,"read":true,"update":true,"delete":true},
      "benefits":   {"create":true,"read":true,"update":true,"delete":true},
      "leadership": {"create":false,"read":true,"update":true,"delete":false},
      "departments":{"create":false,"read":true,"update":true,"delete":false}
    }'::jsonb,
    true
  ),
  (
    'Operations Admin',
    'Day-to-day operations: locations, contacts, events, communication tools.',
    '{
      "locations":     {"create":true,"read":true,"update":true,"delete":true},
      "contacts":      {"create":true,"read":true,"update":true,"delete":true},
      "events":        {"create":true,"read":true,"update":true,"delete":true},
      "communication": {"create":true,"read":true,"update":true,"delete":true},
      "departments":   {"create":false,"read":true,"update":true,"delete":false}
    }'::jsonb,
    true
  ),
  (
    'Marketing & Comms Admin',
    'External and internal communications: announcements, branding, communication tools.',
    '{
      "announcements": {"create":true,"read":true,"update":true,"delete":true},
      "branding":      {"create":true,"read":true,"update":true,"delete":true},
      "communication": {"create":true,"read":true,"update":true,"delete":true},
      "events":        {"create":true,"read":true,"update":true,"delete":false},
      "company":       {"create":false,"read":true,"update":true,"delete":false}
    }'::jsonb,
    true
  ),
  (
    'Tech Admin',
    'Owns the technology stack and chatbot configuration.',
    '{
      "technology": {"create":true,"read":true,"update":true,"delete":true},
      "products":   {"create":true,"read":true,"update":true,"delete":true},
      "chatbot":    {"create":true,"read":true,"update":true,"delete":true},
      "company":    {"create":false,"read":true,"update":false,"delete":false}
    }'::jsonb,
    true
  ),
  (
    'Leadership Admin',
    'Read-mostly access tailored for executive oversight across the org.',
    '{
      "leadership":    {"create":true,"read":true,"update":true,"delete":true},
      "departments":   {"create":true,"read":true,"update":true,"delete":true},
      "company":       {"create":true,"read":true,"update":true,"delete":true},
      "staff":         {"create":false,"read":true,"update":false,"delete":false},
      "policies":      {"create":false,"read":true,"update":true,"delete":false},
      "announcements": {"create":false,"read":true,"update":true,"delete":false}
    }'::jsonb,
    true
  )
ON CONFLICT (name) DO NOTHING;
