/*
  # Align post template fields with feed.vue (post_kind)

  1. Posts
    - Add `post_kind` (text, default 'standard') as the canonical column used by
      the feed and home page templates.
    - Backfill `post_kind` from the previously added `post_type` column so any
      existing rows keep their current template selection.

  2. Announcements
    - Add a `summary` text column for the headline preview shown on press-style
      announcements (single-line teaser above the body).

  3. Notes
    - All new columns are nullable / have safe defaults so existing rows keep
      working unchanged.
    - We are only adding columns, no destructive operations or renames.
    - RLS unchanged: existing per-table policies still apply.
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'posts' AND column_name = 'post_kind'
  ) THEN
    ALTER TABLE posts ADD COLUMN post_kind text NOT NULL DEFAULT 'standard';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'posts' AND column_name = 'post_type'
  ) THEN
    UPDATE posts SET post_kind = post_type
    WHERE post_kind = 'standard' AND post_type IS NOT NULL AND post_type <> 'standard';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'announcements' AND column_name = 'summary'
  ) THEN
    ALTER TABLE announcements ADD COLUMN summary text;
  END IF;
END $$;
