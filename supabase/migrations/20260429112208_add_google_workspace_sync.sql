/*
  # Google Workspace sync (retry with correct function namespace)

  Sets up settings, allow/block rules, department mapping, run log,
  per-field locks, plus google_user_id / avatar_source columns and
  the avatars storage bucket. See prior migration header for details.
*/

CREATE TABLE IF NOT EXISTS google_sync_settings (
  id text PRIMARY KEY DEFAULT 'default',
  domain text DEFAULT '',
  default_action text DEFAULT 'include' CHECK (default_action IN ('include','exclude')),
  auto_sync_enabled boolean DEFAULT false,
  department_source text DEFAULT 'organizations' CHECK (department_source IN ('organizations','orgUnitPath')),
  last_synced_at timestamptz,
  last_sync_status text,
  last_sync_error text,
  updated_at timestamptz DEFAULT now()
);

INSERT INTO google_sync_settings (id) VALUES ('default') ON CONFLICT (id) DO NOTHING;

ALTER TABLE google_sync_settings ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_sync_settings' AND policyname='Admins read sync settings') THEN
    CREATE POLICY "Admins read sync settings" ON google_sync_settings FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_sync_settings' AND policyname='Super admins update sync settings') THEN
    CREATE POLICY "Super admins update sync settings" ON google_sync_settings FOR UPDATE TO authenticated
      USING (private.is_super_admin()) WITH CHECK (private.is_super_admin());
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS google_sync_rules (
  email text PRIMARY KEY,
  action text NOT NULL CHECK (action IN ('include','exclude')),
  note text DEFAULT '',
  updated_at timestamptz DEFAULT now(),
  updated_by text DEFAULT ''
);

ALTER TABLE google_sync_rules ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_sync_rules' AND policyname='Admins read sync rules') THEN
    CREATE POLICY "Admins read sync rules" ON google_sync_rules FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_sync_rules' AND policyname='Admins insert sync rules') THEN
    CREATE POLICY "Admins insert sync rules" ON google_sync_rules FOR INSERT TO authenticated
      WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_sync_rules' AND policyname='Admins update sync rules') THEN
    CREATE POLICY "Admins update sync rules" ON google_sync_rules FOR UPDATE TO authenticated
      USING (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')))
      WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_sync_rules' AND policyname='Admins delete sync rules') THEN
    CREATE POLICY "Admins delete sync rules" ON google_sync_rules FOR DELETE TO authenticated
      USING (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS google_department_map (
  google_value text PRIMARY KEY,
  department_id uuid REFERENCES departments(id) ON DELETE SET NULL,
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE google_department_map ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_department_map' AND policyname='Admins read dept map') THEN
    CREATE POLICY "Admins read dept map" ON google_department_map FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_department_map' AND policyname='Admins insert dept map') THEN
    CREATE POLICY "Admins insert dept map" ON google_department_map FOR INSERT TO authenticated
      WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_department_map' AND policyname='Admins update dept map') THEN
    CREATE POLICY "Admins update dept map" ON google_department_map FOR UPDATE TO authenticated
      USING (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')))
      WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_department_map' AND policyname='Admins delete dept map') THEN
    CREATE POLICY "Admins delete dept map" ON google_department_map FOR DELETE TO authenticated
      USING (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS google_sync_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at timestamptz DEFAULT now(),
  finished_at timestamptz,
  mode text NOT NULL CHECK (mode IN ('dry_run','apply')),
  triggered_by text DEFAULT '',
  added int DEFAULT 0,
  updated int DEFAULT 0,
  skipped int DEFAULT 0,
  excluded int DEFAULT 0,
  deactivated int DEFAULT 0,
  reactivated int DEFAULT 0,
  errors jsonb DEFAULT '[]'::jsonb,
  diff jsonb DEFAULT '[]'::jsonb
);

CREATE INDEX IF NOT EXISTS google_sync_runs_started_idx ON google_sync_runs(started_at DESC);

ALTER TABLE google_sync_runs ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='google_sync_runs' AND policyname='Admins read sync runs') THEN
    CREATE POLICY "Admins read sync runs" ON google_sync_runs FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS staff_member_locks (
  staff_member_id uuid NOT NULL REFERENCES staff_members(id) ON DELETE CASCADE,
  field text NOT NULL,
  updated_at timestamptz DEFAULT now(),
  updated_by text DEFAULT '',
  PRIMARY KEY (staff_member_id, field)
);

ALTER TABLE staff_member_locks ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='staff_member_locks' AND policyname='Admins read staff locks') THEN
    CREATE POLICY "Admins read staff locks" ON staff_member_locks FOR SELECT TO authenticated
      USING (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='staff_member_locks' AND policyname='Admins insert staff locks') THEN
    CREATE POLICY "Admins insert staff locks" ON staff_member_locks FOR INSERT TO authenticated
      WITH CHECK (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='staff_member_locks' AND policyname='Admins delete staff locks') THEN
    CREATE POLICY "Admins delete staff locks" ON staff_member_locks FOR DELETE TO authenticated
      USING (EXISTS (SELECT 1 FROM admin_users WHERE admin_users.email = lower(auth.jwt() ->> 'email')));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS user_profile_locks (
  user_id uuid NOT NULL,
  field text NOT NULL,
  updated_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, field)
);

ALTER TABLE user_profile_locks ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='user_profile_locks' AND policyname='Users manage own profile locks select') THEN
    CREATE POLICY "Users manage own profile locks select" ON user_profile_locks FOR SELECT TO authenticated
      USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='user_profile_locks' AND policyname='Users manage own profile locks insert') THEN
    CREATE POLICY "Users manage own profile locks insert" ON user_profile_locks FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='user_profile_locks' AND policyname='Users manage own profile locks delete') THEN
    CREATE POLICY "Users manage own profile locks delete" ON user_profile_locks FOR DELETE TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='staff_members' AND column_name='google_user_id') THEN
    ALTER TABLE staff_members ADD COLUMN google_user_id text;
    CREATE UNIQUE INDEX staff_members_google_user_id_idx ON staff_members(google_user_id) WHERE google_user_id IS NOT NULL;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='user_profiles' AND column_name='avatar_source') THEN
    ALTER TABLE user_profiles ADD COLUMN avatar_source text DEFAULT 'user';
  END IF;
END $$;

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='Public read avatars') THEN
    CREATE POLICY "Public read avatars" ON storage.objects FOR SELECT TO public
      USING (bucket_id = 'avatars');
  END IF;
END $$;
