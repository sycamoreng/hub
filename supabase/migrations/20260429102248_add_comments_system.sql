/*
  # Comments system

  1. New Tables
    - `comments`
      - `id` (uuid, primary key)
      - `target_type` (text, constrained to 'post' | 'announcement')
      - `target_id` (uuid)
      - `user_id` (uuid, references auth.users)
      - `parent_id` (uuid, nullable self-reference for one-level replies)
      - `content` (text, max 2000 chars enforced by check constraint)
      - `is_edited` (bool, default false)
      - `created_at` / `updated_at` (timestamptz)
    - `comment_mentions`
      - `comment_id` (uuid) + `user_id` (uuid) + `staff_id` (uuid) unique per combo
      - Populated by trigger from @mentions in comment content.

  2. Security
    - RLS enabled. Any authenticated user can read comments and mention rows.
    - Authors can insert their own comments, update/delete their own; admins can delete any.
    - Mention rows are read-only to users; inserted by trigger with SECURITY DEFINER.

  3. Triggers
    - `tg_parse_comment_mentions`: extracts @[Name](uuid) refs, writes `comment_mentions`, fires
      notifications (same pattern as post_mentions), and queues email via queue_mention_email.
    - `tg_notify_comment_author`: adds an in-app notification to the post/announcement author
      when someone comments (never self-notify).
    - `tg_set_comment_updated_at`: maintains updated_at and is_edited on UPDATE.

  4. Notes
    - `target_type` is validated by a CHECK constraint instead of an enum to keep it
      consistent with `reactions` which uses the same text approach.
*/

CREATE TABLE IF NOT EXISTS comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type text NOT NULL CHECK (target_type IN ('post', 'announcement')),
  target_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  parent_id uuid REFERENCES comments(id) ON DELETE CASCADE,
  content text NOT NULL CHECK (char_length(content) > 0 AND char_length(content) <= 2000),
  is_edited boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS comments_target_idx ON comments(target_type, target_id, created_at);
CREATE INDEX IF NOT EXISTS comments_user_idx ON comments(user_id);

ALTER TABLE comments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='comments' AND policyname='Authenticated users can read comments') THEN
    CREATE POLICY "Authenticated users can read comments" ON comments FOR SELECT TO authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='comments' AND policyname='Users insert own comments') THEN
    CREATE POLICY "Users insert own comments" ON comments FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='comments' AND policyname='Users update own comments') THEN
    CREATE POLICY "Users update own comments" ON comments FOR UPDATE TO authenticated
      USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='comments' AND policyname='Users delete own or admins delete any') THEN
    CREATE POLICY "Users delete own or admins delete any" ON comments FOR DELETE TO authenticated
      USING (
        auth.uid() = user_id
        OR EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email'))
      );
  END IF;
END $$;

-- comment_mentions
CREATE TABLE IF NOT EXISTS comment_mentions (
  comment_id uuid NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  staff_id uuid REFERENCES staff_members(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (comment_id, user_id)
);

CREATE INDEX IF NOT EXISTS comment_mentions_user_idx ON comment_mentions(user_id);

ALTER TABLE comment_mentions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='comment_mentions' AND policyname='Authenticated users can read comment mentions') THEN
    CREATE POLICY "Authenticated users can read comment mentions" ON comment_mentions FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- Keep updated_at fresh and mark is_edited
CREATE OR REPLACE FUNCTION public.tg_set_comment_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.content IS DISTINCT FROM OLD.content THEN
    NEW.is_edited := true;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_comment_updated_at ON comments;
CREATE TRIGGER set_comment_updated_at
BEFORE UPDATE ON comments
FOR EACH ROW EXECUTE FUNCTION public.tg_set_comment_updated_at();

-- Parse @[Name](uuid) mentions, populate comment_mentions + notifications + email queue
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
  v_target_label text;
  v_link text;
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

    INSERT INTO notifications (user_id, type, title, body, link_path, metadata)
    VALUES (
      v_user_id, 'mention',
      v_mentioner || ' mentioned you in a comment',
      LEFT(NEW.content, 220),
      '/feed',
      jsonb_build_object('comment_id', NEW.id, 'target_type', NEW.target_type, 'target_id', NEW.target_id)
    );

    PERFORM public.queue_mention_email(
      v_user_id, v_mentioner, LEFT(NEW.content, 220), '/feed',
      jsonb_build_object('comment_id', NEW.id, 'target_type', NEW.target_type, 'target_id', NEW.target_id)
    );
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS parse_comment_mentions ON comments;
CREATE TRIGGER parse_comment_mentions
AFTER INSERT OR UPDATE OF content ON comments
FOR EACH ROW EXECUTE FUNCTION public.tg_parse_comment_mentions();

-- Notify the author of the post/announcement (not self)
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

  INSERT INTO notifications (user_id, type, title, body, link_path, metadata)
  VALUES (
    v_author_id, 'comment', v_title, LEFT(NEW.content, 220),
    '/feed', jsonb_build_object('comment_id', NEW.id, 'target_type', NEW.target_type, 'target_id', NEW.target_id)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_comment_author ON comments;
CREATE TRIGGER notify_comment_author
AFTER INSERT ON comments
FOR EACH ROW EXECUTE FUNCTION public.tg_notify_comment_author();
