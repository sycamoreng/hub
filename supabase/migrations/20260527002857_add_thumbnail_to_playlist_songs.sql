/*
  # Add thumbnail URL to playlist songs

  1. Modified Tables
    - `playlist_songs`
      - `thumbnail_url` (text, nullable) - Album art or video thumbnail URL from streaming service

  2. Important Notes
    - Existing songs will have NULL thumbnail (no data loss)
    - Thumbnail is populated automatically when songs are added via streaming link
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'playlist_songs' AND column_name = 'thumbnail_url'
  ) THEN
    ALTER TABLE playlist_songs ADD COLUMN thumbnail_url text;
  END IF;
END $$;
