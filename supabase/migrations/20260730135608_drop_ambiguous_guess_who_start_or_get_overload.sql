-- Remove the p_staff_id-taking overload that conflicts with the daily-puzzle
-- entry point of the same name. Match creation is handled by
-- public.guess_who_match_create.
DROP FUNCTION IF EXISTS public.guess_who_start_or_get(uuid);
