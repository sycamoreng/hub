/*
  # HR Feedback Phase 1

  Adds support for the HR team's feedback:
  1. Staff salary & level
     - `staff_members.monthly_net_salary` and `level` for auto-calculated allowances and finance reviews.
  2. Loans (Finance Requests)
     - Adds `loan_category` (personal/asset), `monthly_net_salary` snapshot.
     - Two-stage approval: HC review then Finance payout. New columns capture each stage and a rollup trigger keeps `status` consistent.
  3. Leave allowance
     - Adds `monthly_net_salary` snapshot, `allowance_amount`, plus Finance payout columns on `leave_requests` so HC approval triggers the Finance step.
  4. Exit attachments + ordered clearance
     - Adds `resignation_letter_url`, `handover_notes_url`, `handover_summary`, `hc_final_confirmed_at`, `hc_final_confirmed_by`.
     - Reorders `exit_units.sort_order` so clearance flow runs HC -> Line Manager -> Internal Control -> Technology -> Finance -> HC final confirmation.
  5. HMO providers list
     - New `hmo_providers` table with admin RLS for the benefits page.
  6. Learning budgets per level
     - New `learning_budgets` table with admin RLS.
  7. Storage buckets
     - `exit-documents` (private) for resignation/handover uploads
     - `hmo-documents` (public) for the HMO provider list

  Security: RLS enabled on every new table; storage policies restrict writes to admins and reads to authenticated users (or public for HMO).
*/

-- 1. Staff salary + level
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staff_members' AND column_name='monthly_net_salary') THEN
    ALTER TABLE staff_members ADD COLUMN monthly_net_salary numeric(14,2) DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='staff_members' AND column_name='level') THEN
    ALTER TABLE staff_members ADD COLUMN level text DEFAULT '';
  END IF;
END $$;

-- 2. Finance requests two-stage flow
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='finance_requests' AND column_name='loan_category') THEN
    ALTER TABLE finance_requests ADD COLUMN loan_category text DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='finance_requests' AND column_name='monthly_net_salary') THEN
    ALTER TABLE finance_requests ADD COLUMN monthly_net_salary numeric(14,2) DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='finance_requests' AND column_name='hc_status') THEN
    ALTER TABLE finance_requests ADD COLUMN hc_status text DEFAULT 'pending';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='finance_requests' AND column_name='hc_reviewer_id') THEN
    ALTER TABLE finance_requests ADD COLUMN hc_reviewer_id uuid;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='finance_requests' AND column_name='hc_decided_at') THEN
    ALTER TABLE finance_requests ADD COLUMN hc_decided_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='finance_requests' AND column_name='hc_notes') THEN
    ALTER TABLE finance_requests ADD COLUMN hc_notes text DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='finance_requests' AND column_name='finance_status') THEN
    ALTER TABLE finance_requests ADD COLUMN finance_status text DEFAULT 'pending';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='finance_requests' AND column_name='finance_reviewer_id') THEN
    ALTER TABLE finance_requests ADD COLUMN finance_reviewer_id uuid;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='finance_requests' AND column_name='finance_decided_at') THEN
    ALTER TABLE finance_requests ADD COLUMN finance_decided_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='finance_requests' AND column_name='finance_notes') THEN
    ALTER TABLE finance_requests ADD COLUMN finance_notes text DEFAULT '';
  END IF;
END $$;

-- Rollup trigger to keep finance_requests.status in sync with the two-stage flow
CREATE OR REPLACE FUNCTION public._finance_rollup_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.hc_status = 'rejected' OR NEW.finance_status = 'rejected' THEN
    NEW.status := 'rejected';
  ELSIF NEW.finance_status = 'approved' THEN
    NEW.status := 'approved';
  ELSIF NEW.hc_status = 'approved' THEN
    NEW.status := 'hc_approved';
  ELSE
    NEW.status := 'pending';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS finance_rollup_status ON finance_requests;
CREATE TRIGGER finance_rollup_status
BEFORE UPDATE ON finance_requests
FOR EACH ROW EXECUTE FUNCTION public._finance_rollup_status();

-- 3. Leave allowance + finance payout
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='monthly_net_salary') THEN
    ALTER TABLE leave_requests ADD COLUMN monthly_net_salary numeric(14,2) DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='allowance_amount') THEN
    ALTER TABLE leave_requests ADD COLUMN allowance_amount numeric(14,2) DEFAULT 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='finance_status') THEN
    ALTER TABLE leave_requests ADD COLUMN finance_status text DEFAULT 'pending';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='finance_reviewer_id') THEN
    ALTER TABLE leave_requests ADD COLUMN finance_reviewer_id uuid;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='finance_decided_at') THEN
    ALTER TABLE leave_requests ADD COLUMN finance_decided_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='finance_notes') THEN
    ALTER TABLE leave_requests ADD COLUMN finance_notes text DEFAULT '';
  END IF;
END $$;

-- 4. Exit case attachments + final HC confirmation
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='exit_cases' AND column_name='resignation_letter_url') THEN
    ALTER TABLE exit_cases ADD COLUMN resignation_letter_url text DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='exit_cases' AND column_name='handover_notes_url') THEN
    ALTER TABLE exit_cases ADD COLUMN handover_notes_url text DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='exit_cases' AND column_name='handover_summary') THEN
    ALTER TABLE exit_cases ADD COLUMN handover_summary text DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='exit_cases' AND column_name='hc_final_confirmed_at') THEN
    ALTER TABLE exit_cases ADD COLUMN hc_final_confirmed_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='exit_cases' AND column_name='hc_final_confirmed_by') THEN
    ALTER TABLE exit_cases ADD COLUMN hc_final_confirmed_by uuid;
  END IF;
