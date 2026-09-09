/*
# Regularize exited staff (July 2026 batch)

1. Purpose
   - Ten staff members have left the company. This records their exits so they
     drop out of the active directory and appear correctly on the Exited list.

2. Changes
   - Updates 7 existing records (matched by employee ID) to mark them exited:
     set exit date, exit reason, inactive, and hidden from the active directory.
   - Inserts 3 records that were not yet in the system, already marked exited.

3. Notes
   - Existing records are matched by staff_id (employee ID); their stored name
     and email are left untouched.
   - No data is deleted.
*/

DO $$
BEGIN
  -- Existing records: mark as exited (matched by employee ID)
  UPDATE staff_members SET exited_at = DATE '2026-07-17', exit_reason = 'Voluntary Exit', is_active = false, directory_visible = false
    WHERE staff_id = 'SISL-2020-010';
  UPDATE staff_members SET exited_at = DATE '2026-07-03', exit_reason = 'Termination', is_active = false, directory_visible = false
    WHERE staff_id = 'SISL-2024-190';
  UPDATE staff_members SET exited_at = DATE '2026-07-03', exit_reason = 'Termination', is_active = false, directory_visible = false
    WHERE staff_id = 'SISL-2024-204';
  UPDATE staff_members SET exited_at = DATE '2026-07-03', exit_reason = 'Termination', is_active = false, directory_visible = false
    WHERE staff_id = 'SMFB-2025-004';
  UPDATE staff_members SET exited_at = DATE '2026-07-03', exit_reason = 'Termination', is_active = false, directory_visible = false
    WHERE staff_id = 'SMFB-2026-008';
  UPDATE staff_members SET exited_at = DATE '2026-07-03', exit_reason = 'Termination', is_active = false, directory_visible = false
    WHERE staff_id = 'SMFB-2026-009';
  UPDATE staff_members SET exited_at = DATE '2026-07-03', exit_reason = 'Termination', is_active = false, directory_visible = false
    WHERE staff_id = 'SMFB-2026-010';

  -- Missing records: insert as already-exited (skip if the id or email already exists)
  INSERT INTO staff_members (staff_id, full_name, email, role, joined_date, exited_at, exit_reason, is_active, directory_visible)
  SELECT v.staff_id, v.full_name, v.email, v.role, v.joined_date, v.exited_at, v.exit_reason, false, false
  FROM (VALUES
    ('SMFB-2025-005', 'Idris Garba',     'idrisgarba561@gmail.com',    'Cleaner',            DATE '2025-09-29', DATE '2026-07-03', 'Termination'),
    ('SMFB-2025-006', 'Abdulrauf Suleiman','abdulraufsuleman4@gmail.com','Operations Officer', DATE '2025-09-29', DATE '2026-07-03', 'Termination'),
    ('SMFB-2025-007', 'Malam Baffa',     'baffanalbasu@gmail.com',     'Cashier',            DATE '2025-09-29', DATE '2026-07-03', 'Termination')
  ) AS v(staff_id, full_name, email, role, joined_date, exited_at, exit_reason)
  WHERE NOT EXISTS (SELECT 1 FROM staff_members sm WHERE sm.staff_id = v.staff_id)
    AND NOT EXISTS (SELECT 1 FROM staff_members sm WHERE lower(sm.email) = lower(v.email));
END $$;
