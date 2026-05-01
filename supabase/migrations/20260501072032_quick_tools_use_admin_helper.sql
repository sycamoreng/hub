/*
  # Quick tools: use SECURITY DEFINER admin helper

  The existing quick_tools write policies embed a direct subquery against
  public.admin_users. That subquery is itself subject to RLS on admin_users
  (which restricts reads to super admins via private.is_super_admin()).
  When admin_users RLS combined with the PostgREST session yields zero rows,
  the INSERT policy fails with "new row violates row-level security policy".

  This migration switches quick_tools write policies to use the
  SECURITY DEFINER helper `private.is_super_admin()` which bypasses RLS and
  reliably returns true for super admins. This also aligns quick_tools with
  how other admin-managed tables in the codebase gate writes.

  1. Changes
    - Drop existing INSERT / UPDATE / DELETE policies on quick_tools
    - Recreate them guarded by private.is_super_admin()

  2. Security
    - RLS remains enabled
    - SELECT policy for active rows is unchanged
    - Writes restricted to super admins (current intent - all existing
      admin_users rows are super_admin)
*/

DROP POLICY IF EXISTS "Admins can insert quick tools" ON quick_tools;
DROP POLICY IF EXISTS "Admins can update quick tools" ON quick_tools;
DROP POLICY IF EXISTS "Admins can delete quick tools" ON quick_tools;

CREATE POLICY "Admins can insert quick tools"
  ON quick_tools FOR INSERT
  TO authenticated
  WITH CHECK (private.is_super_admin());

CREATE POLICY "Admins can update quick tools"
  ON quick_tools FOR UPDATE
  TO authenticated
  USING (private.is_super_admin())
  WITH CHECK (private.is_super_admin());

CREATE POLICY "Admins can delete quick tools"
  ON quick_tools FOR DELETE
  TO authenticated
  USING (private.is_super_admin());
