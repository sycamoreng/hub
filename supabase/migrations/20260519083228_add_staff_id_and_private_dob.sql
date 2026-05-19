/*
  # Add Staff ID and Private Date of Birth

  1. Modified Tables
    - `staff_members`
      - Add `staff_id` (text, unique, nullable) - company identifier like SISL-2024-167

  2. New Tables
    - `staff_private_data`
      - `id` (uuid, primary key, FK to staff_members.id)
      - `date_of_birth` (date, nullable)
      - `updated_at` (timestamptz)
    
    This table is separate from staff_members to ensure DOB is NEVER exposed 
    through the existing public SELECT policies on staff_members. Only admins 
    with 'staff' section permissions can access this table.

  3. Security
    - Enable RLS on staff_private_data
    - Only admins with staff section access can read/insert/update/delete
    - Regular staff and public CANNOT see date_of_birth

  4. Notes
    - DOB is sensitive personal data and must never be exposed publicly
    - Birthday notifications will use a service-role edge function to check this table
    - The staff_id is NOT sensitive and lives on the main table
*/

-- Add staff_id to staff_members
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'staff_members' AND column_name = 'staff_id'
  ) THEN
    ALTER TABLE staff_members ADD COLUMN staff_id text;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_members_staff_id 
  ON staff_members(staff_id) WHERE staff_id IS NOT NULL;

-- Create staff_private_data table
CREATE TABLE IF NOT EXISTS staff_private_data (
  id uuid PRIMARY KEY REFERENCES staff_members(id) ON DELETE CASCADE,
  date_of_birth date,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE staff_private_data ENABLE ROW LEVEL SECURITY;

-- RLS: Only admins with staff permissions can access
CREATE POLICY "Admins can view staff private data"
  ON staff_private_data FOR SELECT
  TO authenticated
  USING (private.admin_can('staff', 'read'));

CREATE POLICY "Admins can insert staff private data"
  ON staff_private_data FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('staff', 'create'));

CREATE POLICY "Admins can update staff private data"
  ON staff_private_data FOR UPDATE
  TO authenticated
  USING (private.admin_can('staff', 'update'))
  WITH CHECK (private.admin_can('staff', 'update'));

CREATE POLICY "Admins can delete staff private data"
  ON staff_private_data FOR DELETE
  TO authenticated
  USING (private.admin_can('staff', 'delete'));

-- Index on date_of_birth month/day for efficient birthday lookups
CREATE INDEX IF NOT EXISTS idx_staff_private_dob_month_day 
  ON staff_private_data (EXTRACT(MONTH FROM date_of_birth), EXTRACT(DAY FROM date_of_birth))
  WHERE date_of_birth IS NOT NULL;
