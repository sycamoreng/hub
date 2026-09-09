/*
# Google sync deactivation alerts

1. Purpose
   - When a Google Workspace sync notices that a staff member who was active is
     now suspended/deactivated in Google, we raise an alert for admins instead of
     silently retiring the record. Admins decide whether it was a genuine exit or
     something else (e.g. an account issue).

2. New table
   - `google_sync_deactivations`
     - `staff_id` (uuid, unique): the affected staff member.
     - `full_name`, `email`, `google_user_id`: snapshot for display.
     - `detected_at` (timestamptz): when the sync first noticed the deactivation.
     - `tentative_exit_date` (date): best-guess exit date. Google does not expose
       an exact suspension date, so this defaults to the detection date and can be
       adjusted by an admin.
     - `status` (text): pending | dismissed | actioned.
     - `notes`, `resolved_by`, `resolved_at`, timestamps.

3. Security
   - RLS enabled. Only super admins (who are the only ones allowed to use Google
     sync) can read or manage these alerts.
*/

CREATE TABLE IF NOT EXISTS public.google_sync_deactivations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES public.staff_members(id) ON DELETE CASCADE,
  full_name text NOT NULL DEFAULT '',
  email text NOT NULL DEFAULT '',
  google_user_id text NOT NULL DEFAULT '',
  detected_at timestamptz NOT NULL DEFAULT now(),
  tentative_exit_date date,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','dismissed','actioned')),
  notes text NOT NULL DEFAULT '',
  resolved_by text,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS google_sync_deactivations_staff_uidx
  ON public.google_sync_deactivations(staff_id);
CREATE INDEX IF NOT EXISTS google_sync_deactivations_status_idx
  ON public.google_sync_deactivations(status, detected_at DESC);

ALTER TABLE public.google_sync_deactivations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Super admins read deactivation alerts"
  ON public.google_sync_deactivations FOR SELECT
  TO authenticated USING (private.is_super_admin());

CREATE POLICY "Super admins insert deactivation alerts"
  ON public.google_sync_deactivations FOR INSERT
  TO authenticated WITH CHECK (private.is_super_admin());

CREATE POLICY "Super admins update deactivation alerts"
  ON public.google_sync_deactivations FOR UPDATE
  TO authenticated USING (private.is_super_admin()) WITH CHECK (private.is_super_admin());

CREATE POLICY "Super admins delete deactivation alerts"
  ON public.google_sync_deactivations FOR DELETE
  TO authenticated USING (private.is_super_admin());

CREATE OR REPLACE FUNCTION public.google_sync_deactivations_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS google_sync_deactivations_touch_trg ON public.google_sync_deactivations;
CREATE TRIGGER google_sync_deactivations_touch_trg
  BEFORE UPDATE ON public.google_sync_deactivations
  FOR EACH ROW EXECUTE FUNCTION public.google_sync_deactivations_touch();
