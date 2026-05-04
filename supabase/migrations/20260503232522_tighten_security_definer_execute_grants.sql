/*
  # Tighten EXECUTE grants on SECURITY DEFINER RPCs

  ## Summary
  The database advisor flagged SECURITY DEFINER functions that were
  callable by the `anon` (unauthenticated) role via PostgREST. This
  migration revokes EXECUTE from `anon` on all flagged functions and
  additionally revokes `authenticated` EXECUTE from helpers that are
  only meant to be called internally by other functions.

  ## Changes
  1. Revoke EXECUTE from `public` and `anon` on every flagged RPC.
  2. Revoke EXECUTE from `authenticated` on internal helpers that the
     frontend never calls directly: `is_attendance_admin`,
     `is_payroll_admin`, `is_email_admin`, and `wordle_pick_word`.
  3. Re-grant EXECUTE to `authenticated` for RPCs that the app calls
     directly: `user_assigned_step_ids`, wordle start/submit,
     raffle_*, `claim_staff_member`.
  4. `postgres` and `service_role` retain EXECUTE everywhere.

  ## Safety
  - Internal admin-check helpers are still callable by the functions
    that need them because SECURITY DEFINER runs as the function
    owner (postgres), not as the caller.
  - No data changes; only GRANT/REVOKE adjustments.
*/

-- Helper macro pattern: revoke from public + anon first, then
-- explicitly re-grant to authenticated where the frontend needs it.

-- Internal helpers - not called from the frontend
revoke execute on function public.is_attendance_admin() from public, anon, authenticated;
revoke execute on function public.is_payroll_admin() from public, anon, authenticated;
revoke execute on function public.is_email_admin() from public, anon, authenticated;
revoke execute on function public.wordle_pick_word(date, integer) from public, anon, authenticated;

-- Called by frontend as authenticated user
revoke execute on function public.user_assigned_step_ids() from public, anon;
grant execute on function public.user_assigned_step_ids() to authenticated;

revoke execute on function public.wordle_start_or_get() from public, anon;
grant execute on function public.wordle_start_or_get() to authenticated;

revoke execute on function public.wordle_submit_guess(text) from public, anon;
grant execute on function public.wordle_submit_guess(text) to authenticated;

revoke execute on function public.claim_staff_member() from public, anon;
grant execute on function public.claim_staff_member() to authenticated;

revoke execute on function public.raffle_allocations_admin() from public, anon;
grant execute on function public.raffle_allocations_admin() to authenticated;

revoke execute on function public.raffle_reset() from public, anon;
grant execute on function public.raffle_reset() to authenticated;

revoke execute on function public.raffle_reveal() from public, anon;
grant execute on function public.raffle_reveal() to authenticated;

revoke execute on function public.raffle_seed() from public, anon;
grant execute on function public.raffle_seed() to authenticated;

revoke execute on function public.raffle_set_status(text) from public, anon;
grant execute on function public.raffle_set_status(text) to authenticated;

revoke execute on function public.raffle_simulate() from public, anon;
grant execute on function public.raffle_simulate() to authenticated;

revoke execute on function public.raffle_stats() from public, anon;
grant execute on function public.raffle_stats() to authenticated;
