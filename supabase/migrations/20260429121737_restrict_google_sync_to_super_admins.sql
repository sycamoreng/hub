/*
  # Restrict Google Sync to super admins

  ## Summary
  Previously, any admin could view Google Sync settings, rules, department map, and runs. Only super admins could apply changes.
  This migration tightens RLS so that ONLY super admins can read/write the Google Sync tables.

  ## Changes
  1. Security
    - Replace `Admins read ...` policies on google_sync_settings, google_sync_rules, google_department_map, google_sync_runs
      with policies requiring `private.is_super_admin()`.
    - Replace insert/update/delete policies on google_sync_rules and google_department_map with super-admin-only checks.
*/

DO $$
BEGIN
  DROP POLICY IF EXISTS "Admins read sync settings" ON google_sync_settings;
  CREATE POLICY "Super admins read sync settings" ON google_sync_settings FOR SELECT TO authenticated
    USING (private.is_super_admin());

  DROP POLICY IF EXISTS "Admins read sync rules" ON google_sync_rules;
  CREATE POLICY "Super admins read sync rules" ON google_sync_rules FOR SELECT TO authenticated
    USING (private.is_super_admin());

  DROP POLICY IF EXISTS "Admins insert sync rules" ON google_sync_rules;
  CREATE POLICY "Super admins insert sync rules" ON google_sync_rules FOR INSERT TO authenticated
    WITH CHECK (private.is_super_admin());

  DROP POLICY IF EXISTS "Admins update sync rules" ON google_sync_rules;
  CREATE POLICY "Super admins update sync rules" ON google_sync_rules FOR UPDATE TO authenticated
    USING (private.is_super_admin()) WITH CHECK (private.is_super_admin());

  DROP POLICY IF EXISTS "Admins delete sync rules" ON google_sync_rules;
  CREATE POLICY "Super admins delete sync rules" ON google_sync_rules FOR DELETE TO authenticated
    USING (private.is_super_admin());

  DROP POLICY IF EXISTS "Admins read dept map" ON google_department_map;
  CREATE POLICY "Super admins read dept map" ON google_department_map FOR SELECT TO authenticated
    USING (private.is_super_admin());

  DROP POLICY IF EXISTS "Admins insert dept map" ON google_department_map;
  CREATE POLICY "Super admins insert dept map" ON google_department_map FOR INSERT TO authenticated
    WITH CHECK (private.is_super_admin());

  DROP POLICY IF EXISTS "Admins update dept map" ON google_department_map;
  CREATE POLICY "Super admins update dept map" ON google_department_map FOR UPDATE TO authenticated
    USING (private.is_super_admin()) WITH CHECK (private.is_super_admin());

  DROP POLICY IF EXISTS "Admins delete dept map" ON google_department_map;
  CREATE POLICY "Super admins delete dept map" ON google_department_map FOR DELETE TO authenticated
    USING (private.is_super_admin());

  DROP POLICY IF EXISTS "Admins read sync runs" ON google_sync_runs;
  CREATE POLICY "Super admins read sync runs" ON google_sync_runs FOR SELECT TO authenticated
    USING (private.is_super_admin());
END $$;
