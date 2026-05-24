/*
  # Add celebration bot support and chat space configuration

  1. Modified Tables
    - `posts`
      - Make `author_id` nullable to support bot-authored posts
    - `company_info`
      - Insert celebration_chat_space_id setting

  2. New Functionality
    - Posts with NULL author_id are treated as bot posts
    - celebration_chat_space_id links celebrations to a Google Chat space for broadcasting

  3. Important Notes
    - Existing posts are unaffected (all have author_id set)
    - The feed UI will display "Sycamore Bot" for posts where author_id IS NULL
    - RLS policies remain intact - bot posts are visible to all authenticated users
*/

-- Allow posts to have no author (bot posts)
ALTER TABLE posts ALTER COLUMN author_id DROP NOT NULL;

-- Add celebration chat space configuration
INSERT INTO company_info (info_key, info_value, category, display_order)
SELECT 'celebration_chat_space_id', '', 'celebrations', 100
WHERE NOT EXISTS (
  SELECT 1 FROM company_info WHERE info_key = 'celebration_chat_space_id'
);
