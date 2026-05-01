/*
  # Harden SECURITY DEFINER RPC exposure and relocate vector extension

  The Supabase security advisor flagged several issues:

  1. `vector` extension installed in the `public` schema.
  2. Several SECURITY DEFINER functions in `public` are callable via PostgREST
     by `anon` and/or `authenticated`, even though they are meant to be invoked
     only by admins (raffle_*, is_email_admin) or by authenticated users with
     specific intent (claim_staff_member, raffle_reveal).

  Changes
  -------
  1. Extension relocation
    - Create schema `extensions` if it does not exist.
    - Move `vector` extension from `public` to `extensions`.

  2. Revoke broad EXECUTE grants on SECURITY DEFINER RPCs
    - Revoke EXECUTE from PUBLIC, anon on all flagged functions.
    - Revoke EXECUTE from authenticated on strictly admin-only RPCs:
      raffle_allocations_admin, raffle_reset, raffle_seed, raffle_set_status,
      raffle_simulate, raffle_stats, is_email_admin.
      These functions already re-check admin status internally, but removing
      EXECUTE prevents the anon/authenticated roles from reaching them over
      PostgREST at all, which is the intent of the advisor warning.
    - Keep EXECUTE for authenticated on raffle_reveal and claim_staff_member:
      both are expected to be called by signed-in staff, and both guard their
      own logic (auth.uid() check + specific updates scoped to the caller).

  Security
  --------
  - RLS posture is unchanged.
  - Admin-only RPCs now return a permission error at the API layer for
    non-admins instead of relying solely on the internal admin check.
  - No data is modified; this is a privilege-only migration.
*/

CREATE SCHEMA IF NOT EXISTS extensions;
GRANT USAGE ON SCHEMA extensions TO authenticated, anon, service_role;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'vector' AND n.nspname = 'public'
  ) THEN
    EXECUTE 'ALTER EXTENSION vector SET SCHEMA extensions';
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.raffle_allocations_admin()    FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.raffle_reset()                FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.raffle_seed()                 FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.raffle_set_status(text)       FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.raffle_simulate()             FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.raffle_stats()                FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.is_email_admin()              FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.raffle_reveal()               FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.claim_staff_member()          FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.raffle_reveal()        TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_staff_member()   TO authenticated;
