/*
  # Add page locks

  Adds a lightweight table that records which pages are locked so admins can
  hide pages from regular users while still allowing admins to preview them.

  1. New Tables
    - `page_locks`
      - `path` (text, primary key) - the route path e.g. `/benefits`
      - `locked` (boolean, default false) - whether the page is hidden from
        non-admin users
      - `updated_at` (timestamptz, default now())
  2. Security
    - Enable RLS on `page_locks`
    - SELECT: any authenticated user (sidebar and middleware need to read it)
    - INSERT/UPDATE/DELETE: super admins only
*/

CREATE TABLE IF NOT EXISTS page_locks (
  path text PRIMARY KEY,
  locked boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE page_locks ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'page_locks' AND policyname = 'Authenticated can read page locks') THEN
    CREATE POLICY "Authenticated can read page locks"
      ON page_locks FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'page_locks' AND policyname = 'Super admins can insert page locks') THEN
    CREATE POLICY "Super admins can insert page locks"
      ON page_locks FOR INSERT
      TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM admin_users a
          WHERE lower(a.email) = lower(auth.jwt() ->> 'email')
            AND a.role = 'super_admin'
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'page_locks' AND policyname = 'Super admins can update page locks') THEN
    CREATE POLICY "Super admins can update page locks"
      ON page_locks FOR UPDATE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM admin_users a
          WHERE lower(a.email) = lower(auth.jwt() ->> 'email')
            AND a.role = 'super_admin'
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM admin_users a
          WHERE lower(a.email) = lower(auth.jwt() ->> 'email')
            AND a.role = 'super_admin'
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'page_locks' AND policyname = 'Super admins can delete page locks') THEN
    CREATE POLICY "Super admins can delete page locks"
      ON page_locks FOR DELETE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM admin_users a
          WHERE lower(a.email) = lower(auth.jwt() ->> 'email')
            AND a.role = 'super_admin'
        )
      );
  END IF;
END $$;
