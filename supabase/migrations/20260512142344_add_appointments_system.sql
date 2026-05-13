/*
  # Appointments (visitor management)

  Creates the appointments module: staff book guest visits by date + office,
  front-desk allowlist sees and manages them for their location, admins have
  full control via a new 'appointments' permission section.

  1. New Tables
    - `appointments` — one row per guest visit
    - `appointment_front_desk` — allowlist of staff who can manage all
      appointments (optionally scoped to a location)
    - `appointment_events` — append-only audit trail

  2. New Function
    - `private.is_front_desk(uuid)` — true if caller is on the allowlist
      (global or for the given location)

  3. Security
    - RLS enabled everywhere
    - Creators can CRUD their own appointments
    - Front desk staff can read/update at their locations (no delete)
    - Admins with `appointments` permission can do everything
    - Events are read alongside the appointment and are append-only

  4. Notes
    1. `status` values: scheduled | checked_in | in_meeting | checked_out |
       no_show | cancelled
    2. Existing super admins are granted the new section automatically
*/

CREATE TABLE IF NOT EXISTS public.appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by_staff_id uuid REFERENCES public.staff_members(id) ON DELETE SET NULL,
  created_by_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  location_id uuid REFERENCES public.locations(id) ON DELETE SET NULL,
  guest_name text NOT NULL DEFAULT '',
  guest_company text NOT NULL DEFAULT '',
  guest_email text NOT NULL DEFAULT '',
  guest_phone text NOT NULL DEFAULT '',
  guest_count integer NOT NULL DEFAULT 1,
  purpose text NOT NULL DEFAULT '',
  scheduled_date date NOT NULL,
  scheduled_start time NOT NULL DEFAULT '09:00',
  scheduled_end time,
  status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','checked_in','in_meeting','checked_out','no_show','cancelled')),
  current_location_note text NOT NULL DEFAULT '',
  checked_in_at timestamptz,
  checked_out_at timestamptz,
  host_notified_at timestamptz,
  badge_number text NOT NULL DEFAULT '',
  notes text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS appointments_scheduled_date_idx ON public.appointments (scheduled_date);
CREATE INDEX IF NOT EXISTS appointments_location_idx ON public.appointments (location_id);
CREATE INDEX IF NOT EXISTS appointments_creator_idx ON public.appointments (created_by_staff_id);
CREATE INDEX IF NOT EXISTS appointments_status_idx ON public.appointments (status);

