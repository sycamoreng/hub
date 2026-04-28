/*
  # Rich post templates and announcement images

  1. Posts
    - Add `post_type` (text, default 'standard') so users can publish themed posts
      (birthday, anniversary, milestone, achievement, shoutout, question, celebration).
    - Add `template_data` (jsonb) for per-template fields such as years celebrated,
      colleague mentioned, or accent colour overrides.
    - Add `image_url` (text) so a post can include a single hero image.

  2. Announcements
    - Add `image_url` (text) so company announcements can be presented as press
      posts with a banner image.

  3. Notes
    - All new columns are nullable / have safe defaults so existing rows continue
      to behave as standard posts / image-less announcements.
    - No RLS changes needed; existing policies still apply because we only added
      columns to existing tables.
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'posts' AND column_name = 'post_type'
  ) THEN
    ALTER TABLE posts ADD COLUMN post_type text NOT NULL DEFAULT 'standard';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'posts' AND column_name = 'template_data'
  ) THEN
    ALTER TABLE posts ADD COLUMN template_data jsonb NOT NULL DEFAULT '{}'::jsonb;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'posts' AND column_name = 'image_url'
  ) THEN
    ALTER TABLE posts ADD COLUMN image_url text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'announcements' AND column_name = 'image_url'
  ) THEN
    ALTER TABLE announcements ADD COLUMN image_url text;
  END IF;
END $$;
