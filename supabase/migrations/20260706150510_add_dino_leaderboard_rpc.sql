/*
  # Add dino leaderboard RPC

  The client-side leaderboard was fetching ALL scores (no limit), but PostgREST
  caps responses at 1000 rows by default. With 1187+ scores, newer entries were
  silently dropped, causing the leaderboard to miss updated personal bests.

  Fix: aggregate the top-10 server-side via an RPC.
*/

CREATE OR REPLACE FUNCTION public.dino_leaderboard(p_limit int DEFAULT 10)
RETURNS TABLE (
  user_id uuid,
  best int,
  name text,
  avatar text,
  role text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.user_id,
    s.best::int,
    COALESCE(sm.full_name, 'Sycamore staff') AS name,
    up.avatar_url AS avatar,
    sm.role
  FROM (
    SELECT dr.user_id, MAX(dr.score) AS best
    FROM dino_runner_scores dr
    GROUP BY dr.user_id
    ORDER BY best DESC
    LIMIT p_limit
  ) s
  LEFT JOIN staff_members sm ON sm.auth_user_id = s.user_id
  LEFT JOIN user_profiles up ON up.user_id = s.user_id
  ORDER BY s.best DESC;
$$;

REVOKE ALL ON FUNCTION public.dino_leaderboard(int) FROM public;
GRANT EXECUTE ON FUNCTION public.dino_leaderboard(int) TO authenticated, service_role;
