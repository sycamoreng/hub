/*
  # Add Forums Feature

  1. New Tables
    - `forum_categories`
      - `id` (uuid, primary key)
      - `name` (text) - category title
      - `description` (text) - short description of the category
      - `slug` (text, unique) - URL-friendly identifier
      - `icon` (text) - emoji or icon identifier
      - `color` (text) - hex color for theming
      - `sort_order` (int) - display order
      - `is_active` (bool) - whether category is visible
      - `created_at` (timestamptz)

    - `forum_threads`
      - `id` (uuid, primary key)
      - `category_id` (uuid, FK to forum_categories)
      - `author_id` (uuid, FK to auth.users)
      - `title` (text) - thread title
      - `body` (text) - thread body content
      - `is_pinned` (bool) - pinned to top
      - `is_locked` (bool) - prevent new replies
      - `is_resolved` (bool) - marked as resolved
      - `views` (int) - view count
      - `last_reply_at` (timestamptz) - for sorting by activity
      - `reply_count` (int) - denormalized reply count
      - `created_at`, `updated_at` (timestamptz)

    - `forum_replies`
      - `id` (uuid, primary key)
      - `thread_id` (uuid, FK to forum_threads)
      - `author_id` (uuid, FK to auth.users)
      - `body` (text) - reply content
      - `is_accepted` (bool) - marked as accepted answer
      - `parent_reply_id` (uuid, nullable, FK to forum_replies) - nested replies
      - `created_at`, `updated_at` (timestamptz)

    - `forum_thread_votes`
      - `id` (uuid, primary key)
      - `thread_id` (uuid, FK to forum_threads)
      - `user_id` (uuid, FK to auth.users)
      - `vote` (int) - +1 or -1
      - UNIQUE (thread_id, user_id)

    - `forum_reply_votes`
      - `id` (uuid, primary key)
      - `reply_id` (uuid, FK to forum_replies)
      - `user_id` (uuid, FK to auth.users)
      - `vote` (int) - +1 or -1
      - UNIQUE (reply_id, user_id)

  2. Security
    - RLS enabled on all tables
    - Authenticated users can read all active forum content
    - Users can create threads and replies
    - Users can edit/delete their own content
    - Admins can manage categories and moderate content

  3. Notes
    - reply_count and last_reply_at on threads are denormalized for performance
    - Triggers maintain these automatically
    - Voting uses upsert pattern (change vote or remove)
*/

-- Forum Categories
CREATE TABLE IF NOT EXISTS forum_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text DEFAULT '',
  slug text UNIQUE NOT NULL,
  icon text DEFAULT '💬',
  color text DEFAULT '#3087b9',
  sort_order int DEFAULT 0,
  is_active bool DEFAULT true,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE forum_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone authenticated can view active categories"
  ON forum_categories FOR SELECT
  TO authenticated
  USING (is_active = true);

CREATE POLICY "Admins can insert categories"
  ON forum_categories FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM admin_users WHERE lower(email) = lower(auth.jwt()->>'email'))
  );

CREATE POLICY "Admins can update categories"
  ON forum_categories FOR UPDATE
  TO authenticated
  USING (EXISTS (SELECT 1 FROM admin_users WHERE lower(email) = lower(auth.jwt()->>'email')))
  WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE lower(email) = lower(auth.jwt()->>'email')));

CREATE POLICY "Admins can delete categories"
  ON forum_categories FOR DELETE
  TO authenticated
  USING (EXISTS (SELECT 1 FROM admin_users WHERE lower(email) = lower(auth.jwt()->>'email')));

-- Forum Threads
CREATE TABLE IF NOT EXISTS forum_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES forum_categories(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES auth.users(id),
  title text NOT NULL,
  body text NOT NULL DEFAULT '',
  is_pinned bool DEFAULT false,
  is_locked bool DEFAULT false,
  is_resolved bool DEFAULT false,
  views int DEFAULT 0,
  last_reply_at timestamptz DEFAULT now(),
  reply_count int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE forum_threads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view threads"
  ON forum_threads FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can create threads"
  ON forum_threads FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = author_id);

CREATE POLICY "Authors can update own threads"
  ON forum_threads FOR UPDATE
  TO authenticated
  USING (auth.uid() = author_id OR EXISTS (SELECT 1 FROM admin_users WHERE lower(email) = lower(auth.jwt()->>'email')))
  WITH CHECK (auth.uid() = author_id OR EXISTS (SELECT 1 FROM admin_users WHERE lower(email) = lower(auth.jwt()->>'email')));

CREATE POLICY "Authors and admins can delete threads"
  ON forum_threads FOR DELETE
  TO authenticated
  USING (auth.uid() = author_id OR EXISTS (SELECT 1 FROM admin_users WHERE lower(email) = lower(auth.jwt()->>'email')));

