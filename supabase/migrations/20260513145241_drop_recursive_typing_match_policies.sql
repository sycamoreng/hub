/*
  # Drop recursive typing match RLS policies

  A leftover `typing_match_players` table carries an RLS policy whose
  `qual` references `typing_match_players` itself (`EXISTS (... FROM
  typing_match_players p2 WHERE p2.match_id = m.id AND p2.user_id =
  auth.uid())`). The clause inside the EXISTS triggers RLS evaluation on
  the same table, producing `infinite recursion detected in policy for
  relation "typing_match_players"`.

  In addition, `typing_matches` has a `Players read their matches` policy
  that joins to that same broken `typing_match_players` table (and uses
  the wrong join condition `p.match_id = p.id`). Because the project
  actually stores match membership in `typing_match_participants`, this
  policy is both dead weight and the trigger for the recursion error
  above when reading `typing_matches`.

  ## Changes
  1. Drop the recursive policy on `typing_match_players`.
  2. Drop the `Players read their matches` policy on `typing_matches`.

  ## Safety
  - `typing_matches` still has `Authenticated read matches` (USING true)
    so authenticated reads continue to work.
  - `typing_match_players` is unused by the application; with no SELECT
    policy and RLS enabled it remains locked down for `authenticated`
    while we keep the table for now.
*/

DROP POLICY IF EXISTS "Players read own match rows" ON public.typing_match_players;
DROP POLICY IF EXISTS "Players read their matches" ON public.typing_matches;
