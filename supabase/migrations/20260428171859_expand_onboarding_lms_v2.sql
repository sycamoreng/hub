/*
  # Expand onboarding into a lightweight LMS (corrected helper)

  Same intent as the previous attempt; uses `private.admin_can` (the actual helper in
  this project) for write policies on `onboarding_resources`.
*/

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='onboarding_steps' AND column_name='content_type') THEN
    ALTER TABLE public.onboarding_steps ADD COLUMN content_type text NOT NULL DEFAULT 'task';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='onboarding_steps' AND column_name='body') THEN
    ALTER TABLE public.onboarding_steps ADD COLUMN body text NOT NULL DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='onboarding_steps' AND column_name='video_url') THEN
    ALTER TABLE public.onboarding_steps ADD COLUMN video_url text NOT NULL DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='onboarding_steps' AND column_name='cover_image_url') THEN
    ALTER TABLE public.onboarding_steps ADD COLUMN cover_image_url text NOT NULL DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='onboarding_steps' AND column_name='estimated_minutes') THEN
    ALTER TABLE public.onboarding_steps ADD COLUMN estimated_minutes integer NOT NULL DEFAULT 0;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.onboarding_resources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id uuid NOT NULL REFERENCES public.onboarding_steps(id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'link',
  title text NOT NULL,
  description text NOT NULL DEFAULT '',
  url text NOT NULL DEFAULT '',
  body text NOT NULL DEFAULT '',
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS onboarding_resources_step_idx ON public.onboarding_resources (step_id);

ALTER TABLE public.onboarding_resources ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='onboarding_resources' AND policyname='Authenticated users can read resources') THEN
    CREATE POLICY "Authenticated users can read resources"
      ON public.onboarding_resources FOR SELECT
      TO authenticated
      USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='onboarding_resources' AND policyname='Onboarding admins can insert resources') THEN
    CREATE POLICY "Onboarding admins can insert resources"
      ON public.onboarding_resources FOR INSERT
      TO authenticated
      WITH CHECK (private.admin_can('onboarding', 'create'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='onboarding_resources' AND policyname='Onboarding admins can update resources') THEN
    CREATE POLICY "Onboarding admins can update resources"
      ON public.onboarding_resources FOR UPDATE
      TO authenticated
      USING (private.admin_can('onboarding', 'update'))
      WITH CHECK (private.admin_can('onboarding', 'update'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='onboarding_resources' AND policyname='Onboarding admins can delete resources') THEN
    CREATE POLICY "Onboarding admins can delete resources"
      ON public.onboarding_resources FOR DELETE
      TO authenticated
      USING (private.admin_can('onboarding', 'delete'));
  END IF;
END $$;
