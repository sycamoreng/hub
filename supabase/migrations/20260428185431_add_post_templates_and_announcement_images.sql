/*
  # Post templates, post images, announcement images

  1. Posts
    - Adds `image_url` (text) for press-style image posts.
    - Adds `post_kind` (text, default 'standard') to mark special posts: birthday, anniversary, mood, milestone, kudos, welcome, congrats.
    - Adds `template_data` (jsonb, default '{}'::jsonb) for template-specific data (years, person mentioned, mood emoji, etc.)
  2. Announcements
    - Adds `image_url` (text) for press-style hero image on announcements.
    - Adds `summary` (text) optional dek/standfirst displayed under title.
  3. Security
    - No policy changes required: existing RLS already gates inserts to authenticated users with author_id match, and selects to authenticated.
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'posts' AND column_name = 'image_url'
  ) THEN
    ALTER TABLE posts ADD COLUMN image_url text DEFAULT '';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'posts' AND column_name = 'post_kind'
  ) THEN
    ALTER TABLE posts ADD COLUMN post_kind text DEFAULT 'standard';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'posts' AND column_name = 'template_data'
  ) THEN
    ALTER TABLE posts ADD COLUMN template_data jsonb DEFAULT '{}'::jsonb;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'announcements' AND column_name = 'image_url'
  ) THEN
    ALTER TABLE announcements ADD COLUMN image_url text DEFAULT '';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'announcements' AND column_name = 'summary'
  ) THEN
    ALTER TABLE announcements ADD COLUMN summary text DEFAULT '';
  END IF;
END $$;
