/*
  # User shortcut pins

  Lets each staff member personalize which "quick shortcuts" appear on their home
  page. The catalog of available shortcuts is defined in app code; this table
  only stores the user's chosen keys and their ordering.

  1. New Table
    - `user_shortcut_pins`
      - `user_id` (uuid, PK, references auth.users)
      - `pins` (text[]) — ordered list of shortcut keys (e.g. ['appointments','leave'])
      - `updated_at` (timestamptz)

  2. Security
    - RLS enabled
    - Each user can only read/insert/update/delete their own row
    - No cross-user access

  3. Notes
    1. Keys are validated client-side against a static catalog; we intentionally
       do not enforce a CHECK so the catalog can evolve without migrations.
*/

CREATE TABLE IF NOT EXISTS public.user_shortcut_pins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  pins text[] NOT NULL DEFAULT ARRAY[]::text[],
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_shortcut_pins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "User reads own pins" ON public.user_shortcut_pins;
CREATE POLICY "User reads own pins"
  ON public.user_shortcut_pins FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "User inserts own pins" ON public.user_shortcut_pins;
CREATE POLICY "User inserts own pins"
  ON public.user_shortcut_pins FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "User updates own pins" ON public.user_shortcut_pins;
CREATE POLICY "User updates own pins"
  ON public.user_shortcut_pins FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "User deletes own pins" ON public.user_shortcut_pins;
CREATE POLICY "User deletes own pins"
  ON public.user_shortcut_pins FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());
