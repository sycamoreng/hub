-- Add rounds infra to all game match tables
ALTER TABLE wordle_matches ADD COLUMN IF NOT EXISTS total_rounds int NOT NULL DEFAULT 1;
ALTER TABLE wordle_matches ADD COLUMN IF NOT EXISTS current_round int NOT NULL DEFAULT 1;
ALTER TABLE guess_who_matches ADD COLUMN IF NOT EXISTS total_rounds int NOT NULL DEFAULT 1;
ALTER TABLE guess_who_matches ADD COLUMN IF NOT EXISTS current_round int NOT NULL DEFAULT 1;
ALTER TABLE dino_matches ADD COLUMN IF NOT EXISTS total_rounds int NOT NULL DEFAULT 1;
ALTER TABLE dino_matches ADD COLUMN IF NOT EXISTS current_round int NOT NULL DEFAULT 1;
ALTER TABLE codebreaker_matches ADD COLUMN IF NOT EXISTS total_rounds int NOT NULL DEFAULT 1;
ALTER TABLE codebreaker_matches ADD COLUMN IF NOT EXISTS current_round int NOT NULL DEFAULT 1;
ALTER TABLE crossword_matches ADD COLUMN IF NOT EXISTS total_rounds int NOT NULL DEFAULT 1;
ALTER TABLE crossword_matches ADD COLUMN IF NOT EXISTS current_round int NOT NULL DEFAULT 1;
ALTER TABLE typing_matches ADD COLUMN IF NOT EXISTS total_rounds int NOT NULL DEFAULT 1;
ALTER TABLE typing_matches ADD COLUMN IF NOT EXISTS current_round int NOT NULL DEFAULT 1;

ALTER TABLE wordle_match_participants ADD COLUMN IF NOT EXISTS series_points int NOT NULL DEFAULT 0;
ALTER TABLE wordle_match_participants ADD COLUMN IF NOT EXISTS series_wins int NOT NULL DEFAULT 0;
ALTER TABLE guess_who_match_participants ADD COLUMN IF NOT EXISTS series_points int NOT NULL DEFAULT 0;
ALTER TABLE guess_who_match_participants ADD COLUMN IF NOT EXISTS series_wins int NOT NULL DEFAULT 0;
ALTER TABLE dino_match_participants ADD COLUMN IF NOT EXISTS series_points int NOT NULL DEFAULT 0;
ALTER TABLE dino_match_participants ADD COLUMN IF NOT EXISTS series_wins int NOT NULL DEFAULT 0;
ALTER TABLE codebreaker_match_participants ADD COLUMN IF NOT EXISTS series_points int NOT NULL DEFAULT 0;
ALTER TABLE codebreaker_match_participants ADD COLUMN IF NOT EXISTS series_wins int NOT NULL DEFAULT 0;
ALTER TABLE crossword_match_participants ADD COLUMN IF NOT EXISTS series_points int NOT NULL DEFAULT 0;
ALTER TABLE crossword_match_participants ADD COLUMN IF NOT EXISTS series_wins int NOT NULL DEFAULT 0;
ALTER TABLE typing_match_participants ADD COLUMN IF NOT EXISTS series_points int NOT NULL DEFAULT 0;
ALTER TABLE typing_match_participants ADD COLUMN IF NOT EXISTS series_wins int NOT NULL DEFAULT 0;