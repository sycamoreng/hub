/*
  # Performance Phase 4 - Recognitions, PIPs, review notifications

  1. New tables
    - `performance_recognitions`
      Captures exceptional performance (commendations, spot awards, promotions).
      Linked to subject staff and optionally a cycle or objective.
    - `performance_improvement_plans`
      Core PIP record for a subject + cycle with owner, goals, status, timeline.
    - `performance_improvement_checkins`
      Progress check-ins under a PIP.
  2. Notifications
    - Triggers on performance_reviews insert (invited) and update (submitted) notify the
      reviewer and subject respectively.
    - Trigger on performance_improvement_plans insert notifies the subject.
  3. Security
    - RLS on all new tables. Admins with performance.manage gain write access; subjects and
      their managers get read access. PIP checkins follow the parent PIP.
*/

CREATE TABLE IF NOT EXISTS public.performance_recognitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_staff_id uuid NOT NULL REFERENCES public.staff_members(id) ON DELETE CASCADE,
  cycle_id uuid REFERENCES public.performance_cycles(id) ON DELETE SET NULL,
  objective_id uuid REFERENCES public.performance_objectives(id) ON DELETE SET NULL,
  kind text NOT NULL DEFAULT 'commendation',
  title text NOT NULL DEFAULT '',
  summary text NOT NULL DEFAULT '',
  impact text NOT NULL DEFAULT '',
  points integer NOT NULL DEFAULT 0,
  awarded_at date NOT NULL DEFAULT CURRENT_DATE,
  awarded_by uuid REFERENCES public.staff_members(id) ON DELETE SET NULL,
  visible_to_staff boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT performance_recognitions_kind_check CHECK (kind IN ('commendation','spot_award','promotion','bonus','milestone'))
);

CREATE INDEX IF NOT EXISTS performance_recognitions_subject_idx ON public.performance_recognitions(subject_staff_id);
CREATE INDEX IF NOT EXISTS performance_recognitions_cycle_idx ON public.performance_recognitions(cycle_id);

