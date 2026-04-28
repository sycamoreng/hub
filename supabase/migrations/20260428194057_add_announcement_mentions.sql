/*
  # Add @mention support for announcements

  1. New Tables
    - `announcement_mentions`
      - `announcement_id` (uuid, FK announcements ON DELETE CASCADE)
      - `user_id` (uuid, FK auth.users ON DELETE CASCADE)
      - `staff_id` (uuid, FK staff_members ON DELETE SET NULL)
      - `created_at` (timestamptz, default now())
      - Composite PK on (announcement_id, user_id)

  2. Security (RLS)
    - SELECT: any authenticated user can read mentions to render the feed.
    - INSERT/UPDATE/DELETE: not exposed to clients - mentions are populated by
      a SECURITY DEFINER trigger that scans the announcement content for
      `@<full_name>` matches against active staff members.

  3. Triggers
    - `announcement_parse_mentions` (after insert OR update of content):
      re-parses mentions from the announcement content on each change.
    - `announcement_mention_notify` (after insert on announcement_mentions):
      drops a notification of type `mention` for the recipient pointing at /feed.

  4. Notes
    - On UPDATE we delete and re-insert mention rows so removed names disappear
      and new ones notify. A simple delete+insert keeps the trigger logic compact.
*/

CREATE TABLE IF NOT EXISTS public.announcement_mentions (
  announcement_id uuid NOT NULL REFERENCES public.announcements(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  staff_id uuid REFERENCES public.staff_members(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (announcement_id, user_id)
);

CREATE INDEX IF NOT EXISTS announcement_mentions_user_idx ON public.announcement_mentions (user_id);

ALTER TABLE public.announcement_mentions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='announcement_mentions'
    AND policyname='Authenticated users can read announcement mentions'
  ) THEN
    CREATE POLICY "Authenticated users can read announcement mentions"
      ON public.announcement_mentions FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.tg_parse_announcement_mentions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    DELETE FROM public.announcement_mentions WHERE announcement_id = NEW.id;
  END IF;

  IF NEW.content IS NULL OR length(NEW.content) = 0 THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.announcement_mentions (announcement_id, user_id, staff_id)
  SELECT NEW.id, s.auth_user_id, s.id
  FROM public.staff_members s
  WHERE s.is_active = true
    AND s.auth_user_id IS NOT NULL
    AND length(s.full_name) > 1
    AND position('@' || s.full_name IN NEW.content) > 0
  ON CONFLICT (announcement_id, user_id) DO NOTHING;

  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.tg_notify_announcement_mention()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  ann_title text;
  preview text;
BEGIN
  SELECT title, left(content, 140) INTO ann_title, preview
  FROM public.announcements WHERE id = NEW.announcement_id LIMIT 1;

  INSERT INTO public.notifications (recipient_id, actor_id, type, title, body, link)
  VALUES (
    NEW.user_id,
    NULL,
    'mention',
    'You were mentioned in an announcement' || COALESCE(': ' || ann_title, ''),
    preview,
    '/feed'
  );

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS announcement_parse_mentions ON public.announcements;
CREATE TRIGGER announcement_parse_mentions
  AFTER INSERT OR UPDATE OF content ON public.announcements
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_parse_announcement_mentions();

DROP TRIGGER IF EXISTS announcement_mention_notify ON public.announcement_mentions;
CREATE TRIGGER announcement_mention_notify
  AFTER INSERT ON public.announcement_mentions
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_notify_announcement_mention();
