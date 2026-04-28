/*
  # Add in-app notifications

  1. New Tables
    - `notifications`
      - `id` (uuid, PK)
      - `recipient_id` (uuid, FK auth.users, the user who should see this notification)
      - `actor_id` (uuid, FK auth.users, the user who caused the event - nullable for system events)
      - `type` (text) - one of: 'post_new', 'announcement_new', 'reaction_received'
      - `title` (text) - short headline shown in the bell dropdown
      - `body` (text) - longer description
      - `link` (text) - in-app path to navigate to when clicked
      - `read_at` (timestamptz, nullable) - when the recipient marked it read
      - `created_at` (timestamptz, default now())

  2. Security
    - RLS enabled on `notifications`
    - SELECT: recipients can read their own notifications
    - UPDATE: recipients can mark their own as read (only `read_at` should change in practice)
    - DELETE: recipients can dismiss their own
    - INSERT: NOT exposed to clients - all inserts happen via SECURITY DEFINER triggers

  3. Triggers (all SECURITY DEFINER, fire after the source row is committed)
    - `on_post_published` - when a post is inserted with `is_published = true`, fan-out one
      notification to every claimed staff member except the author
    - `on_announcement_created` - when an announcement is inserted with `is_active = true`,
      fan-out one notification to every claimed staff member
    - `on_reaction_inserted` - when a reaction targeting a post is inserted, notify the
      post's author (skipped if author reacted to their own post)

  4. Realtime
    - The table is added to the `supabase_realtime` publication so the client can subscribe
      via Supabase Realtime and receive new notifications instantly.

  5. Notes
    - The fan-out queries are bounded by the number of claimed staff members; for the size of
      this org this is well under any practical concern. If the directory grows large, the
      broadcast functions could be moved to a queue/edge worker later.
*/

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  type text NOT NULL,
  title text NOT NULL DEFAULT '',
  body text NOT NULL DEFAULT '',
  link text NOT NULL DEFAULT '',
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notifications_recipient_created_idx
  ON public.notifications (recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_recipient_unread_idx
  ON public.notifications (recipient_id) WHERE read_at IS NULL;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='Recipients can read own notifications') THEN
    CREATE POLICY "Recipients can read own notifications"
      ON public.notifications FOR SELECT
      TO authenticated
      USING (auth.uid() = recipient_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='Recipients can update own notifications') THEN
    CREATE POLICY "Recipients can update own notifications"
      ON public.notifications FOR UPDATE
      TO authenticated
      USING (auth.uid() = recipient_id)
      WITH CHECK (auth.uid() = recipient_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='notifications' AND policyname='Recipients can delete own notifications') THEN
    CREATE POLICY "Recipients can delete own notifications"
      ON public.notifications FOR DELETE
      TO authenticated
      USING (auth.uid() = recipient_id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.tg_notify_post_published()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  author_name text;
  preview text;
BEGIN
  IF NOT NEW.is_published THEN
    RETURN NEW;
  END IF;

  SELECT full_name INTO author_name
  FROM public.staff_members
  WHERE auth_user_id = NEW.author_id
  LIMIT 1;

  preview := left(NEW.content, 140);

  INSERT INTO public.notifications (recipient_id, actor_id, type, title, body, link)
  SELECT DISTINCT s.auth_user_id,
                  NEW.author_id,
                  'post_new',
                  COALESCE(author_name, 'A colleague') || ' shared a new post',
                  preview,
                  '/feed'
  FROM public.staff_members s
  WHERE s.auth_user_id IS NOT NULL
    AND s.is_active = true
    AND s.auth_user_id <> NEW.author_id;

  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.tg_notify_announcement_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT NEW.is_active THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.notifications (recipient_id, actor_id, type, title, body, link)
  SELECT DISTINCT s.auth_user_id,
                  NULL,
                  'announcement_new',
                  'New announcement: ' || NEW.title,
                  left(NEW.content, 200),
                  '/'
  FROM public.staff_members s
  WHERE s.auth_user_id IS NOT NULL
    AND s.is_active = true;

  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.tg_notify_reaction_received()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  target_author uuid;
  actor_name text;
  preview text;
BEGIN
  IF NEW.target_type <> 'post' THEN
    RETURN NEW;
  END IF;

  SELECT author_id, left(content, 100) INTO target_author, preview
  FROM public.posts
  WHERE id = NEW.target_id
  LIMIT 1;

  IF target_author IS NULL OR target_author = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT full_name INTO actor_name
  FROM public.staff_members
  WHERE auth_user_id = NEW.user_id
  LIMIT 1;

  INSERT INTO public.notifications (recipient_id, actor_id, type, title, body, link)
  VALUES (
    target_author,
    NEW.user_id,
    'reaction_received',
    COALESCE(actor_name, 'Someone') || ' reacted ' || NEW.emoji || ' to your post',
    preview,
    '/feed'
  );

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS post_published_notify ON public.posts;
CREATE TRIGGER post_published_notify
  AFTER INSERT ON public.posts
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_notify_post_published();

DROP TRIGGER IF EXISTS announcement_created_notify ON public.announcements;
CREATE TRIGGER announcement_created_notify
  AFTER INSERT ON public.announcements
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_notify_announcement_created();

DROP TRIGGER IF EXISTS reaction_received_notify ON public.reactions;
CREATE TRIGGER reaction_received_notify
  AFTER INSERT ON public.reactions
  FOR EACH ROW
  EXECUTE FUNCTION public.tg_notify_reaction_received();

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'notifications'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications';
  END IF;
END $$;
