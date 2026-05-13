/*
  # Restore EXECUTE on RLS helper functions

  Earlier hardening revoked EXECUTE on `is_attendance_admin`, `is_payroll_admin`,
  and `is_email_admin` from `authenticated`. These helpers are referenced inside
  Row Level Security policies; PostgreSQL evaluates policy expressions as the
  calling role, so the calling role must have EXECUTE — SECURITY DEFINER does
  not bypass that check. The result was admins getting `permission denied for
  function is_attendance_admin` on the attendance admin page.

  1. Changes
     - GRANT EXECUTE on the three helper functions back to `authenticated`.
     - Keep them out of `anon`/`public` so unauthenticated callers still cannot run them.

  2. Security
     - The helpers themselves only return boolean role checks; they reveal no data.
     - Without this grant, RLS policies that use them silently fail with 42501.
*/

GRANT EXECUTE ON FUNCTION public.is_attendance_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_payroll_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_email_admin() TO authenticated;
