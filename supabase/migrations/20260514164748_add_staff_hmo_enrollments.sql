/*
  # Staff HMO Enrollments

  1. New Tables
    - `staff_hmo_enrollments` - one row per staff member, holds their enrollee id, plan and provider linkage
      - `staff_id` (uuid, FK to staff_members, unique - one enrollment per staff)
      - `provider_id` (uuid, FK to hmo_providers, nullable)
      - `enrollee_id` (text) - the unique number issued by the HMO
      - `plan_name` (text) - e.g. "Gold", "Platinum"
      - `effective_date` (date, nullable) - when cover started
      - `notes` (text)

  2. Security
    - RLS enabled
    - Staff can SELECT their own enrollment row
    - Authorised admins (private.admin_can('staff','manage') or super admin) can SELECT/INSERT/UPDATE/DELETE all
*/

CREATE TABLE IF NOT EXISTS public.staff_hmo_enrollments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES public.staff_members(id) ON DELETE CASCADE,
  provider_id uuid REFERENCES public.hmo_providers(id) ON DELETE SET NULL,
  enrollee_id text NOT NULL DEFAULT '',
  plan_name text NOT NULL DEFAULT '',
  effective_date date,
  notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT staff_hmo_enrollments_staff_unique UNIQUE (staff_id)
);

ALTER TABLE public.staff_hmo_enrollments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff_hmo_enrollments' AND policyname='Staff view own enrollment') THEN
    CREATE POLICY "Staff view own enrollment"
      ON public.staff_hmo_enrollments FOR SELECT
      TO authenticated
      USING (
        staff_id IN (SELECT id FROM public.staff_members WHERE auth_user_id = auth.uid())
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff_hmo_enrollments' AND policyname='Admins view all enrollments') THEN
    CREATE POLICY "Admins view all enrollments"
      ON public.staff_hmo_enrollments FOR SELECT
      TO authenticated
      USING (private.is_super_admin() OR private.admin_can('staff','manage'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff_hmo_enrollments' AND policyname='Admins insert enrollments') THEN
    CREATE POLICY "Admins insert enrollments"
      ON public.staff_hmo_enrollments FOR INSERT
      TO authenticated
      WITH CHECK (private.is_super_admin() OR private.admin_can('staff','manage'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff_hmo_enrollments' AND policyname='Admins update enrollments') THEN
    CREATE POLICY "Admins update enrollments"
      ON public.staff_hmo_enrollments FOR UPDATE
      TO authenticated
      USING (private.is_super_admin() OR private.admin_can('staff','manage'))
      WITH CHECK (private.is_super_admin() OR private.admin_can('staff','manage'));
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='staff_hmo_enrollments' AND policyname='Admins delete enrollments') THEN
    CREATE POLICY "Admins delete enrollments"
      ON public.staff_hmo_enrollments FOR DELETE
      TO authenticated
      USING (private.is_super_admin() OR private.admin_can('staff','manage'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS staff_hmo_enrollments_staff_idx ON public.staff_hmo_enrollments(staff_id);
CREATE INDEX IF NOT EXISTS staff_hmo_enrollments_provider_idx ON public.staff_hmo_enrollments(provider_id);
