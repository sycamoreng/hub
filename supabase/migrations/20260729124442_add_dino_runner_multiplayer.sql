/*
# Add Sycamore Run (Dino) multiplayer

1. New Tables
   - `dino_matches` — multiplayer rooms for the dino runner game
     - `id` (uuid, PK)
     - `host_user_id` (uuid, FK auth.users)
     - `code` (text, unique 6-char)
     - `status` (text: pending/active/finished/cancelled)
     - `max_players` (int, default 30)
     - `time_limit_seconds` (int, nullable — max game duration)
     - `deadline_at` (timestamptz, nullable)
     - `started_at` / `finished_at` (timestamptz)
   - `dino_match_participants` — players in each room
     - `id` (uuid, PK)
     - `match_id` (uuid, FK dino_matches)
     - `user_id` (uuid, FK auth.users)
     - `status` (text: joined/playing/crashed/left)
     - `score` (int, default 0)
     - `duration_ms` (int, default 0)
     - `points_awarded` (int, default 0)
     - `joined_at` / `finished_at` (timestamptz)

2. New Functions (SECURITY DEFINER)
   - `dino_match_create(p_time_limit int)` — create room with optional time limit
   - `dino_match_join(p_code text)` — join a room by code
   - `dino_match_leave(p_match_id uuid)` — leave a pending room
   - `dino_match_start(p_match_id uuid)` — host starts the race
   - `dino_match_crash(p_match_id uuid, p_score int, p_duration_ms int)` — player crashed, lock in score
   - `dino_match_board(p_match_id uuid)` — get room state

3. Scoring
   - 1st place: 15 pts, 2nd: 10 pts, 3rd: 5 pts, everyone else who played: 2 pts

4. Security
   - RLS enabled, SELECT only for authenticated.
   - All writes via SECURITY DEFINER RPCs.
*/

-- === dino_matches ===
CREATE TABLE IF NOT EXISTS dino_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code text NOT NULL UNIQUE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','finished','cancelled')),
  max_players int NOT NULL DEFAULT 30,
  time_limit_seconds int,
  deadline_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE dino_matches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "select_dino_matches" ON dino_matches;
CREATE POLICY "select_dino_matches" ON dino_matches FOR SELECT TO authenticated USING (true);

-- === dino_match_participants ===
CREATE TABLE IF NOT EXISTS dino_match_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES dino_matches(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'joined' CHECK (status IN ('joined','playing','crashed','left')),
  score int NOT NULL DEFAULT 0,
  duration_ms int NOT NULL DEFAULT 0,
  points_awarded int NOT NULL DEFAULT 0,
  joined_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE(match_id, user_id)
);

ALTER TABLE dino_match_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "select_dino_match_participants" ON dino_match_participants;
CREATE POLICY "select_dino_match_participants" ON dino_match_participants FOR SELECT TO authenticated USING (true);

-- === RPC: create ===
CREATE OR REPLACE FUNCTION dino_match_create(p_time_limit int DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_code text;
  v_match dino_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  IF p_time_limit IS NOT NULL AND p_time_limit NOT IN (30, 60, 90, 120, 180) THEN
    p_time_limit := 60;
  END IF;

  LOOP
    v_code := upper(substr(md5(random()::text), 1, 6));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM dino_matches WHERE code = v_code);
  END LOOP;

  INSERT INTO dino_matches (host_user_id, code, time_limit_seconds)
  VALUES (v_uid, v_code, p_time_limit)
  RETURNING * INTO v_match;

  RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status, 'time_limit_seconds', v_match.time_limit_seconds);
END;
$$;

-- === RPC: join ===
CREATE OR REPLACE FUNCTION dino_match_join(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match dino_matches;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM dino_matches WHERE code = upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

  IF EXISTS (SELECT 1 FROM dino_match_participants WHERE match_id = v_match.id AND user_id = v_uid) THEN
    UPDATE dino_match_participants SET status = 'joined' WHERE match_id = v_match.id AND user_id = v_uid AND status = 'left';
    RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status);
  END IF;

  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'room already started'; END IF;
  SELECT count(*) INTO v_count FROM dino_match_participants WHERE match_id = v_match.id AND status <> 'left';
  IF v_count >= v_match.max_players THEN RAISE EXCEPTION 'room is full'; END IF;

  INSERT INTO dino_match_participants (match_id, user_id) VALUES (v_match.id, v_uid);
  RETURN jsonb_build_object('id', v_match.id, 'code', v_match.code, 'status', v_match.status);
END;
$$;

