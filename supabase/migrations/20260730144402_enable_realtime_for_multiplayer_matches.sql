DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'wordle_matches','wordle_match_participants',
    'guess_who_matches','guess_who_match_participants',
    'dino_matches','dino_match_participants',
    'codebreaker_matches','codebreaker_match_participants',
    'crossword_matches','crossword_match_participants'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', t);
  END LOOP;
END $$;