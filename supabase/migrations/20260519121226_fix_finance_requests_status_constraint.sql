/*
  # Fix finance_requests status check constraint

  1. Changes
    - Drop old `finance_requests_status_check` constraint that only allowed: pending, approved, declined, cancelled
    - Add new constraint that also allows `hc_approved` to support the two-stage approval workflow (HC -> Finance)

  2. Important Notes
    - The workflow is: pending -> hc_approved -> approved/declined/cancelled
    - No data is lost or modified, only the constraint is updated
*/

ALTER TABLE finance_requests DROP CONSTRAINT IF EXISTS finance_requests_status_check;

ALTER TABLE finance_requests ADD CONSTRAINT finance_requests_status_check
  CHECK (status = ANY (ARRAY['pending', 'hc_approved', 'approved', 'declined', 'cancelled']));
