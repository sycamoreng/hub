/*
  # Stage-specific finance request permissions

  1. Background
    The admin finance page split review into two stages (HC then Finance), but
    the underlying RLS only checked `payroll.update`, and the UI gated the
    buttons on permission keys (`staff.manage`, `payroll.manage`) that did not
    exist in the permission schema. This migration wires real stage permissions
    end-to-end.

  2. Changes
    - RLS on `finance_requests` UPDATE now also allows admins with
      `finance_hc.update` or `finance_finance.update` (in addition to
      `payroll.update`). Cancel-own-pending logic for staff is unchanged.
    - New trigger `trg_finance_requests_stage_authz` enforces stage isolation:
        - Changes to `hc_status` / `hc_*` columns require super admin OR
          `finance_hc.update` OR `payroll.update`.
        - Changes to `finance_status` / `finance_*` / final `decided_*`
          columns require super admin OR `finance_finance.update` OR
          `payroll.update`.
        - Staff cancelling their own pending request (status -> 'cancelled')
          is allowed without admin permissions.

  3. Security
    - Trigger runs as SECURITY DEFINER so it can read auth.uid() and call
      `private.is_super_admin` / `private.admin_can`.
    - REVOKE/GRANT preserved on helpers; no policy is loosened beyond the
      explicit new permission keys.
*/

DROP POLICY IF EXISTS "Staff cancel own pending finance requests" ON public.finance_requests;
CREATE POLICY "Staff cancel own pending finance requests"
  ON public.finance_requests FOR UPDATE
  TO authenticated
  USING (
    (requester_user_id = auth.uid() AND status = 'pending')
    OR private.admin_can('payroll','update')
    OR private.admin_can('finance_hc','update')
    OR private.admin_can('finance_finance','update')
  )
  WITH CHECK (
    (requester_user_id = auth.uid() AND status IN ('pending','cancelled'))
    OR private.admin_can('payroll','update')
    OR private.admin_can('finance_hc','update')
    OR private.admin_can('finance_finance','update')
  );

CREATE OR REPLACE FUNCTION private.finance_requests_stage_authz()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  is_super boolean := false;
  can_payroll boolean := false;
  can_hc boolean := false;
  can_fin boolean := false;
  uid uuid := auth.uid();
  hc_changed boolean;
  fin_changed boolean;
  staff_self_cancel boolean;
BEGIN
  is_super := private.is_super_admin();
  IF is_super THEN
    RETURN NEW;
  END IF;

  can_payroll := private.admin_can('payroll','update');
  can_hc := private.admin_can('finance_hc','update');
  can_fin := private.admin_can('finance_finance','update');

  hc_changed := (NEW.hc_status IS DISTINCT FROM OLD.hc_status)
             OR (NEW.hc_reviewer_id IS DISTINCT FROM OLD.hc_reviewer_id)
             OR (NEW.hc_decided_at IS DISTINCT FROM OLD.hc_decided_at)
             OR (NEW.hc_notes IS DISTINCT FROM OLD.hc_notes);

  fin_changed := (NEW.finance_status IS DISTINCT FROM OLD.finance_status)
              OR (NEW.finance_reviewer_id IS DISTINCT FROM OLD.finance_reviewer_id)
              OR (NEW.finance_decided_at IS DISTINCT FROM OLD.finance_decided_at)
              OR (NEW.finance_notes IS DISTINCT FROM OLD.finance_notes)
              OR (NEW.decided_by IS DISTINCT FROM OLD.decided_by)
              OR (NEW.decided_at IS DISTINCT FROM OLD.decided_at);

  staff_self_cancel := (OLD.requester_user_id = uid)
                       AND (OLD.status = 'pending')
                       AND (NEW.status = 'cancelled')
                       AND NOT hc_changed
                       AND NOT fin_changed;

  IF staff_self_cancel THEN
    RETURN NEW;
  END IF;

  IF hc_changed AND NOT (can_hc OR can_payroll) THEN
    RAISE EXCEPTION 'not authorised to change HC review stage';
  END IF;

  IF fin_changed AND NOT (can_fin OR can_payroll) THEN
    RAISE EXCEPTION 'not authorised to change Finance review stage';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.finance_requests_stage_authz() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_finance_requests_stage_authz ON public.finance_requests;
CREATE TRIGGER trg_finance_requests_stage_authz
BEFORE UPDATE ON public.finance_requests
FOR EACH ROW
EXECUTE FUNCTION private.finance_requests_stage_authz();
