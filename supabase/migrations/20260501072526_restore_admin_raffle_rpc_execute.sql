/*
  # Restore EXECUTE on admin raffle RPCs for authenticated

  The previous migration revoked EXECUTE from `authenticated` on admin raffle
  RPCs to satisfy the security advisor. However, the admin UI calls these
  functions directly from the browser using the end user's JWT (role =
  authenticated), and each function already performs its own admin check
  internally (is_email_admin / super_admin). Removing EXECUTE breaks the
  admin UI with a permission error.

  This migration restores EXECUTE to `authenticated` for those RPCs. The
  functions' internal admin checks remain the authorization boundary.
  EXECUTE for `anon` and `PUBLIC` stays revoked, so unauthenticated callers
  cannot reach them.

  Changes
  -------
  - GRANT EXECUTE to authenticated on:
      raffle_allocations_admin, raffle_reset, raffle_seed,
      raffle_set_status(text), raffle_simulate, raffle_stats,
      is_email_admin
  - Anon remains revoked for all of the above.
*/

GRANT EXECUTE ON FUNCTION public.raffle_allocations_admin()  TO authenticated;
GRANT EXECUTE ON FUNCTION public.raffle_reset()              TO authenticated;
GRANT EXECUTE ON FUNCTION public.raffle_seed()               TO authenticated;
GRANT EXECUTE ON FUNCTION public.raffle_set_status(text)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.raffle_simulate()           TO authenticated;
GRANT EXECUTE ON FUNCTION public.raffle_stats()              TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_email_admin()            TO authenticated;
