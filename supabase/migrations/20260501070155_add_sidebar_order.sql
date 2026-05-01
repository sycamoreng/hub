/*
  # Sidebar Section Order

  Stores a global, organization-wide order for client sidebar groups.
  Admins manage this from the admin panel; staff see the configured order.

  1. New Tables
    - `sidebar_order`
      - `id` (int, primary key, always 1 - single-row config)
      - `groups` (text[]) - ordered list of group ids
      - `updated_at` (timestamptz)

  2. Security
    - Enable RLS
    - Authenticated users can read the order (needed to render sidebar)
    - Only admins can insert / update (mutations funneled via policies that
      check admin_users membership)
*/

CREATE TABLE IF NOT EXISTS sidebar_order (
  id int PRIMARY KEY DEFAULT 1,
  groups text[] NOT NULL DEFAULT ARRAY[]::text[],
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sidebar_order_singleton CHECK (id = 1)
);

ALTER TABLE sidebar_order ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'sidebar_order' AND policyname = 'Authenticated can read sidebar order'
  ) THEN
    CREATE POLICY "Authenticated can read sidebar order"
      ON sidebar_order FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'sidebar_order' AND policyname = 'Admins can insert sidebar order'
  ) THEN
    CREATE POLICY "Admins can insert sidebar order"
      ON sidebar_order FOR INSERT
      TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM admin_users au
          WHERE lower(au.email) = lower(auth.jwt() ->> 'email')
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'sidebar_order' AND policyname = 'Admins can update sidebar order'
  ) THEN
    CREATE POLICY "Admins can update sidebar order"
      ON sidebar_order FOR UPDATE
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
  END IF;
END $$;

INSERT INTO sidebar_order (id, groups)
VALUES (1, ARRAY['company','productivity','work','people','comms']::text[])
ON CONFLICT (id) DO NOTHING;
