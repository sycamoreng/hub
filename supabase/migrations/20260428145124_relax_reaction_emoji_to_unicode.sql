/*
  # Relax reactions.emoji to allow any unicode emoji

  1. Modified Tables
    - `reactions`
      - Drop the legacy CHECK constraint that limited `emoji` to a fixed
        identifier set ('like','celebrate', ...). The column now stores arbitrary
        short unicode emoji strings (e.g. a thumbs-up character) so the UI can
        offer a wide picker.
      - A length cap is applied (max 16 characters) to keep storage tidy and
        prevent abuse.

  2. Notes
    - No data is dropped. Existing rows (if any used the old identifiers) are
      left intact; the application layer will treat them as historical entries.
    - RLS policies are unchanged.
*/

ALTER TABLE public.reactions
  DROP CONSTRAINT IF EXISTS reactions_emoji_check;

ALTER TABLE public.reactions
  ADD CONSTRAINT reactions_emoji_length_check
  CHECK (char_length(emoji) BETWEEN 1 AND 16);
