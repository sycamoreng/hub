/*
  # Backfill new badges from historical activity

  1. Awards
    - `speed_demon` - Users with at least 1 typing run at 60+ WPM (40 pts)
    - `legend` - Users with 1000+ total lifetime points (200 pts)
    - `detective` - Users with 3+ correct Guess Who attempts (30 pts)
    - `sleuth` - Users with 10+ correct Guess Who attempts (75 pts)
    - `social_butterfly` - Users with 10+ posts (50 pts)
    - `helper` - Users with 25+ comments (40 pts)
    - `generous` - Users with 15+ kudos given (50 pts)
    - `wordsmith` - Users with 5+ wordle wins (35 pts)

  2. Notes
    - Only awards badges to users who don't already have them
    - Awards bonus points for each new badge
    - Creates notifications for awarded badges
*/

DO $$
DECLARE
  v_badge_id uuid;
  v_user_id uuid;
  v_award int;
  v_badge_name text;
BEGIN
  -- Speed Demon: users with at least 1 typing run >= 60 WPM
  SELECT id, points_award, name INTO v_badge_id, v_award, v_badge_name
  FROM badges WHERE code = 'speed_demon' AND is_active = true;

  IF v_badge_id IS NOT NULL THEN
    FOR v_user_id IN
      SELECT DISTINCT user_id FROM typing_runs WHERE wpm >= 60
    LOOP
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = v_user_id AND badge_id = v_badge_id) THEN
        INSERT INTO user_badges (user_id, badge_id) VALUES (v_user_id, v_badge_id);
        IF v_award > 0 THEN
          INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
          VALUES (v_user_id, 'badge_awarded', 'badge', v_badge_id::text, v_award, v_badge_name);
        END IF;
        INSERT INTO notifications (recipient_id, type, title, body, link)
        VALUES (v_user_id, 'badge_awarded', 'New badge: ' || v_badge_name, 'Achieved 60+ WPM in Typing Sprint', '/recognition');
      END IF;
    END LOOP;
  END IF;

  -- Legend: users with 1000+ total points
  SELECT id, points_award, name INTO v_badge_id, v_award, v_badge_name
  FROM badges WHERE code = 'legend' AND is_active = true;

  IF v_badge_id IS NOT NULL THEN
    FOR v_user_id IN
      SELECT user_id FROM points_events GROUP BY user_id HAVING sum(points) >= 1000
    LOOP
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = v_user_id AND badge_id = v_badge_id) THEN
        INSERT INTO user_badges (user_id, badge_id) VALUES (v_user_id, v_badge_id);
        IF v_award > 0 THEN
          INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
          VALUES (v_user_id, 'badge_awarded', 'badge', v_badge_id::text, v_award, v_badge_name);
        END IF;
        INSERT INTO notifications (recipient_id, type, title, body, link)
        VALUES (v_user_id, 'badge_awarded', 'New badge: ' || v_badge_name, 'Reached 1000 points', '/recognition');
      END IF;
    END LOOP;
  END IF;

  -- Detective: users with 3+ correct Guess Who attempts
  SELECT id, points_award, name INTO v_badge_id, v_award, v_badge_name
  FROM badges WHERE code = 'detective' AND is_active = true;

  IF v_badge_id IS NOT NULL THEN
    FOR v_user_id IN
      SELECT user_id FROM guess_who_attempts WHERE won = true GROUP BY user_id HAVING count(*) >= 3
    LOOP
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = v_user_id AND badge_id = v_badge_id) THEN
        INSERT INTO user_badges (user_id, badge_id) VALUES (v_user_id, v_badge_id);
        IF v_award > 0 THEN
          INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
          VALUES (v_user_id, 'badge_awarded', 'badge', v_badge_id::text, v_award, v_badge_name);
        END IF;
        INSERT INTO notifications (recipient_id, type, title, body, link)
        VALUES (v_user_id, 'badge_awarded', 'New badge: ' || v_badge_name, 'Guessed correctly 3 times in Guess Who', '/recognition');
      END IF;
    END LOOP;
  END IF;

  -- Sleuth: users with 10+ correct Guess Who attempts
  SELECT id, points_award, name INTO v_badge_id, v_award, v_badge_name
  FROM badges WHERE code = 'sleuth' AND is_active = true;

  IF v_badge_id IS NOT NULL THEN
    FOR v_user_id IN
      SELECT user_id FROM guess_who_attempts WHERE won = true GROUP BY user_id HAVING count(*) >= 10
    LOOP
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = v_user_id AND badge_id = v_badge_id) THEN
        INSERT INTO user_badges (user_id, badge_id) VALUES (v_user_id, v_badge_id);
        IF v_award > 0 THEN
          INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
          VALUES (v_user_id, 'badge_awarded', 'badge', v_badge_id::text, v_award, v_badge_name);
        END IF;
        INSERT INTO notifications (recipient_id, type, title, body, link)
        VALUES (v_user_id, 'badge_awarded', 'New badge: ' || v_badge_name, 'Guessed correctly 10 times in Guess Who', '/recognition');
      END IF;
    END LOOP;
  END IF;

  -- Social Butterfly: users with 10+ posts
  SELECT id, points_award, name INTO v_badge_id, v_award, v_badge_name
  FROM badges WHERE code = 'social_butterfly' AND is_active = true;

  IF v_badge_id IS NOT NULL THEN
    FOR v_user_id IN
      SELECT author_id FROM posts GROUP BY author_id HAVING count(*) >= 10
    LOOP
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = v_user_id AND badge_id = v_badge_id) THEN
        INSERT INTO user_badges (user_id, badge_id) VALUES (v_user_id, v_badge_id);
        IF v_award > 0 THEN
          INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
          VALUES (v_user_id, 'badge_awarded', 'badge', v_badge_id::text, v_award, v_badge_name);
        END IF;
        INSERT INTO notifications (recipient_id, type, title, body, link)
        VALUES (v_user_id, 'badge_awarded', 'New badge: ' || v_badge_name, 'Created 10 posts', '/recognition');
      END IF;
    END LOOP;
  END IF;

  -- Helper: users with 25+ comments
  SELECT id, points_award, name INTO v_badge_id, v_award, v_badge_name
  FROM badges WHERE code = 'helper' AND is_active = true;

  IF v_badge_id IS NOT NULL THEN
    FOR v_user_id IN
      SELECT user_id FROM comments GROUP BY user_id HAVING count(*) >= 25
    LOOP
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = v_user_id AND badge_id = v_badge_id) THEN
        INSERT INTO user_badges (user_id, badge_id) VALUES (v_user_id, v_badge_id);
        IF v_award > 0 THEN
          INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
          VALUES (v_user_id, 'badge_awarded', 'badge', v_badge_id::text, v_award, v_badge_name);
        END IF;
        INSERT INTO notifications (recipient_id, type, title, body, link)
        VALUES (v_user_id, 'badge_awarded', 'New badge: ' || v_badge_name, 'Left 25 comments', '/recognition');
      END IF;
    END LOOP;
  END IF;

  -- Generous: users with 15+ kudos given
  SELECT id, points_award, name INTO v_badge_id, v_award, v_badge_name
  FROM badges WHERE code = 'generous' AND is_active = true;

  IF v_badge_id IS NOT NULL THEN
    FOR v_user_id IN
      SELECT from_user_id FROM kudos GROUP BY from_user_id HAVING count(*) >= 15
    LOOP
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = v_user_id AND badge_id = v_badge_id) THEN
        INSERT INTO user_badges (user_id, badge_id) VALUES (v_user_id, v_badge_id);
        IF v_award > 0 THEN
          INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
          VALUES (v_user_id, 'badge_awarded', 'badge', v_badge_id::text, v_award, v_badge_name);
        END IF;
        INSERT INTO notifications (recipient_id, type, title, body, link)
        VALUES (v_user_id, 'badge_awarded', 'New badge: ' || v_badge_name, 'Gave 15 kudos', '/recognition');
      END IF;
    END LOOP;
  END IF;

  -- Wordsmith: users with 5+ wordle wins
  SELECT id, points_award, name INTO v_badge_id, v_award, v_badge_name
  FROM badges WHERE code = 'wordsmith' AND is_active = true;

  IF v_badge_id IS NOT NULL THEN
    FOR v_user_id IN
      SELECT user_id FROM points_events WHERE event_kind = 'wordle_win' GROUP BY user_id HAVING count(*) >= 5
    LOOP
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = v_user_id AND badge_id = v_badge_id) THEN
        INSERT INTO user_badges (user_id, badge_id) VALUES (v_user_id, v_badge_id);
        IF v_award > 0 THEN
          INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
          VALUES (v_user_id, 'badge_awarded', 'badge', v_badge_id::text, v_award, v_badge_name);
        END IF;
        INSERT INTO notifications (recipient_id, type, title, body, link)
        VALUES (v_user_id, 'badge_awarded', 'New badge: ' || v_badge_name, 'Won 5 Wordle puzzles', '/recognition');
      END IF;
    END LOOP;
  END IF;
END $$;
