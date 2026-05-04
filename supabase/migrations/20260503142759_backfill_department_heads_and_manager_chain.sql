/*
  # Auto-detect department heads and backfill manager chain

  Most departments already have a `head_email` and `head_title` filled
  in as text but `head_staff_id` was not set, so the organogram and
  "My Team" page had no link back to a real staff record. This migration
  resolves heads automatically and derives the initial reporting chain.

  1. Changes
    - For every department with `head_email` but no `head_staff_id`,
      match by lowercased email against `staff_members` and set
      `head_staff_id`.
    - As a fallback, try matching by `head_name` (case-insensitive)
      when email matching did not find a staff row.
    - For every active staff member whose department has a head and
      whose `manager_id` is not set, default their manager to the
      department head (skipping the head themselves).

  2. Notes
    - Only fills `null` values; no existing assignments are overwritten.
    - Staff in sub-teams will be further refined later by assigning
      team leads; this migration establishes the baseline top-level
      chain.

  3. Security
    - No RLS changes.
*/

UPDATE departments d
SET head_staff_id = s.id
FROM staff_members s
WHERE d.head_staff_id IS NULL
  AND d.head_email <> ''
  AND lower(s.email) = lower(d.head_email);

UPDATE departments d
SET head_staff_id = s.id
FROM staff_members s
WHERE d.head_staff_id IS NULL
  AND d.head_name <> ''
  AND lower(s.full_name) = lower(d.head_name);

UPDATE staff_members sm
SET manager_id = d.head_staff_id
FROM departments d
WHERE sm.manager_id IS NULL
  AND sm.department_id = d.id
  AND d.head_staff_id IS NOT NULL
  AND sm.id <> d.head_staff_id
  AND sm.is_active = true;
