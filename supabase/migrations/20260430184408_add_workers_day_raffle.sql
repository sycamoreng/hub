/*
  # Workers' Day Raffle

  1. New Tables
    - `raffle_prizes`: catalog of prize types with quantities (editable before sealing).
      - `id` uuid PK, `name` text unique, `icon` text, `color` text,
        `quantity` int, `display_order` int.
    - `raffle_settings`: single-row settings table (id=1).
      - `status` text in ('draft','sealed','live','closed'),
        `sealed_at`, `live_at`, `closed_at`, `updated_at`, `blanks_count` int.
    - `raffle_allocations`: pre-seeded assignment of each staff member to a prize or blank.
      - `id` uuid PK, `staff_member_id` uuid unique (FK staff_members),
        `prize_id` uuid nullable (FK raffle_prizes), `is_blank` bool,
        `revealed_at` timestamptz, `created_at`.

  2. Seeded Reference Data
    - 10 prize rows with the quantities provided (Shopping Voucher 15, Solar Table Fan 10,
      Insulated Cups 16, Power Bank 12, Bluetooth Headphones 10, Smart Watch 7, Branded Mug 10,
      Cash 5K x35, Cash 10K x30, Cash 20K x15).
    - `raffle_settings` row with status='draft', blanks_count=19.

  3. Functions
    - `raffle_simulate()` (admin): returns a fresh shuffled preview without writing.
    - `raffle_seed()` (admin): one-shot shuffle that writes allocations and flips status to 'sealed'.
      Validates (sum(prize quantity) + blanks) == staff count.
    - `raffle_set_status(new_status)` (admin): transitions status forward (sealed->live, live->closed).
    - `raffle_reveal()` (authenticated staff): atomically reveals caller's allocation and returns
      the assigned prize or blank. Safe under concurrency; idempotent after first reveal.
    - `raffle_reset()` (super admin only): wipes allocations, resets status to draft. For safety net only.

  4. Security
    - RLS enabled on all new tables.
    - Authenticated users can SELECT raffle_prizes and raffle_settings.
    - Authenticated users can SELECT their own raffle_allocations row (by staff_members.auth_user_id).
    - Admins (is_email_admin()) can SELECT all allocations and UPDATE prize quantities / settings.
    - All writes to allocations go through SECURITY DEFINER RPCs (no direct INSERT/UPDATE/DELETE policies).

  5. Notes
    - Shuffle uses Postgres' order-by-random on both sides (staff list and prize pool),
      which is equivalent to a Fisher-Yates shuffle for our purposes.
    - `raffle_reveal()` uses an UPDATE ... WHERE revealed_at IS NULL RETURNING pattern so a
      second call returns the previously-assigned allocation without changing anything.
*/

-- Prizes
CREATE TABLE IF NOT EXISTS raffle_prizes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  icon text NOT NULL DEFAULT 'gift',
  color text NOT NULL DEFAULT '#059669',
  quantity int NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  display_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Settings (single row)
