/*
  # Fix comment triggers to match notifications schema

  The previous migration referenced `user_id`, `link_path`, and `metadata` on
  `notifications`. The actual columns are `recipient_id`, `actor_id`, `type`,
  `title`, `body`, `link`. Rewrite the two trigger functions to use them.
*/

CREATE OR REPLACE FUNCTION public.tg_parse_comment_mentions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match record;
  v_user_id uuid;
  v_staff_id uuid;
  v_mentioner text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    DELETE FROM comment_mentions WHERE comment_id = NEW.id;
  END IF;

  SELECT COALESCE(s.full_name, 'A colleague') INTO v_mentioner
    FROM staff_members s WHERE s.auth_user_id = NEW.user_id LIMIT 1;
  IF v_mentioner IS NULL THEN v_mentioner := 'A colleague'; END IF;

  FOR v_match IN
    SELECT DISTINCT (regexp_matches(NEW.content, '@\[[^\]]+\]\(([0-9a-fA-F-]{36})\)', 'g'))[1] AS uid
  LOOP
    BEGIN
      v_user_id := v_match.uid::uuid;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE;
    END;
    IF v_user_id = NEW.user_id THEN CONTINUE; END IF;

    SELECT id INTO v_staff_id FROM staff_members WHERE auth_user_id = v_user_id LIMIT 1;

    INSERT INTO comment_mentions (comment_id, user_id, staff_id)
    VALUES (NEW.id, v_user_id, v_staff_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO notifications (recipient_id, actor_id, type, title, body, link)
    VALUES (
      v_user_id, NEW.user_id, 'mention',
      v_mentioner || ' mentioned you in a comment',
      LEFT(NEW.content, 220),
      '/feed'
    );

    PERFORM public.queue_mention_email(
      v_user_id, v_mentioner, LEFT(NEW.content, 220), '/feed',
      jsonb_build_object('comment_id', NEW.id, 'target_type', NEW.target_type, 'target_id', NEW.target_id)
    );
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.tg_notify_comment_author()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_author_id uuid;
  v_commenter text;
  v_title text;
BEGIN
  IF NEW.target_type = 'post' THEN
    SELECT author_id INTO v_author_id FROM posts WHERE id = NEW.target_id;
  END IF;

  IF v_author_id IS NULL OR v_author_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(s.full_name, 'A colleague') INTO v_commenter
    FROM staff_members s WHERE s.auth_user_id = NEW.user_id LIMIT 1;
  IF v_commenter IS NULL THEN v_commenter := 'A colleague'; END IF;

  v_title := v_commenter || ' commented on your post';

  INSERT INTO notifications (recipient_id, actor_id, type, title, body, link)
  VALUES (v_author_id, NEW.user_id, 'comment', v_title, LEFT(NEW.content, 220), '/feed');

  RETURN NEW;
END;
$$;
