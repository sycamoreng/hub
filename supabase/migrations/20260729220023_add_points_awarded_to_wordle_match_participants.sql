ALTER TABLE wordle_match_participants
  ADD COLUMN IF NOT EXISTS points_awarded integer NOT NULL DEFAULT 0;