/*
  # Staff directory visibility and proper exits

  1. Problem
    The directory currently has only `is_active`. We use it for two distinct
    things:
      a) "this person has actually left the company" (exit)
      b) "hide this email from the directory for now" (e.g. shared mailboxes,
         placeholder accounts)
    They need to be tracked separately.

  2. Changes
    - Add `staff_members.exited_at date null` — set when a person genuinely
      leaves. The exit workflow can populate this. Used by the Exited tab.
    - Add `staff_members.directory_visible boolean not null default true` —
      lets admins hide an email from the directory without claiming an exit.
    - Refresh `staff_directory_exited` view to use `exited_at` (true exits
      only).
    - Backfill `exited_at` for staff with `is_active=false` AND a closed
      exit_case (those are real exits).
    - For the three explicit emails (chris.may, jennifer.hart, mayowa.oluyede
      on @sycamoreglobal.co.uk) set `directory_visible=false` and clear any
      `exited_at` so they don't appear in either list, since they aren't
      real exits.

  3. Security
    - No RLS changes. View is security_invoker.
*/

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staff_members' AND column_name='exited_at') THEN
    ALTER TABLE public.staff_members ADD COLUMN exited_at date;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staff_members' AND column_name='directory_visible') THEN
    ALTER TABLE public.staff_members ADD COLUMN directory_visible boolean NOT NULL DEFAULT true;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS staff_members_exited_at_idx ON public.staff_members(exited_at);
CREATE INDEX IF NOT EXISTS staff_members_directory_visible_idx ON public.staff_members(directory_visible);

-- Backfill: real exits = inactive AND have a closed exit case.
UPDATE public.staff_members s
   SET exited_at = COALESCE(
        (SELECT max(ec.effective_date)::date FROM public.exit_cases ec WHERE ec.staff_id = s.id AND ec.status = 'closed'),
        (SELECT max(ec.last_working_day)::date FROM public.exit_cases ec WHERE ec.staff_id = s.id AND ec.status = 'closed')
      )
 WHERE s.is_active = false
   AND s.exited_at IS NULL
   AND EXISTS (SELECT 1 FROM public.exit_cases ec WHERE ec.staff_id = s.id AND ec.status = 'closed');

-- Hide the three placeholder mailboxes from the directory but do NOT mark them as exits.
UPDATE public.staff_members
   SET directory_visible = false,
       exited_at = NULL
 WHERE lower(email) IN (
    'chris.may@sycamoreglobal.co.uk',
    'jennifer.hart@sycamoreglobal.co.uk',
    'mayowa.oluyede@sycamoreglobal.co.uk'
 );

CREATE OR REPLACE VIEW public.staff_directory_exited
WITH (security_invoker = true)
AS
SELECT s.id, s.full_name, s.email, s.role, s.phone, s.bio,
       s.department_id, s.location_id, s.joined_date, s.auth_user_id,
       d.name AS department_name,
       l.name AS location_name, l.city AS location_city,
       s.exited_at AS exit_effective_date
FROM public.staff_members s
LEFT JOIN public.departments d ON d.id = s.department_id
LEFT JOIN public.locations l ON l.id = s.location_id
WHERE s.exited_at IS NOT NULL;

GRANT SELECT ON public.staff_directory_exited TO authenticated;