-- === RPC: leave ===
CREATE OR REPLACE FUNCTION dino_match_leave(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match dino_matches;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM dino_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_match.status = 'pending' THEN
    UPDATE dino_match_participants SET status = 'left' WHERE match_id = p_match_id AND user_id = v_uid;
    IF v_match.host_user_id = v_uid THEN
      IF NOT EXISTS (SELECT 1 FROM dino_match_participants WHERE match_id = p_match_id AND status <> 'left') THEN
        UPDATE dino_matches SET status = 'cancelled' WHERE id = p_match_id;
      END IF;
    END IF;
  END IF;
END;
$$;

-- === RPC: start ===
CREATE OR REPLACE FUNCTION dino_match_start(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match dino_matches;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM dino_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.host_user_id <> v_uid THEN RAISE EXCEPTION 'only host can start'; END IF;
  IF v_match.status <> 'pending' THEN RAISE EXCEPTION 'already started'; END IF;

  DELETE FROM dino_match_participants WHERE match_id = p_match_id AND status = 'left';
  SELECT count(*) INTO v_count FROM dino_match_participants WHERE match_id = p_match_id;
  IF v_count < 1 THEN RAISE EXCEPTION 'need at least 1 player'; END IF;

  UPDATE dino_match_participants SET status = 'playing' WHERE match_id = p_match_id;
  UPDATE dino_matches SET
    status = 'active',
    started_at = now(),
    deadline_at = CASE WHEN time_limit_seconds IS NOT NULL THEN now() + (time_limit_seconds || ' seconds')::interval ELSE NULL END
  WHERE id = p_match_id RETURNING * INTO v_match;

  RETURN jsonb_build_object('id', v_match.id, 'status', v_match.status, 'deadline_at', v_match.deadline_at);
END;
$$;

-- === RPC: crash (player finished their run) ===
CREATE OR REPLACE FUNCTION dino_match_crash(p_match_id uuid, p_score int, p_duration_ms int)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match dino_matches;
  v_all_done boolean;
  v_rank int;
  v_points int := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM dino_matches WHERE id = p_match_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;
  IF v_match.status <> 'active' THEN RAISE EXCEPTION 'room not active'; END IF;

  UPDATE dino_match_participants SET
    status = 'crashed',
    score = GREATEST(0, p_score),
    duration_ms = GREATEST(0, p_duration_ms),
    finished_at = now()
  WHERE match_id = p_match_id AND user_id = v_uid AND status = 'playing';

  -- Check if all done
  SELECT NOT EXISTS (
    SELECT 1 FROM dino_match_participants WHERE match_id = p_match_id AND status = 'playing'
  ) INTO v_all_done;

  IF v_all_done THEN
    UPDATE dino_matches SET status = 'finished', finished_at = now() WHERE id = p_match_id;

    -- Award points by rank
    FOR v_rank IN 1..(SELECT count(*) FROM dino_match_participants WHERE match_id = p_match_id AND status = 'crashed') LOOP
      UPDATE dino_match_participants SET points_awarded = CASE
        WHEN v_rank = 1 THEN 15
        WHEN v_rank = 2 THEN 10
        WHEN v_rank = 3 THEN 5
        ELSE 2
      END
      WHERE id = (
        SELECT id FROM dino_match_participants
        WHERE match_id = p_match_id AND status = 'crashed'
        ORDER BY score DESC, duration_ms DESC
        LIMIT 1 OFFSET (v_rank - 1)
      );
    END LOOP;

    -- Insert points events for winners
    INSERT INTO points_events (user_id, event_kind, ref_type, ref_id, points, note)
    SELECT p.user_id, 'dino_multi', 'dino_match', v_match.id::text, p.points_awarded,
      CASE WHEN p.points_awarded = 15 THEN '1st place in Sycamore Run race'
           WHEN p.points_awarded = 10 THEN '2nd place in Sycamore Run race'
           WHEN p.points_awarded = 5 THEN '3rd place in Sycamore Run race'
           ELSE 'Participated in Sycamore Run race' END
    FROM dino_match_participants p
    WHERE p.match_id = p_match_id AND p.status = 'crashed' AND p.points_awarded > 0
    ON CONFLICT (user_id, event_kind, ref_type, ref_id) DO NOTHING;
  END IF;

  RETURN dino_match_board(p_match_id);
END;
$$;

-- === RPC: board ===
CREATE OR REPLACE FUNCTION dino_match_board(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_match dino_matches;
  v_players jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_match FROM dino_matches WHERE id = p_match_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'room not found'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) INTO v_players
  FROM (
    SELECT p.user_id, p.status, p.score, p.duration_ms, p.points_awarded,
           p.joined_at, p.finished_at,
           s.full_name, s.role
    FROM dino_match_participants p
    LEFT JOIN staff_members s ON s.auth_user_id = p.user_id
    WHERE p.match_id = p_match_id
    ORDER BY p.score DESC, p.duration_ms DESC, p.joined_at
  ) x;

  RETURN jsonb_build_object(
    'match', jsonb_build_object(
      'id', v_match.id,
      'code', v_match.code,
      'status', v_match.status,
      'max_players', v_match.max_players,
      'host_user_id', v_match.host_user_id,
      'time_limit_seconds', v_match.time_limit_seconds,
      'deadline_at', v_match.deadline_at,
      'started_at', v_match.started_at,
      'finished_at', v_match.finished_at
    ),
    'players', v_players
  );
END;
$$;

GRANT EXECUTE ON FUNCTION dino_match_create(int) TO authenticated;
GRANT EXECUTE ON FUNCTION dino_match_join(text) TO authenticated;
GRANT EXECUTE ON FUNCTION dino_match_leave(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION dino_match_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION dino_match_crash(uuid, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION dino_match_board(uuid) TO authenticated;
