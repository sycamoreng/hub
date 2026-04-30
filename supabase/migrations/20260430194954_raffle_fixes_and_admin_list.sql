/*
  # Raffle fixes and admin list function

  1. Changes
    - Grant EXECUTE on is_email_admin() to authenticated. RLS policies that
      call it were failing with "permission denied for function is_email_admin"
      when triggered by client-side UPDATEs (e.g. saving a prize quantity).
    - Add `visible_on_sidebar` boolean to raffle_settings so admins can toggle
      the staff-facing /raffle page from appearing in the sidebar nav.
    - Add `raffle_allocations_admin()` RPC that returns full staff-by-staff
      results (who spun, what they won, who hasn't spun yet) for admin dashboards.
*/

GRANT EXECUTE ON FUNCTION public.is_email_admin() TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'raffle_settings' AND column_name = 'visible_on_sidebar'
  ) THEN
    ALTER TABLE raffle_settings ADD COLUMN visible_on_sidebar boolean NOT NULL DEFAULT true;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION raffle_allocations_admin()
RETURNS TABLE (
  staff_id uuid,
  full_name text,
  email text,
  is_blank boolean,
  prize_id uuid,
  prize_name text,
  prize_color text,
  prize_icon text,
  revealed_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_email_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  RETURN QUERY
  SELECT
    s.id, s.full_name, s.email,
    a.is_blank,
    a.prize_id,
    p.name, p.color, p.icon,
    a.revealed_at
  FROM staff_members s
  LEFT JOIN raffle_allocations a ON a.staff_member_id = s.id
  LEFT JOIN raffle_prizes p ON p.id = a.prize_id
  WHERE s.is_active IS NOT FALSE
  ORDER BY a.revealed_at DESC NULLS LAST, s.full_name ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION raffle_allocations_admin() TO authenticated;