CREATE TABLE IF NOT EXISTS public.appointment_front_desk (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES public.staff_members(id) ON DELETE CASCADE,
  location_id uuid REFERENCES public.locations(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS appointment_front_desk_unique_idx
  ON public.appointment_front_desk (staff_id, COALESCE(location_id::text, 'all'));

CREATE TABLE IF NOT EXISTS public.appointment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id uuid NOT NULL REFERENCES public.appointments(id) ON DELETE CASCADE,
  actor_staff_id uuid REFERENCES public.staff_members(id) ON DELETE SET NULL,
  actor_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type text NOT NULL CHECK (event_type IN ('created','status_changed','location_updated','note_added','edited','deleted')),
  from_value text NOT NULL DEFAULT '',
  to_value text NOT NULL DEFAULT '',
  note text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS appointment_events_appointment_idx
  ON public.appointment_events (appointment_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.appointments_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS appointments_set_updated_at_trg ON public.appointments;
CREATE TRIGGER appointments_set_updated_at_trg
  BEFORE UPDATE ON public.appointments
  FOR EACH ROW EXECUTE FUNCTION public.appointments_set_updated_at();

CREATE OR REPLACE FUNCTION private.is_front_desk(p_location uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.appointment_front_desk fd
    JOIN public.staff_members sm ON sm.id = fd.staff_id
    WHERE sm.auth_user_id = auth.uid()
      AND (fd.location_id IS NULL OR fd.location_id = p_location)
  );
$$;

REVOKE ALL ON FUNCTION private.is_front_desk(uuid) FROM public;
GRANT EXECUTE ON FUNCTION private.is_front_desk(uuid) TO authenticated;

ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Creator, front desk, admin can read" ON public.appointments;
CREATE POLICY "Creator, front desk, admin can read"
  ON public.appointments FOR SELECT
  TO authenticated
  USING (
    created_by_user_id = auth.uid()
    OR private.is_front_desk(location_id)
    OR private.admin_can('appointments', 'read')
  );

DROP POLICY IF EXISTS "Auth user can create appointment" ON public.appointments;
CREATE POLICY "Auth user can create appointment"
  ON public.appointments FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by_user_id = auth.uid()
    OR private.admin_can('appointments', 'create')
  );

DROP POLICY IF EXISTS "Creator, front desk, admin can update" ON public.appointments;
CREATE POLICY "Creator, front desk, admin can update"
  ON public.appointments FOR UPDATE
  TO authenticated
  USING (
    created_by_user_id = auth.uid()
    OR private.is_front_desk(location_id)
    OR private.admin_can('appointments', 'update')
  )
  WITH CHECK (
    created_by_user_id = auth.uid()
    OR private.is_front_desk(location_id)
    OR private.admin_can('appointments', 'update')
  );

DROP POLICY IF EXISTS "Creator or admin can delete" ON public.appointments;
CREATE POLICY "Creator or admin can delete"
  ON public.appointments FOR DELETE
  TO authenticated
  USING (
    created_by_user_id = auth.uid()
    OR private.admin_can('appointments', 'delete')
  );

ALTER TABLE public.appointment_front_desk ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can read front desk list" ON public.appointment_front_desk;
CREATE POLICY "Authenticated can read front desk list"
  ON public.appointment_front_desk FOR SELECT
  TO authenticated
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "Admin can add front desk" ON public.appointment_front_desk;
CREATE POLICY "Admin can add front desk"
  ON public.appointment_front_desk FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('appointments', 'create'));

DROP POLICY IF EXISTS "Admin can update front desk" ON public.appointment_front_desk;
CREATE POLICY "Admin can update front desk"
  ON public.appointment_front_desk FOR UPDATE
  TO authenticated
  USING (private.admin_can('appointments', 'update'))
  WITH CHECK (private.admin_can('appointments', 'update'));

DROP POLICY IF EXISTS "Admin can remove front desk" ON public.appointment_front_desk;
CREATE POLICY "Admin can remove front desk"
  ON public.appointment_front_desk FOR DELETE
  TO authenticated
  USING (private.admin_can('appointments', 'delete'));

ALTER TABLE public.appointment_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Can read events for visible appointments" ON public.appointment_events;
CREATE POLICY "Can read events for visible appointments"
  ON public.appointment_events FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.appointments a
      WHERE a.id = appointment_events.appointment_id
        AND (
          a.created_by_user_id = auth.uid()
          OR private.is_front_desk(a.location_id)
          OR private.admin_can('appointments', 'read')
        )
    )
  );

DROP POLICY IF EXISTS "Can insert events for managed appointments" ON public.appointment_events;
CREATE POLICY "Can insert events for managed appointments"
  ON public.appointment_events FOR INSERT
  TO authenticated
  WITH CHECK (
    (actor_user_id IS NULL OR actor_user_id = auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.appointments a
      WHERE a.id = appointment_events.appointment_id
        AND (
          a.created_by_user_id = auth.uid()
          OR private.is_front_desk(a.location_id)
          OR private.admin_can('appointments', 'update')
        )
    )
  );

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT email, permissions FROM public.admin_users WHERE role = 'super_admin' LOOP
    UPDATE public.admin_users
    SET permissions = COALESCE(r.permissions, '{}'::jsonb) || jsonb_build_object(
      'appointments',
      jsonb_build_object('create', true, 'read', true, 'update', true, 'delete', true)
    )
    WHERE email = r.email;
  END LOOP;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.admin_role_presets WHERE name = 'Super admin') THEN
    UPDATE public.admin_role_presets
    SET permissions = COALESCE(permissions, '{}'::jsonb) || jsonb_build_object(
      'appointments',
      jsonb_build_object('create', true, 'read', true, 'update', true, 'delete', true)
    )
    WHERE name = 'Super admin';
  END IF;
END $$;