END $$;

-- Reorder clearance to HR's requested order: HC -> Line Manager -> Internal Control -> Technology -> Finance -> HC final
UPDATE exit_units SET sort_order = 10 WHERE code = 'human_capital';
UPDATE exit_units SET sort_order = 20 WHERE code = 'line_manager';
UPDATE exit_units SET sort_order = 30 WHERE code = 'internal_control';
UPDATE exit_units SET sort_order = 40 WHERE code = 'technology';
UPDATE exit_units SET sort_order = 50 WHERE code = 'finance';
UPDATE exit_units SET sort_order = 60 WHERE code = 'admin_facilities';
UPDATE exit_units SET sort_order = 70 WHERE code = 'communications';

-- 5. HMO providers
CREATE TABLE IF NOT EXISTS hmo_providers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text DEFAULT '',
  logo_url text DEFAULT '',
  document_url text DEFAULT '',
  contact_email text DEFAULT '',
  contact_phone text DEFAULT '',
  website text DEFAULT '',
  coverage_summary text DEFAULT '',
  sort_order integer DEFAULT 100,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE hmo_providers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can view active HMO providers" ON hmo_providers;
CREATE POLICY "Authenticated can view active HMO providers"
  ON hmo_providers FOR SELECT TO authenticated
  USING (is_active = true OR private.admin_can('benefits','manage'));

DROP POLICY IF EXISTS "Admins manage HMO providers insert" ON hmo_providers;
CREATE POLICY "Admins manage HMO providers insert"
  ON hmo_providers FOR INSERT TO authenticated
  WITH CHECK (private.admin_can('benefits','manage'));

DROP POLICY IF EXISTS "Admins manage HMO providers update" ON hmo_providers;
CREATE POLICY "Admins manage HMO providers update"
  ON hmo_providers FOR UPDATE TO authenticated
  USING (private.admin_can('benefits','manage'))
  WITH CHECK (private.admin_can('benefits','manage'));

DROP POLICY IF EXISTS "Admins manage HMO providers delete" ON hmo_providers;
CREATE POLICY "Admins manage HMO providers delete"
  ON hmo_providers FOR DELETE TO authenticated
  USING (private.admin_can('benefits','manage'));

-- 6. Learning budgets per level
CREATE TABLE IF NOT EXISTS learning_budgets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  level text NOT NULL UNIQUE,
  annual_amount numeric(14,2) NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'NGN',
  notes text DEFAULT '',
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE learning_budgets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can view learning budgets" ON learning_budgets;
CREATE POLICY "Authenticated can view learning budgets"
  ON learning_budgets FOR SELECT TO authenticated
  USING (is_active = true OR private.admin_can('benefits','manage'));

DROP POLICY IF EXISTS "Admins manage learning budgets insert" ON learning_budgets;
CREATE POLICY "Admins manage learning budgets insert"
  ON learning_budgets FOR INSERT TO authenticated
  WITH CHECK (private.admin_can('benefits','manage'));

DROP POLICY IF EXISTS "Admins manage learning budgets update" ON learning_budgets;
CREATE POLICY "Admins manage learning budgets update"
  ON learning_budgets FOR UPDATE TO authenticated
  USING (private.admin_can('benefits','manage'))
  WITH CHECK (private.admin_can('benefits','manage'));

DROP POLICY IF EXISTS "Admins manage learning budgets delete" ON learning_budgets;
CREATE POLICY "Admins manage learning budgets delete"
  ON learning_budgets FOR DELETE TO authenticated
  USING (private.admin_can('benefits','manage'));

-- 7. Storage buckets
INSERT INTO storage.buckets (id, name, public)
VALUES ('exit-documents', 'exit-documents', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('hmo-documents', 'hmo-documents', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Authenticated can read exit documents" ON storage.objects;
CREATE POLICY "Authenticated can read exit documents"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'exit-documents');

DROP POLICY IF EXISTS "Authenticated can upload exit documents" ON storage.objects;
CREATE POLICY "Authenticated can upload exit documents"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'exit-documents');

DROP POLICY IF EXISTS "Authenticated can update own exit documents" ON storage.objects;
CREATE POLICY "Authenticated can update own exit documents"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'exit-documents' AND owner = auth.uid())
  WITH CHECK (bucket_id = 'exit-documents' AND owner = auth.uid());

DROP POLICY IF EXISTS "Public can read HMO documents" ON storage.objects;
CREATE POLICY "Public can read HMO documents"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'hmo-documents');

DROP POLICY IF EXISTS "Admins upload HMO documents" ON storage.objects;
CREATE POLICY "Admins upload HMO documents"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'hmo-documents' AND private.admin_can('benefits','manage'));

DROP POLICY IF EXISTS "Admins update HMO documents" ON storage.objects;
CREATE POLICY "Admins update HMO documents"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'hmo-documents' AND private.admin_can('benefits','manage'))
  WITH CHECK (bucket_id = 'hmo-documents' AND private.admin_can('benefits','manage'));

DROP POLICY IF EXISTS "Admins delete HMO documents" ON storage.objects;
CREATE POLICY "Admins delete HMO documents"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'hmo-documents' AND private.admin_can('benefits','manage'));