CREATE TABLE IF NOT EXISTS raffle_settings (
  id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','sealed','live','closed')),
  blanks_count int NOT NULL DEFAULT 19 CHECK (blanks_count >= 0),
  sealed_at timestamptz,
  live_at timestamptz,
  closed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Allocations
CREATE TABLE IF NOT EXISTS raffle_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_member_id uuid NOT NULL UNIQUE REFERENCES staff_members(id) ON DELETE CASCADE,
  prize_id uuid REFERENCES raffle_prizes(id) ON DELETE SET NULL,
  is_blank boolean NOT NULL DEFAULT false,
  revealed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((is_blank = true AND prize_id IS NULL) OR (is_blank = false AND prize_id IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS raffle_allocations_prize_idx ON raffle_allocations(prize_id);

-- Seed prize catalog
INSERT INTO raffle_prizes (name, icon, color, quantity, display_order) VALUES
  ('Shopping Voucher',    'gift',    '#0d9488', 15, 1),
  ('Solar Table Fan',     'sparkle', '#0891b2', 10, 2),
  ('Insulated Cup',       'cake',    '#0284c7', 16, 3),
  ('Power Bank',          'sparkle', '#7c3aed', 12, 4),
  ('Bluetooth Headphone', 'chat',    '#ea580c', 10, 5),
  ('Smart Watch',         'star',    '#db2777',  7, 6),
  ('Branded Mug',         'cake',    '#65a30d', 10, 7),
  ('5K Cash Prize',       'gift',    '#16a34a', 35, 8),
  ('10K Cash Prize',      'gift',    '#15803d', 30, 9),
  ('20K Cash Prize',      'star',    '#166534', 15, 10)
ON CONFLICT (name) DO NOTHING;

-- Seed settings singleton
INSERT INTO raffle_settings (id, status, blanks_count) VALUES (1, 'draft', 19)
ON CONFLICT (id) DO NOTHING;

-- Enable RLS
ALTER TABLE raffle_prizes ENABLE ROW LEVEL SECURITY;
ALTER TABLE raffle_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE raffle_allocations ENABLE ROW LEVEL SECURITY;

-- Policies: prizes (read-all authenticated; admin-only writes)
DROP POLICY IF EXISTS "raffle_prizes read" ON raffle_prizes;
CREATE POLICY "raffle_prizes read" ON raffle_prizes FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "raffle_prizes admin update" ON raffle_prizes;
CREATE POLICY "raffle_prizes admin update" ON raffle_prizes FOR UPDATE TO authenticated
  USING (is_email_admin()) WITH CHECK (is_email_admin());

DROP POLICY IF EXISTS "raffle_prizes admin insert" ON raffle_prizes;
CREATE POLICY "raffle_prizes admin insert" ON raffle_prizes FOR INSERT TO authenticated
  WITH CHECK (is_email_admin());

DROP POLICY IF EXISTS "raffle_prizes admin delete" ON raffle_prizes;
CREATE POLICY "raffle_prizes admin delete" ON raffle_prizes FOR DELETE TO authenticated
  USING (is_email_admin());

-- Policies: settings (read-all; admin update)
DROP POLICY IF EXISTS "raffle_settings read" ON raffle_settings;
CREATE POLICY "raffle_settings read" ON raffle_settings FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "raffle_settings admin update" ON raffle_settings;
CREATE POLICY "raffle_settings admin update" ON raffle_settings FOR UPDATE TO authenticated
  USING (is_email_admin()) WITH CHECK (is_email_admin());

-- Policies: allocations (own row read for users; admin reads all)
DROP POLICY IF EXISTS "raffle_allocations own read" ON raffle_allocations;
CREATE POLICY "raffle_allocations own read" ON raffle_allocations FOR SELECT TO authenticated
  USING (
    is_email_admin()
    OR EXISTS (
      SELECT 1 FROM staff_members s
      WHERE s.id = raffle_allocations.staff_member_id
        AND s.auth_user_id = auth.uid()
    )
  );
-- No INSERT/UPDATE/DELETE policies — all writes go through SECURITY DEFINER functions.

-- Simulation (admin): returns a fresh random preview without writing
CREATE OR REPLACE FUNCTION raffle_simulate()
RETURNS TABLE (
  staff_id uuid,
  full_name text,
  email text,
  prize_name text,
  is_blank boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  blanks int;
BEGIN
  IF NOT is_email_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT blanks_count INTO blanks FROM raffle_settings WHERE id = 1;

  RETURN QUERY
  WITH pool AS (
    SELECT p.name AS pname, p.id AS pid, false AS blank
    FROM raffle_prizes p
    CROSS JOIN LATERAL generate_series(1, p.quantity) g
    UNION ALL
    SELECT NULL::text, NULL::uuid, true
    FROM generate_series(1, blanks)
  ),
  shuffled_pool AS (
    SELECT pname, pid, blank, row_number() OVER (ORDER BY random()) AS rn FROM pool
  ),
  shuffled_staff AS (
    SELECT s.id AS sid, s.full_name AS sname, s.email AS semail,
           row_number() OVER (ORDER BY random()) AS rn
    FROM staff_members s
    WHERE s.is_active IS NOT FALSE
  )
  SELECT ss.sid, ss.sname, ss.semail, sp.pname, sp.blank
  FROM shuffled_staff ss
  LEFT JOIN shuffled_pool sp ON sp.rn = ss.rn;
END;
$$;

GRANT EXECUTE ON FUNCTION raffle_simulate() TO authenticated;

-- Seed (admin): one-shot; writes allocations, flips to sealed
CREATE OR REPLACE FUNCTION raffle_seed()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_status text;
  staff_count int;
  prize_total int;
  blanks int;
BEGIN
  IF NOT is_email_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT status, blanks_count INTO current_status, blanks FROM raffle_settings WHERE id = 1 FOR UPDATE;
  IF current_status <> 'draft' THEN
    RAISE EXCEPTION 'raffle already sealed (status=%). Reset required to re-seed.', current_status;
  END IF;

  SELECT count(*) INTO staff_count FROM staff_members WHERE is_active IS NOT FALSE;
  SELECT coalesce(sum(quantity), 0) INTO prize_total FROM raffle_prizes;

  IF prize_total + blanks <> staff_count THEN
    RAISE EXCEPTION 'slot mismatch: staff=% but prize_total=% + blanks=% = %',
      staff_count, prize_total, blanks, prize_total + blanks;
  END IF;

  INSERT INTO raffle_allocations (staff_member_id, prize_id, is_blank)
  WITH pool AS (
    SELECT p.id AS pid, false AS blank
    FROM raffle_prizes p
    CROSS JOIN LATERAL generate_series(1, p.quantity) g
    UNION ALL
    SELECT NULL::uuid, true FROM generate_series(1, blanks)
  ),
  shuffled_pool AS (
    SELECT pid, blank, row_number() OVER (ORDER BY random()) AS rn FROM pool
  ),
  shuffled_staff AS (
    SELECT id AS sid, row_number() OVER (ORDER BY random()) AS rn
    FROM staff_members WHERE is_active IS NOT FALSE
  )
  SELECT ss.sid, sp.pid, sp.blank
  FROM shuffled_staff ss
  JOIN shuffled_pool sp ON sp.rn = ss.rn;

  UPDATE raffle_settings
    SET status = 'sealed', sealed_at = now(), updated_at = now()
    WHERE id = 1;

  RETURN jsonb_build_object('ok', true, 'allocated', staff_count);
END;
$$;

GRANT EXECUTE ON FUNCTION raffle_seed() TO authenticated;

-- Status transitions (admin)
CREATE OR REPLACE FUNCTION raffle_set_status(new_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_status text;
BEGIN
  IF NOT is_email_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF new_status NOT IN ('sealed','live','closed') THEN
    RAISE EXCEPTION 'invalid status: %', new_status;
  END IF;

  SELECT status INTO current_status FROM raffle_settings WHERE id = 1 FOR UPDATE;

  IF new_status = 'live' AND current_status <> 'sealed' THEN
    RAISE EXCEPTION 'can only go live from sealed, current=%', current_status;
  END IF;
  IF new_status = 'closed' AND current_status NOT IN ('live','sealed') THEN
    RAISE EXCEPTION 'can only close from live/sealed, current=%', current_status;
  END IF;

  UPDATE raffle_settings
  SET status = new_status,
      live_at = CASE WHEN new_status='live' THEN now() ELSE live_at END,
      closed_at = CASE WHEN new_status='closed' THEN now() ELSE closed_at END,
      updated_at = now()
  WHERE id = 1;

  RETURN jsonb_build_object('ok', true, 'status', new_status);
END;
$$;

GRANT EXECUTE ON FUNCTION raffle_set_status(text) TO authenticated;

-- Reveal (any authenticated staff): idempotent
CREATE OR REPLACE FUNCTION raffle_reveal()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_status text;
  my_staff_id uuid;
  alloc record;
  prize record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT status INTO current_status FROM raffle_settings WHERE id = 1;
  IF current_status NOT IN ('live','closed') THEN
    RAISE EXCEPTION 'raffle not live';
  END IF;

  SELECT id INTO my_staff_id FROM staff_members WHERE auth_user_id = auth.uid() LIMIT 1;
  IF my_staff_id IS NULL THEN
    RAISE EXCEPTION 'no staff record for this user';
  END IF;

  SELECT * INTO alloc FROM raffle_allocations WHERE staff_member_id = my_staff_id;
  IF alloc IS NULL THEN
    RAISE EXCEPTION 'no allocation found for your account';
  END IF;

  IF alloc.revealed_at IS NULL THEN
    UPDATE raffle_allocations SET revealed_at = now()
    WHERE staff_member_id = my_staff_id AND revealed_at IS NULL
    RETURNING * INTO alloc;
  END IF;

  IF alloc.prize_id IS NOT NULL THEN
    SELECT id, name, icon, color INTO prize FROM raffle_prizes WHERE id = alloc.prize_id;
  END IF;

  RETURN jsonb_build_object(
    'is_blank', alloc.is_blank,
    'revealed_at', alloc.revealed_at,
    'prize', CASE
      WHEN alloc.is_blank THEN NULL
      ELSE jsonb_build_object('id', prize.id, 'name', prize.name, 'icon', prize.icon, 'color', prize.color)
    END
  );
END;
$$;

GRANT EXECUTE ON FUNCTION raffle_reveal() TO authenticated;

-- Reset (super admin) — safety valve in case sealing needs to be redone.
CREATE OR REPLACE FUNCTION raffle_reset()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_users
    WHERE email = lower(auth.jwt() ->> 'email') AND role = 'super_admin'
  ) THEN
    RAISE EXCEPTION 'super admin only';
  END IF;

  DELETE FROM raffle_allocations;
  UPDATE raffle_settings
    SET status='draft', sealed_at=NULL, live_at=NULL, closed_at=NULL, updated_at=now()
    WHERE id=1;
  RETURN jsonb_build_object('ok', true);
END;
$$;

GRANT EXECUTE ON FUNCTION raffle_reset() TO authenticated;

-- Stats helper (admin): revealed count per prize plus totals
CREATE OR REPLACE FUNCTION raffle_stats()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT is_email_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM raffle_allocations),
    'revealed', (SELECT count(*) FROM raffle_allocations WHERE revealed_at IS NOT NULL),
    'pending', (SELECT count(*) FROM raffle_allocations WHERE revealed_at IS NULL),
    'blanks_total', (SELECT count(*) FROM raffle_allocations WHERE is_blank),
    'blanks_revealed', (SELECT count(*) FROM raffle_allocations WHERE is_blank AND revealed_at IS NOT NULL),
    'by_prize', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'prize_id', p.id, 'name', p.name, 'quantity', p.quantity,
        'revealed', coalesce(r.revealed, 0)
      ) ORDER BY p.display_order), '[]'::jsonb)
      FROM raffle_prizes p
      LEFT JOIN (
        SELECT prize_id, count(*) FILTER (WHERE revealed_at IS NOT NULL) AS revealed
        FROM raffle_allocations GROUP BY prize_id
      ) r ON r.prize_id = p.id
    )
  ) INTO result;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION raffle_stats() TO authenticated;
