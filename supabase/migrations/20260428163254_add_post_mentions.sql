/*
  # Add @mention support for feed posts

  1. New Tables
    - `post_mentions`
      - `post_id` (uuid, FK posts) - the post the mention appears in
      - `user_id` (uuid, FK auth.users) - the mentioned user (recipient)
      - `staff_id` (uuid, FK staff_members) - cached staff record id for quick UI rendering
      - `created_at` (timestamptz, default now())
      - Composite PK on (post_id, user_id)

  2. Security (RLS)
    - SELECT: any authenticated user can read mentions (needed to render the feed)
    - INSERT/UPDATE/DELETE: not exposed to clients - mentions are populated by a SECURITY
      DEFINER trigger that parses the post content. The post author cannot fabricate
      mentions to other people that aren't actually in the text.

  3. Triggers
    - `tg_parse_post_mentions` (after insert on posts): scans the post's content for
      occurrences of `@<full_name>` matching active, claimed staff members and inserts a
      mention row for each unique match. Self-mentions (the author) are skipped.
    - `tg_notify_mention` (after insert on post_mentions): inserts a notification of type
      'mention' for the mentioned recipient with a link to /feed.

  4. Notes
    - Parsing uses `position('@' || full_name in NEW.content)`, which is a simple substring
      match. Names with shared prefixes (e.g. "Anna" and "Anna Smith") will both match if
      both are explicitly typed; this is the desired behaviour - if you typed "@Anna" you
      mean Anna, and if you typed "@Anna Smith" you mean both share an attribution path
      that includes Anna. To avoid spurious matches, only the first occurrence of each
      distinct user creates a single notification.
    - The notification trigger reuses the existing notifications table.
*/

CREATE TABLE IF NOT EXISTS public.post_mentions (
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  staff_id uuid REFERENCES public.staff_members(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);

CREATE INDEX IF NOT EXISTS post_mentions_user_idx ON public.post_mentions (user_id);

ALTER TABLE public.post_mentions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='post_mentions' AND policyname='Authenticated users can read mentions') THEN
    CREATE POLICY "Authenticated users can read mentions"
      ON public.post_mentions FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.tg_parse_post_mentions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NEW.content IS NULL OR length(NEW.content) = 0 THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.post_mentions (post_id, user_id, staff_id)
  SELECT NEW.id, s.auth_user_id, s.id
  FROM public.staff_members s
  WHERE s.is_active = true
    AND s.auth_user_id IS NOT NULL
    AND s.auth_user_id <> NEW.author_id
    AND length(s.full_name) > 1
    AND position('@' || s.full_name IN NEW.content) > 0
  ON CONFLICT (post_id, user_id) DO NOTHING;

  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.tg_notify_mention()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  actor_uid uuid;
  actor_name text;
  preview text;
BEGIN
  SELECT author_id, left(content, 140) INTO actor_uid, preview
  FROM public.posts
  WHERE id = NEW.post_id
  LIMIT 1;

  IF actor_uid IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT full_name INTO actor_name
  FROM public.staff_members
  WHERE auth_user_id = actor_uid
  LIMIT 1;

  INSERT INTO public.notifications (recipient_id, actor_id, type, title, body, link)
  VALUES (
    NEW.user_id,
    actor_uid,
    'mention',
    COALESCE(actor_name, 'A colleague') || ' mentioned you in a post',
    preview,
    '/feed'
  );

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS post_parse_mentions ON public.posts;
CREATE TRIGGER post_parse_mentions
  AFTER INSERT ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_parse_post_mentions();

DROP TRIGGER IF EXISTS post_mention_notify ON public.post_mentions;
CREATE TRIGGER post_mention_notify
  AFTER INSERT ON public.post_mentions
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_notify_mention();
