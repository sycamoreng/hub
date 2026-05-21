/*
  # Add new badges and guess_who metric support

  1. New Badges
    - `detective` - Guessed correctly 3 times in Guess Who (30 pts)
    - `sleuth` - Guessed correctly 10 times in Guess Who (75 pts)
    - `wordsmith` - Won 5 Wordle puzzles (35 pts)
    - `speed_demon` - Achieved 60+ WPM in Typing Sprint (40 pts)
    - `social_butterfly` - Created 10 posts (50 pts)
    - `helper` - Left 25 comments (40 pts)
    - `generous` - Gave 15 kudos (50 pts)
    - `legend` - Reached 1000 points (200 pts)

  2. Changes
    - Adds new badge entries to support gamification across all games
    - Higher sort_order to appear after existing badges
*/

-- Insert new badges
INSERT INTO badges (code, name, description, emoji, color, threshold, metric, points_award, sort_order, is_active)
VALUES
  ('detective', 'Detective', 'Guessed correctly 3 times in Guess Who', '🔍', 'sky', 3, 'guess_who_correct_count', 30, 9, true),
  ('sleuth', 'Sleuth', 'Guessed correctly 10 times in Guess Who', '🕵️', 'teal', 10, 'guess_who_correct_count', 75, 10, true),
  ('wordsmith', 'Wordsmith', 'Won 5 Wordle puzzles', '📝', 'emerald', 5, 'wordle_win_count', 35, 11, true),
  ('speed_demon', 'Speed Demon', 'Achieved 60+ WPM in Typing Sprint', '⚡', 'amber', 1, 'typing_60wpm_count', 40, 12, true),
  ('social_butterfly', 'Social Butterfly', 'Created 10 posts', '🦋', 'rose', 10, 'posts_count', 50, 13, true),
  ('helper', 'Helper', 'Left 25 comments', '🙌', 'sky', 25, 'comments_count', 40, 14, true),
  ('generous', 'Generous', 'Gave 15 kudos', '💝', 'rose', 15, 'kudos_given_count', 50, 15, true),
  ('legend', 'Legend', 'Reached 1000 points', '👑', 'amber', 1000, 'points_total', 200, 16, true)
ON CONFLICT (code) DO NOTHING;
