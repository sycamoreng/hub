/*
  # Backfill and auto-award badges (corrected)

  Same as previous attempt; fixes column name for comments (user_id, not author_id).
*/

CREATE OR REPLACE FUNCTION private.compute_user_metric(p_user_id uuid, p_metric text)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v bigint := 0;
BEGIN
  IF p_metric = 'points_total' THEN
    SELECT COALESCE(SUM(points), 0) INTO v FROM public.points_events WHERE user_id = p_user_id;
  ELSIF p_metric = 'posts_count' THEN
    SELECT COUNT(*) INTO v FROM public.posts WHERE author_id = p_user_id;
  ELSIF p_metric = 'comments_count' THEN
    SELECT COUNT(*) INTO v FROM public.comments WHERE user_id = p_user_id;
  ELSIF p_metric = 'kudos_given_count' THEN
    SELECT COUNT(*) INTO v FROM public.kudos WHERE from_user_id = p_user_id;
  ELSIF p_metric = 'kudos_received_count' THEN
    SELECT COUNT(*) INTO v FROM public.kudos WHERE to_user_id = p_user_id;
  ELSIF p_metric = 'learning_count' THEN
    SELECT COUNT(*) INTO v FROM public.points_events WHERE user_id = p_user_id AND event_kind = 'onboarding_step_completed';
  ELSIF p_metric = 'spark_correct_count' THEN
    SELECT COUNT(*) INTO v FROM public.spark_responses WHERE user_id = p_user_id AND is_correct = true;
  END IF;
  RETURN COALESCE(v, 0);
END;
$$;

CREATE OR REPLACE FUNCTION private.recompute_user_badges(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  b RECORD;
  v bigint;
  awarded_count integer := 0;
  bonus integer;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN 0;
  END IF;

  FOR b IN
    SELECT id, name, description, metric, threshold, points_award
    FROM public.badges
    WHERE is_active = true
  LOOP
    IF EXISTS (SELECT 1 FROM public.user_badges WHERE user_id = p_user_id AND badge_id = b.id) THEN
      CONTINUE;
    END IF;

    v := private.compute_user_metric(p_user_id, b.metric);
    IF v >= COALESCE(b.threshold, 0) THEN
      BEGIN
        INSERT INTO public.user_badges (user_id, badge_id) VALUES (p_user_id, b.id);
      EXCEPTION WHEN unique_violation THEN
        CONTINUE;
      END;
      awarded_count := awarded_count + 1;

      bonus := COALESCE(b.points_award, 0);
      IF bonus > 0 THEN
        INSERT INTO public.points_events (user_id, event_kind, ref_type, ref_id, points, note)
        VALUES (p_user_id, 'badge_awarded', 'badge', b.id, bonus, b.name);
      END IF;

      BEGIN
        INSERT INTO public.notifications (recipient_id, type, title, body, link)
        VALUES (p_user_id, 'badge_awarded', 'New badge: ' || b.name, COALESCE(b.description, ''), '/recognition');
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
  END LOOP;

  RETURN awarded_count;
END;
$$;

REVOKE ALL ON FUNCTION private.recompute_user_badges(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.recompute_all_badges()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  u RECORD;
  total integer := 0;
BEGIN
  IF NOT private.is_super_admin() THEN
    RAISE EXCEPTION 'not authorised';
  END IF;

  FOR u IN SELECT id FROM auth.users LOOP
    total := total + private.recompute_user_badges(u.id);
  END LOOP;

  RETURN total;
END;
$$;

REVOKE ALL ON FUNCTION public.recompute_all_badges() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recompute_all_badges() TO authenticated;

CREATE OR REPLACE FUNCTION private.points_events_check_badges()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.event_kind = 'badge_awarded' THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS NOT NULL THEN
    PERFORM private.recompute_user_badges(NEW.user_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_points_events_check_badges ON public.points_events;
CREATE TRIGGER trg_points_events_check_badges
AFTER INSERT ON public.points_events
FOR EACH ROW
EXECUTE FUNCTION private.points_events_check_badges();

DO $$
DECLARE
  u RECORD;
BEGIN
  FOR u IN SELECT DISTINCT user_id AS id FROM public.points_events WHERE user_id IS NOT NULL LOOP
    PERFORM private.recompute_user_badges(u.id);
  END LOOP;
END $$;
