/*
  # Create leadership table

  1. New Tables
    - `leadership`
      - `id` (uuid, primary key)
      - `full_name` (text, required)
      - `title` (text, required) - e.g. "Chief Executive Officer"
      - `tier` (text, required) - one of: 'board', 'executive', 'senior'
      - `bio` (text)
      - `email` (text)
      - `phone` (text)
      - `photo_url` (text)
      - `linkedin_url` (text)
      - `display_order` (int) - manual ordering within a tier
      - `is_active` (bool)
      - `created_at` (timestamptz)
  2. Security
    - Enable RLS
    - Public SELECT for active rows (anon + authenticated)
    - Authenticated INSERT/UPDATE/DELETE for admins via login
*/

CREATE TABLE IF NOT EXISTS leadership (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text NOT NULL,
  title text NOT NULL DEFAULT '',
  tier text NOT NULL DEFAULT 'executive',
  bio text DEFAULT '',
  email text DEFAULT '',
  phone text DEFAULT '',
  photo_url text DEFAULT '',
  linkedin_url text DEFAULT '',
  display_order integer DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT leadership_tier_check CHECK (tier IN ('board', 'executive', 'senior'))
);

ALTER TABLE leadership ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active leadership"
  ON leadership FOR SELECT
  TO anon, authenticated
  USING (is_active = true);

CREATE POLICY "Authenticated users can insert leadership"
  ON leadership FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Authenticated users can update leadership"
  ON leadership FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Authenticated users can delete leadership"
  ON leadership FOR DELETE
  TO authenticated
  USING (true);
