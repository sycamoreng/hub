/*
  # Internal Control rename and exit HR notification helper

  1. Updates
    - Rename department "Internal Control" to "Internal Control and Audit Department".
    - Rename exit_unit "Internal Control" -> "Internal Control and Audit".
    - Add helper view `staff_directory_exited` exposing inactive staff with
      department/location names so the staff page can display a dedicated
      "Exited staff" list under existing RLS.

  2. Security
    - No RLS changes. The view is built on `staff_members` so existing policies
      apply (super admins / staff.read holders see everyone).
*/

UPDATE public.departments SET name = 'Internal Control and Audit Department'
  WHERE name = 'Internal Control';

UPDATE public.exit_units SET name = 'Internal Control and Audit'
  WHERE code = 'internal_control';

CREATE OR REPLACE VIEW public.staff_directory_exited
WITH (security_invoker = true)
AS
SELECT s.id, s.full_name, s.email, s.role, s.phone, s.bio,
       s.department_id, s.location_id, s.joined_date, s.auth_user_id,
       d.name AS department_name,
       l.name AS location_name, l.city AS location_city,
       (SELECT max(ec.effective_date)::date FROM public.exit_cases ec WHERE ec.staff_id = s.id AND ec.status = 'closed') AS exit_effective_date
FROM public.staff_members s
LEFT JOIN public.departments d ON d.id = s.department_id
LEFT JOIN public.locations l ON l.id = s.location_id
WHERE s.is_active = false;

GRANT SELECT ON public.staff_directory_exited TO authenticated;
