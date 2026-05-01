/*
  # Fix quick_tools admin RLS policies

  The existing INSERT / UPDATE / DELETE policies compared
  `admin_users.email` directly against `lower(auth.jwt() ->> 'email')`.
  If an admin row stored the email with any uppercase character, the
  comparison failed and valid admins were blocked from inserting rows.

  This migration drops those three policies and re-creates them with a
  case-insensitive comparison on both sides (`lower(au.email) = lower(jwt email)`).

  1. Changes
    - Drop and recreate `Admins can insert quick tools`
    - Drop and recreate `Admins can update quick tools`
    - Drop and recreate `Admins can delete quick tools`

  2. Security
    - RLS remains enabled
    - SELECT policy (active rows for authenticated) is untouched
    - Only admins (case-insensitive email match) can mutate
*/

DROP POLICY IF EXISTS "Admins can insert quick tools" ON quick_tools;
DROP POLICY IF EXISTS "Admins can update quick tools" ON quick_tools;
DROP POLICY IF EXISTS "Admins can delete quick tools" ON quick_tools;

CREATE POLICY "Admins can insert quick tools"
  ON quick_tools FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users au
      WHERE lower(au.email) = lower(auth.jwt() ->> 'email')
    )
  );

CREATE POLICY "Admins can update quick tools"
  ON quick_tools FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users au
      WHERE lower(au.email) = lower(auth.jwt() ->> 'email')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users au
      WHERE lower(au.email) = lower(auth.jwt() ->> 'email')
    )
  );

CREATE POLICY "Admins can delete quick tools"
  ON quick_tools FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users au
      WHERE lower(au.email) = lower(auth.jwt() ->> 'email')
    )
  );