CREATE INDEX IF NOT EXISTS idx_forum_threads_category ON forum_threads(category_id, is_pinned DESC, last_reply_at DESC);
CREATE INDEX IF NOT EXISTS idx_forum_threads_author ON forum_threads(author_id);

-- Forum Replies
CREATE TABLE IF NOT EXISTS forum_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES forum_threads(id) ON DELETE CASCADE,
  author_id uuid NOT NULL REFERENCES auth.users(id),
  body text NOT NULL,
  is_accepted bool DEFAULT false,
  parent_reply_id uuid REFERENCES forum_replies(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE forum_replies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view replies"
  ON forum_replies FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can create replies"
  ON forum_replies FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = author_id
    AND NOT EXISTS (SELECT 1 FROM forum_threads WHERE id = thread_id AND is_locked = true)
  );

CREATE POLICY "Authors can update own replies"
  ON forum_replies FOR UPDATE
  TO authenticated
  USING (auth.uid() = author_id OR EXISTS (SELECT 1 FROM admin_users WHERE lower(email) = lower(auth.jwt()->>'email')))
  WITH CHECK (auth.uid() = author_id OR EXISTS (SELECT 1 FROM admin_users WHERE lower(email) = lower(auth.jwt()->>'email')));

CREATE POLICY "Authors and admins can delete replies"
  ON forum_replies FOR DELETE
  TO authenticated
  USING (auth.uid() = author_id OR EXISTS (SELECT 1 FROM admin_users WHERE lower(email) = lower(auth.jwt()->>'email')));

CREATE INDEX IF NOT EXISTS idx_forum_replies_thread ON forum_replies(thread_id, created_at);
CREATE INDEX IF NOT EXISTS idx_forum_replies_author ON forum_replies(author_id);

-- Thread Votes
CREATE TABLE IF NOT EXISTS forum_thread_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES forum_threads(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  vote int NOT NULL CHECK (vote IN (-1, 1)),
  created_at timestamptz DEFAULT now(),
  UNIQUE (thread_id, user_id)
);

ALTER TABLE forum_thread_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view thread votes"
  ON forum_thread_votes FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can insert own thread votes"
  ON forum_thread_votes FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own thread votes"
  ON forum_thread_votes FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own thread votes"
  ON forum_thread_votes FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- Reply Votes
CREATE TABLE IF NOT EXISTS forum_reply_votes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reply_id uuid NOT NULL REFERENCES forum_replies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  vote int NOT NULL CHECK (vote IN (-1, 1)),
  created_at timestamptz DEFAULT now(),
  UNIQUE (reply_id, user_id)
);

ALTER TABLE forum_reply_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view reply votes"
  ON forum_reply_votes FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can insert own reply votes"
  ON forum_reply_votes FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own reply votes"
  ON forum_reply_votes FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own reply votes"
  ON forum_reply_votes FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- Trigger: update reply_count and last_reply_at on new reply
CREATE OR REPLACE FUNCTION update_thread_reply_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE forum_threads
    SET reply_count = reply_count + 1,
        last_reply_at = NEW.created_at,
        updated_at = now()
    WHERE id = NEW.thread_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE forum_threads
    SET reply_count = GREATEST(0, reply_count - 1),
        last_reply_at = COALESCE(
          (SELECT MAX(created_at) FROM forum_replies WHERE thread_id = OLD.thread_id AND id != OLD.id),
          (SELECT created_at FROM forum_threads WHERE id = OLD.thread_id)
        ),
        updated_at = now()
    WHERE id = OLD.thread_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_forum_reply_stats ON forum_replies;
CREATE TRIGGER trg_forum_reply_stats
  AFTER INSERT OR DELETE ON forum_replies
  FOR EACH ROW
  EXECUTE FUNCTION update_thread_reply_stats();

-- Seed default categories
INSERT INTO forum_categories (name, description, slug, icon, color, sort_order) VALUES
  ('General Discussion', 'Chat about anything work-related or off-topic', 'general', '💬', '#3087b9', 1),
  ('Ideas & Suggestions', 'Share ideas to make Sycamore better', 'ideas', '💡', '#F59E0B', 2),
  ('Help & Questions', 'Ask questions and get help from colleagues', 'help', '🙋', '#10B981', 3),
  ('Tech Talk', 'Discuss technology, tools, and engineering topics', 'tech', '⚡', '#6366F1', 4),
  ('Random & Fun', 'Memes, jokes, and casual vibes', 'random', '🎲', '#EC4899', 5)
ON CONFLICT (slug) DO NOTHING;
