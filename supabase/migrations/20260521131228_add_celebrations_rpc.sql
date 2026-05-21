/*
  # Add celebrations RPC for birthday/anniversary display

  1. Functions
    - `get_upcoming_celebrations()` - Returns upcoming birthdays (month/day only, no birth year)
      and work anniversaries for the next 30 days. Designed for all authenticated users.

  2. Notes
    - Only exposes month and day of birth, never the full date
    - Only returns active, directory-visible staff
    - Anniversaries include years at company
*/

CREATE OR REPLACE FUNCTION public.get_upcoming_celebrations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today date := CURRENT_DATE;
  v_birthdays jsonb;
  v_anniversaries jsonb;
BEGIN
  -- Birthdays: get month/day only for next 30 days
  SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.days_until), '[]'::jsonb)
  INTO v_birthdays
  FROM (
    SELECT
      sm.id,
      sm.full_name,
      sm.role,
      sm.auth_user_id,
      d.name as department_name,
      EXTRACT(MONTH FROM sp.date_of_birth)::int as birth_month,
      EXTRACT(DAY FROM sp.date_of_birth)::int as birth_day,
      CASE
        WHEN make_date(EXTRACT(YEAR FROM v_today)::int, EXTRACT(MONTH FROM sp.date_of_birth)::int, EXTRACT(DAY FROM sp.date_of_birth)::int) >= v_today
        THEN make_date(EXTRACT(YEAR FROM v_today)::int, EXTRACT(MONTH FROM sp.date_of_birth)::int, EXTRACT(DAY FROM sp.date_of_birth)::int) - v_today
        ELSE make_date(EXTRACT(YEAR FROM v_today)::int + 1, EXTRACT(MONTH FROM sp.date_of_birth)::int, EXTRACT(DAY FROM sp.date_of_birth)::int) - v_today
      END as days_until
    FROM staff_members sm
    JOIN staff_private_data sp ON sp.id = sm.id
    LEFT JOIN departments d ON d.id = sm.department_id
    WHERE sm.is_active = true
      AND sm.directory_visible = true
      AND sp.date_of_birth IS NOT NULL
  ) t
  WHERE t.days_until <= 30;

  -- Work anniversaries: next 30 days, only those with 1+ years
  SELECT COALESCE(jsonb_agg(row_to_json(t)::jsonb ORDER BY t.days_until), '[]'::jsonb)
  INTO v_anniversaries
  FROM (
    SELECT
      sm.id,
      sm.full_name,
      sm.role,
      sm.auth_user_id,
      d.name as department_name,
      EXTRACT(MONTH FROM sm.joined_date)::int as anniversary_month,
      EXTRACT(DAY FROM sm.joined_date)::int as anniversary_day,
      EXTRACT(YEAR FROM v_today)::int - EXTRACT(YEAR FROM sm.joined_date)::int as years,
      CASE
        WHEN make_date(EXTRACT(YEAR FROM v_today)::int, EXTRACT(MONTH FROM sm.joined_date)::int, EXTRACT(DAY FROM sm.joined_date)::int) >= v_today
        THEN make_date(EXTRACT(YEAR FROM v_today)::int, EXTRACT(MONTH FROM sm.joined_date)::int, EXTRACT(DAY FROM sm.joined_date)::int) - v_today
        ELSE make_date(EXTRACT(YEAR FROM v_today)::int + 1, EXTRACT(MONTH FROM sm.joined_date)::int, EXTRACT(DAY FROM sm.joined_date)::int) - v_today
      END as days_until
    FROM staff_members sm
    LEFT JOIN departments d ON d.id = sm.department_id
    WHERE sm.is_active = true
      AND sm.directory_visible = true
      AND sm.joined_date IS NOT NULL
      AND EXTRACT(YEAR FROM v_today)::int - EXTRACT(YEAR FROM sm.joined_date)::int > 0
  ) t
  WHERE t.days_until <= 30;

  RETURN jsonb_build_object(
    'birthdays', v_birthdays,
    'anniversaries', v_anniversaries
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_upcoming_celebrations() TO authenticated;
