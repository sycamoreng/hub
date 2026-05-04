/*
  # Correct manager chain for team leads

  1. Changes
    - For any active staff member who is the lead of a team, if their
      `manager_id` currently points to someone who is NOT the head of
      their department (e.g. it mistakenly points at another team lead
      or a peer in the same department), reassign it to the department
      head. Team leads should report to the department head, not to
      another lead.
    - Only runs when the department has a `head_staff_id` and it's not
      the team lead themselves.

  2. Notes
    - Non-destructive: leaves the assignment alone when the department
      has no head, and never sets a team lead as their own manager.
    - Does not touch non-lead staff; their chain is already correct
      (direct manager, team lead, or department head).

  3. Security
    - No RLS changes.
*/

UPDATE staff_members sm
SET manager_id = d.head_staff_id
FROM teams t, departments d
WHERE t.lead_staff_id = sm.id
  AND sm.department_id = d.id
  AND d.head_staff_id IS NOT NULL
  AND d.head_staff_id <> sm.id
  AND (sm.manager_id IS NULL OR sm.manager_id <> d.head_staff_id)
  AND sm.is_active = true;
