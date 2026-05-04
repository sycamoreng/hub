/*
  # Salary advance and loan requests

  Adds a finance request workflow where staff can request a salary advance
  or a multi-month loan, and admins with payroll access review, approve,
  or decline the request.

  1. New tables
    - `finance_requests`
      - `id` uuid primary key
      - `staff_id` uuid references staff_members
      - `requester_user_id` uuid references auth.users
      - `type` text: 'advance' or 'loan'
      - `amount` numeric(14,2)
      - `currency` text (default NGN)
      - `reason` text
      - `repayment_months` int (1 for advance)
      - `status` text: 'pending' | 'approved' | 'declined' | 'cancelled'
      - `decided_by` uuid, `decided_at` timestamptz, `decision_notes` text
      - `created_at`, `updated_at`

  2. Security
    - RLS enabled.
    - Staff can SELECT and INSERT their own requests.
    - Staff can UPDATE to cancel their own pending requests.
    - Admins with `payroll` read can see all; create/update require payroll create/update.
*/

CREATE TABLE IF NOT EXISTS finance_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff_members(id) ON DELETE SET NULL,
  requester_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  type text NOT NULL CHECK (type IN ('advance','loan')),
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  currency text NOT NULL DEFAULT 'NGN',
  reason text NOT NULL DEFAULT '',
  repayment_months int NOT NULL DEFAULT 1 CHECK (repayment_months BETWEEN 1 AND 36),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','declined','cancelled')),
  decided_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  decided_at timestamptz,
  decision_notes text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS finance_requests_user_idx ON finance_requests(requester_user_id);
CREATE INDEX IF NOT EXISTS finance_requests_status_idx ON finance_requests(status);
CREATE INDEX IF NOT EXISTS finance_requests_staff_idx ON finance_requests(staff_id);

ALTER TABLE finance_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Staff view own finance requests" ON finance_requests;
CREATE POLICY "Staff view own finance requests"
  ON finance_requests FOR SELECT
  TO authenticated
  USING (requester_user_id = auth.uid() OR private.admin_can('payroll','read'));

DROP POLICY IF EXISTS "Staff create own finance requests" ON finance_requests;
CREATE POLICY "Staff create own finance requests"
  ON finance_requests FOR INSERT
  TO authenticated
  WITH CHECK (requester_user_id = auth.uid() OR private.admin_can('payroll','create'));

DROP POLICY IF EXISTS "Staff cancel own pending finance requests" ON finance_requests;
CREATE POLICY "Staff cancel own pending finance requests"
  ON finance_requests FOR UPDATE
  TO authenticated
  USING (
    (requester_user_id = auth.uid() AND status = 'pending')
    OR private.admin_can('payroll','update')
  )
  WITH CHECK (
    (requester_user_id = auth.uid() AND status IN ('pending','cancelled'))
    OR private.admin_can('payroll','update')
  );

DROP POLICY IF EXISTS "Admins delete finance requests" ON finance_requests;
CREATE POLICY "Admins delete finance requests"
  ON finance_requests FOR DELETE
  TO authenticated
  USING (private.admin_can('payroll','delete'));
