/*
  # Add Admin Audit Log and Last Active Tracking

  1. New Tables
    - `admin_audit_log`
      - `id` (bigint, generated, primary key)
      - `admin_email` (text) - who performed the action
      - `action` (text) - what was done (create, update, delete, login, etc.)
      - `target_type` (text) - the entity type (staff, policy, product, etc.)
      - `target_id` (text, nullable) - specific record identifier
      - `target_label` (text, nullable) - human-readable name/title
      - `details` (jsonb, nullable) - extra context (old/new values, etc.)
      - `ip_address` (text, nullable)
      - `created_at` (timestamptz)

  2. Modified Tables
    - `admin_users`
      - Add `last_active_at` column (timestamptz, nullable)

  3. Security
    - Enable RLS on admin_audit_log
    - Super admins can read all audit logs
    - Admins can read their own audit logs
    - Insert allowed for authenticated (service writes via edge functions)

  4. Indexes
    - Index on admin_email for filtering by admin
    - Index on created_at for time-based queries
    - Index on target_type for filtering by entity
*/

-- Create audit log table
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  admin_email text NOT NULL DEFAULT '',
  action text NOT NULL DEFAULT '',
  target_type text NOT NULL DEFAULT '',
  target_id text,
  target_label text,
  details jsonb,
  ip_address text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;

-- Add last_active_at to admin_users
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'admin_users' AND column_name = 'last_active_at'
  ) THEN
    ALTER TABLE admin_users ADD COLUMN last_active_at timestamptz;
  END IF;
END $$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_audit_log_admin_email ON admin_audit_log(admin_email);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON admin_audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_target_type ON admin_audit_log(target_type);

-- RLS Policies for admin_audit_log
CREATE POLICY "Super admins can view all audit logs"
  ON admin_audit_log FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.email = lower(coalesce(auth.jwt() ->> 'email', ''))
        AND admin_users.role = 'super_admin'
    )
  );

CREATE POLICY "Admins can view own audit logs"
  ON admin_audit_log FOR SELECT
  TO authenticated
  USING (
    admin_email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );

CREATE POLICY "Authenticated users can insert audit logs"
  ON admin_audit_log FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_users
      WHERE admin_users.email = lower(coalesce(auth.jwt() ->> 'email', ''))
    )
  );
