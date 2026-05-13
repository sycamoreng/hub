/*
  # Align typing multiplayer schema with app

  The deployed `typing_matches` table is missing the columns the multiplayer
  RPCs and the app rely on (`prompt_id`, `duration_ms`, `started_at`,
  `finished_at`). The participants table is also missing — the legacy
  `typing_match_players` table exists instead. This migration:

  1. Adds the missing columns to `typing_matches`.
  2. Creates `typing_match_participants` with RLS + realtime publication.
  3. Leaves the legacy `typing_match_players` alone for safety.

  No data is dropped.
*/

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='typing_matches' AND column_name='prompt_id') THEN
    ALTER TABLE typing_matches ADD COLUMN prompt_id uuid REFERENCES typing_prompts(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='typing_matches' AND column_name='duration_ms') THEN
    ALTER TABLE typing_matches ADD COLUMN duration_ms integer NOT NULL DEFAULT 60000;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='typing_matches' AND column_name='started_at') THEN
    ALTER TABLE typing_matches ADD COLUMN started_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='typing_matches' AND column_name='finished_at') THEN
    ALTER TABLE typing_matches ADD COLUMN finished_at timestamptz;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS typing_match_participants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES typing_matches(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'invited',
  wpm numeric(6,2) DEFAULT 0,
  accuracy numeric(5,2) DEFAULT 0,
  characters_typed int DEFAULT 0,
  words_typed int DEFAULT 0,
  errors int DEFAULT 0,
  duration_ms int DEFAULT 0,
  rank int,
  joined_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (match_id, user_id),
  CONSTRAINT typing_match_participants_status_chk CHECK (status IN ('invited','joined','finished','declined'))
);

CREATE INDEX IF NOT EXISTS typing_match_participants_match_idx ON typing_match_participants(match_id);
CREATE INDEX IF NOT EXISTS typing_match_participants_user_idx ON typing_match_participants(user_id, created_at DESC);

ALTER TABLE typing_match_participants ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='typing_match_participants' AND policyname='Authenticated read participants') THEN
    CREATE POLICY "Authenticated read participants"
      ON typing_match_participants FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='typing_match_participants'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE typing_match_participants';
  END IF;
EXCEPTION WHEN others THEN NULL;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND tablename='typing_matches'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE typing_matches';
  END IF;
EXCEPTION WHEN others THEN NULL;
END $$;

NOTIFY pgrst, 'reload schema';