ALTER TABLE public.performance_recognitions ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_recognitions' AND policyname='Subject can read recognition') THEN
    CREATE POLICY "Subject can read recognition"
      ON public.performance_recognitions FOR SELECT TO authenticated
      USING (
        visible_to_staff AND EXISTS (
          SELECT 1 FROM public.staff_members sm
          WHERE sm.id = subject_staff_id AND sm.auth_user_id = auth.uid()
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_recognitions' AND policyname='Manager can read recognition') THEN
    CREATE POLICY "Manager can read recognition"
      ON public.performance_recognitions FOR SELECT TO authenticated
      USING (private.is_manager_of(subject_staff_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_recognitions' AND policyname='Admin manages recognitions') THEN
    CREATE POLICY "Admin manages recognitions"
      ON public.performance_recognitions FOR SELECT TO authenticated
      USING (private.admin_can('performance','read'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_recognitions' AND policyname='Admin inserts recognitions') THEN
    CREATE POLICY "Admin inserts recognitions"
      ON public.performance_recognitions FOR INSERT TO authenticated
      WITH CHECK (private.admin_can('performance','manage'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_recognitions' AND policyname='Admin updates recognitions') THEN
    CREATE POLICY "Admin updates recognitions"
      ON public.performance_recognitions FOR UPDATE TO authenticated
      USING (private.admin_can('performance','manage'))
      WITH CHECK (private.admin_can('performance','manage'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_recognitions' AND policyname='Admin deletes recognitions') THEN
    CREATE POLICY "Admin deletes recognitions"
      ON public.performance_recognitions FOR DELETE TO authenticated
      USING (private.admin_can('performance','manage'));
  END IF;
END $$;

-- PIPs -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.performance_improvement_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_staff_id uuid NOT NULL REFERENCES public.staff_members(id) ON DELETE CASCADE,
  cycle_id uuid REFERENCES public.performance_cycles(id) ON DELETE SET NULL,
  owner_staff_id uuid REFERENCES public.staff_members(id) ON DELETE SET NULL,
  title text NOT NULL DEFAULT '',
  reason text NOT NULL DEFAULT '',
  expected_outcomes text NOT NULL DEFAULT '',
  support_plan text NOT NULL DEFAULT '',
  consequences text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'draft',
  start_date date,
  end_date date,
  review_frequency_days integer NOT NULL DEFAULT 14,
  closed_outcome text NOT NULL DEFAULT '',
  closed_summary text NOT NULL DEFAULT '',
  closed_at timestamptz,
  closed_by uuid REFERENCES public.staff_members(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pip_status_check CHECK (status IN ('draft','active','on_track','at_risk','off_track','succeeded','failed','cancelled')),
  CONSTRAINT pip_outcome_check CHECK (closed_outcome IN ('', 'succeeded', 'extended', 'failed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS pip_subject_idx ON public.performance_improvement_plans(subject_staff_id);
CREATE INDEX IF NOT EXISTS pip_status_idx ON public.performance_improvement_plans(status);

ALTER TABLE public.performance_improvement_plans ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_plans' AND policyname='Subject reads own PIP') THEN
    CREATE POLICY "Subject reads own PIP"
      ON public.performance_improvement_plans FOR SELECT TO authenticated
      USING (
        status <> 'draft' AND EXISTS (
          SELECT 1 FROM public.staff_members sm
          WHERE sm.id = subject_staff_id AND sm.auth_user_id = auth.uid()
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_plans' AND policyname='Manager reads PIP') THEN
    CREATE POLICY "Manager reads PIP"
      ON public.performance_improvement_plans FOR SELECT TO authenticated
      USING (private.is_manager_of(subject_staff_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_plans' AND policyname='Admin reads PIP') THEN
    CREATE POLICY "Admin reads PIP"
      ON public.performance_improvement_plans FOR SELECT TO authenticated
      USING (private.admin_can('performance','read'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_plans' AND policyname='Admin inserts PIP') THEN
    CREATE POLICY "Admin inserts PIP"
      ON public.performance_improvement_plans FOR INSERT TO authenticated
      WITH CHECK (private.admin_can('performance','manage'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_plans' AND policyname='Admin updates PIP') THEN
    CREATE POLICY "Admin updates PIP"
      ON public.performance_improvement_plans FOR UPDATE TO authenticated
      USING (private.admin_can('performance','manage'))
      WITH CHECK (private.admin_can('performance','manage'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_plans' AND policyname='Admin deletes PIP') THEN
    CREATE POLICY "Admin deletes PIP"
      ON public.performance_improvement_plans FOR DELETE TO authenticated
      USING (private.admin_can('performance','manage'));
  END IF;
END $$;

-- PIP check-ins ----------------------------------------------------
CREATE TABLE IF NOT EXISTS public.performance_improvement_checkins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pip_id uuid NOT NULL REFERENCES public.performance_improvement_plans(id) ON DELETE CASCADE,
  checkin_date date NOT NULL DEFAULT CURRENT_DATE,
  status text NOT NULL DEFAULT 'on_track',
  manager_notes text NOT NULL DEFAULT '',
  staff_response text NOT NULL DEFAULT '',
  evidence text NOT NULL DEFAULT '',
  author_staff_id uuid REFERENCES public.staff_members(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pip_checkin_status_check CHECK (status IN ('on_track','at_risk','off_track'))
);

CREATE INDEX IF NOT EXISTS pip_checkin_pip_idx ON public.performance_improvement_checkins(pip_id, checkin_date DESC);

ALTER TABLE public.performance_improvement_checkins ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_checkins' AND policyname='Read checkins via parent') THEN
    CREATE POLICY "Read checkins via parent"
      ON public.performance_improvement_checkins FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.performance_improvement_plans p
          WHERE p.id = pip_id
          AND (
            private.admin_can('performance','read')
            OR private.is_manager_of(p.subject_staff_id)
            OR (p.status <> 'draft' AND EXISTS (
              SELECT 1 FROM public.staff_members sm
              WHERE sm.id = p.subject_staff_id AND sm.auth_user_id = auth.uid()
            ))
          )
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_checkins' AND policyname='Staff respond to own checkin') THEN
    CREATE POLICY "Staff respond to own checkin"
      ON public.performance_improvement_checkins FOR UPDATE TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.performance_improvement_plans p
          JOIN public.staff_members sm ON sm.id = p.subject_staff_id
          WHERE p.id = pip_id AND sm.auth_user_id = auth.uid()
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.performance_improvement_plans p
          JOIN public.staff_members sm ON sm.id = p.subject_staff_id
          WHERE p.id = pip_id AND sm.auth_user_id = auth.uid()
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_checkins' AND policyname='Admin inserts checkin') THEN
    CREATE POLICY "Admin inserts checkin"
      ON public.performance_improvement_checkins FOR INSERT TO authenticated
      WITH CHECK (private.admin_can('performance','manage'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_checkins' AND policyname='Admin updates checkin') THEN
    CREATE POLICY "Admin updates checkin"
      ON public.performance_improvement_checkins FOR UPDATE TO authenticated
      USING (private.admin_can('performance','manage'))
      WITH CHECK (private.admin_can('performance','manage'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='performance_improvement_checkins' AND policyname='Admin deletes checkin') THEN
    CREATE POLICY "Admin deletes checkin"
      ON public.performance_improvement_checkins FOR DELETE TO authenticated
      USING (private.admin_can('performance','manage'));
  END IF;
END $$;

-- Notification triggers -------------------------------------------

CREATE OR REPLACE FUNCTION public.notify_on_review_invitation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  reviewer_user uuid;
  subject_name text;
  cycle_name text;
BEGIN
  IF NEW.status <> 'invited' OR NEW.reviewer_type = 'self' THEN
    -- still create a self-note for self reviews
    NULL;
  END IF;
  SELECT sm.auth_user_id INTO reviewer_user FROM public.staff_members sm WHERE sm.id = NEW.reviewer_staff_id;
  SELECT sm.full_name INTO subject_name FROM public.staff_members sm WHERE sm.id = NEW.subject_staff_id;
  SELECT c.name INTO cycle_name FROM public.performance_cycles c WHERE c.id = NEW.cycle_id;
  IF reviewer_user IS NULL THEN RETURN NEW; END IF;
  INSERT INTO public.notifications (recipient_id, actor_id, type, title, body, link)
  VALUES (
    reviewer_user,
    NULL,
    'performance_review_invited',
    CASE WHEN NEW.reviewer_type = 'self' THEN 'Self-evaluation ready' ELSE 'Review invitation: ' || COALESCE(subject_name, 'a colleague') END,
    'Cycle: ' || COALESCE(cycle_name, '') ||
      CASE WHEN NEW.due_at IS NOT NULL THEN ' - due ' || to_char(NEW.due_at, 'DD Mon YYYY') ELSE '' END,
    '/performance/review/' || NEW.id::text
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_review_invitation ON public.performance_reviews;
CREATE TRIGGER trg_notify_review_invitation
  AFTER INSERT ON public.performance_reviews
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_review_invitation();

CREATE OR REPLACE FUNCTION public.notify_on_review_submitted()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  subject_user uuid;
  cycle_name text;
  reviewer_display text;
BEGIN
  IF NEW.status <> 'submitted' OR COALESCE(OLD.status, '') = 'submitted' THEN
    RETURN NEW;
  END IF;
  IF NEW.reviewer_type = 'self' THEN
    RETURN NEW;
  END IF;
  SELECT sm.auth_user_id INTO subject_user FROM public.staff_members sm WHERE sm.id = NEW.subject_staff_id;
  SELECT c.name INTO cycle_name FROM public.performance_cycles c WHERE c.id = NEW.cycle_id;
  IF subject_user IS NULL THEN RETURN NEW; END IF;
  IF NEW.anonymous THEN
    reviewer_display := 'an anonymous reviewer';
  ELSE
    SELECT sm.full_name INTO reviewer_display FROM public.staff_members sm WHERE sm.id = NEW.reviewer_staff_id;
  END IF;
  INSERT INTO public.notifications (recipient_id, actor_id, type, title, body, link)
  VALUES (
    subject_user,
    NULL,
    'performance_review_submitted',
    'New feedback received',
    COALESCE(reviewer_display, 'Someone') || ' submitted feedback in ' || COALESCE(cycle_name, 'your performance cycle'),
    '/performance/review/' || NEW.id::text
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_review_submitted ON public.performance_reviews;
CREATE TRIGGER trg_notify_review_submitted
  AFTER UPDATE ON public.performance_reviews
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_review_submitted();

CREATE OR REPLACE FUNCTION public.notify_on_pip_activation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  subject_user uuid;
BEGIN
  IF NEW.status = 'draft' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status <> 'draft' THEN RETURN NEW; END IF;
  SELECT sm.auth_user_id INTO subject_user FROM public.staff_members sm WHERE sm.id = NEW.subject_staff_id;
  IF subject_user IS NULL THEN RETURN NEW; END IF;
  INSERT INTO public.notifications (recipient_id, actor_id, type, title, body, link)
  VALUES (
    subject_user,
    NULL,
    'performance_pip_started',
    'Performance improvement plan started',
    COALESCE(NEW.title, 'Your manager has set up a new improvement plan with clear goals and support.'),
    '/performance'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_pip_insert ON public.performance_improvement_plans;
CREATE TRIGGER trg_notify_pip_insert
  AFTER INSERT ON public.performance_improvement_plans
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_pip_activation();

DROP TRIGGER IF EXISTS trg_notify_pip_update ON public.performance_improvement_plans;
CREATE TRIGGER trg_notify_pip_update
  AFTER UPDATE OF status ON public.performance_improvement_plans
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_pip_activation();
