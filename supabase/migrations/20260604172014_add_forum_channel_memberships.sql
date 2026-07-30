/*
  # Add Forum Channel Memberships

  1. New Tables
    - `forum_channel_members`
      - `id` (uuid, primary key)
      - `category_id` (uuid, FK to forum_categories) - the channel
      - `user_id` (uuid, FK to auth.users) - the member
      - `joined_at` (timestamptz) - when they joined
      - UNIQUE (category_id, user_id)

  2. Security
    - RLS enabled
    - Users can see their own memberships
    - Users can join/leave channels themselves

  3. Notes
    - This enables Slack-style opt-in channel membership
    - Users only see threads from channels they have joined
*/

CREATE TABLE IF NOT EXISTS forum_channel_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES forum_categories(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at timestamptz DEFAULT now(),
  UNIQUE (category_id, user_id)
);

ALTER TABLE forum_channel_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own memberships"
  ON forum_channel_members FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can join channels"
  ON forum_channel_members FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can leave channels"
  ON forum_channel_members FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_forum_channel_members_user ON forum_channel_members(user_id);
CREATE INDEX IF NOT EXISTS idx_forum_channel_members_category ON forum_channel_members(category_id);
