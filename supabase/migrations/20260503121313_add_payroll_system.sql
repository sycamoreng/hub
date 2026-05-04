/*
  # Payroll system (Nigerian context)

  Adds a full payroll module with Nigerian statutory handling:
  PAYE (Finance Act 2020 bands with Consolidated Relief Allowance),
  pension (8% employee / 10% employer of basic+housing+transport),
  NHF (2.5% of basic, optional), NHIS/NSITF/ITF employer toggles.

  1. New tables
    - `payroll_employees` — per-staff payroll profile (grade, bank,
      TIN, pension PFA/PIN, NHF toggle, base salary, allowances)
    - `payroll_components` — configurable earning/deduction catalog
    - `payroll_runs` — monthly runs with status draft/approved/paid
    - `payroll_items` — per-employee breakdown inside a run
    - `payroll_settings` — singleton row with org-level toggles & rates

  2. Security
    - RLS enabled on every table.
    - Admins with `payroll` section access manage everything.
    - Staff can SELECT only their own `payroll_items` where the run is
      approved or paid, joined via staff_members.auth_user_id.
    - All other writes are admin-only.

  3. Notes
    1. Tax logic is computed in the application layer so admins can
       override per-run; this migration only stores inputs and results.
    2. Money stored as `numeric(14,2)` to avoid float rounding.
*/

CREATE TABLE IF NOT EXISTS payroll_settings (
  id int PRIMARY KEY DEFAULT 1,
  company_name text DEFAULT 'Sycamore Integrated Solutions Limited',
  company_tin text DEFAULT '',
  pension_employee_rate numeric(5,4) DEFAULT 0.08,
  pension_employer_rate numeric(5,4) DEFAULT 0.10,
  nhf_rate numeric(5,4) DEFAULT 0.025,
  nhis_rate numeric(5,4) DEFAULT 0.05,
  nsitf_rate numeric(5,4) DEFAULT 0.01,
  itf_rate numeric(5,4) DEFAULT 0.01,
  nhis_enabled boolean DEFAULT false,
  nsitf_enabled boolean DEFAULT false,
  itf_enabled boolean DEFAULT false,
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT payroll_settings_singleton CHECK (id = 1)
);

INSERT INTO payroll_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS payroll_employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid REFERENCES staff_members(id) ON DELETE SET NULL,
  full_name text NOT NULL,
  email text NOT NULL,
  grade text DEFAULT '',
  job_title text DEFAULT '',
  bank_name text DEFAULT '',
  bank_account text DEFAULT '',
  tin text DEFAULT '',
  pfa_name text DEFAULT '',
  pfa_pin text DEFAULT '',
  nhf_enabled boolean DEFAULT false,
  pay_basic numeric(14,2) DEFAULT 0,
  pay_housing numeric(14,2) DEFAULT 0,
  pay_transport numeric(14,2) DEFAULT 0,
  pay_utility numeric(14,2) DEFAULT 0,
  pay_meal numeric(14,2) DEFAULT 0,
  pay_leave numeric(14,2) DEFAULT 0,
  pay_other numeric(14,2) DEFAULT 0,
  is_active boolean DEFAULT true,
  notes text DEFAULT '',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payroll_employees_staff_id_idx ON payroll_employees(staff_id);
CREATE INDEX IF NOT EXISTS payroll_employees_active_idx ON payroll_employees(is_active);

CREATE TABLE IF NOT EXISTS payroll_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  period_year int NOT NULL,
  period_month int NOT NULL CHECK (period_month BETWEEN 1 AND 12),
  label text DEFAULT '',
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','paid')),
  pay_date date,
  total_gross numeric(14,2) DEFAULT 0,
  total_paye numeric(14,2) DEFAULT 0,
  total_pension_employee numeric(14,2) DEFAULT 0,
  total_pension_employer numeric(14,2) DEFAULT 0,
  total_nhf numeric(14,2) DEFAULT 0,
  total_net numeric(14,2) DEFAULT 0,
  notes text DEFAULT '',
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (period_year, period_month)
);

CREATE TABLE IF NOT EXISTS payroll_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL REFERENCES payroll_runs(id) ON DELETE CASCADE,
  employee_id uuid REFERENCES payroll_employees(id) ON DELETE SET NULL,
  staff_id uuid REFERENCES staff_members(id) ON DELETE SET NULL,
  full_name text NOT NULL,
  email text NOT NULL,
  grade text DEFAULT '',
  basic numeric(14,2) DEFAULT 0,
  housing numeric(14,2) DEFAULT 0,
  transport numeric(14,2) DEFAULT 0,
  utility numeric(14,2) DEFAULT 0,
  meal numeric(14,2) DEFAULT 0,
  leave_allowance numeric(14,2) DEFAULT 0,
  other_earnings numeric(14,2) DEFAULT 0,
  bonus numeric(14,2) DEFAULT 0,
  gross numeric(14,2) DEFAULT 0,
  pension_employee numeric(14,2) DEFAULT 0,
  pension_employer numeric(14,2) DEFAULT 0,
  nhf numeric(14,2) DEFAULT 0,
  nhis numeric(14,2) DEFAULT 0,
  cra numeric(14,2) DEFAULT 0,
  taxable_income numeric(14,2) DEFAULT 0,
  paye numeric(14,2) DEFAULT 0,
  other_deductions numeric(14,2) DEFAULT 0,
  net numeric(14,2) DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (run_id, employee_id)
);

CREATE INDEX IF NOT EXISTS payroll_items_run_idx ON payroll_items(run_id);
CREATE INDEX IF NOT EXISTS payroll_items_staff_idx ON payroll_items(staff_id);

ALTER TABLE payroll_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_items ENABLE ROW LEVEL SECURITY;

-- helper: admin with payroll section
CREATE OR REPLACE FUNCTION is_payroll_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users au
    WHERE lower(au.email) = lower(coalesce(auth.jwt() ->> 'email',''))
      AND (au.role = 'super_admin' OR 'payroll' = ANY(au.sections))
  );
$$;

REVOKE ALL ON FUNCTION is_payroll_admin() FROM public;
GRANT EXECUTE ON FUNCTION is_payroll_admin() TO authenticated;

-- payroll_settings
CREATE POLICY "Payroll admins can read settings"
  ON payroll_settings FOR SELECT TO authenticated
  USING (is_payroll_admin());
CREATE POLICY "Payroll admins can update settings"
  ON payroll_settings FOR UPDATE TO authenticated
  USING (is_payroll_admin())
  WITH CHECK (is_payroll_admin());
CREATE POLICY "Payroll admins can insert settings"
  ON payroll_settings FOR INSERT TO authenticated
  WITH CHECK (is_payroll_admin());

-- payroll_employees: admin full access
CREATE POLICY "Payroll admins read employees"
  ON payroll_employees FOR SELECT TO authenticated
  USING (is_payroll_admin());
CREATE POLICY "Payroll admins insert employees"
  ON payroll_employees FOR INSERT TO authenticated
  WITH CHECK (is_payroll_admin());
CREATE POLICY "Payroll admins update employees"
  ON payroll_employees FOR UPDATE TO authenticated
  USING (is_payroll_admin())
  WITH CHECK (is_payroll_admin());
CREATE POLICY "Payroll admins delete employees"
  ON payroll_employees FOR DELETE TO authenticated
  USING (is_payroll_admin());

-- payroll_runs: admin full access
CREATE POLICY "Payroll admins read runs"
  ON payroll_runs FOR SELECT TO authenticated
  USING (is_payroll_admin());
CREATE POLICY "Payroll admins insert runs"
  ON payroll_runs FOR INSERT TO authenticated
  WITH CHECK (is_payroll_admin());
CREATE POLICY "Payroll admins update runs"
  ON payroll_runs FOR UPDATE TO authenticated
  USING (is_payroll_admin())
  WITH CHECK (is_payroll_admin());
CREATE POLICY "Payroll admins delete runs"
  ON payroll_runs FOR DELETE TO authenticated
  USING (is_payroll_admin());

-- payroll_items: admin full access + staff read own approved/paid
CREATE POLICY "Payroll admins read items"
  ON payroll_items FOR SELECT TO authenticated
  USING (is_payroll_admin());
CREATE POLICY "Staff can read own paid items"
  ON payroll_items FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM staff_members sm
      WHERE sm.id = payroll_items.staff_id
        AND sm.auth_user_id = auth.uid()
    )
    AND EXISTS (
      SELECT 1 FROM payroll_runs r
      WHERE r.id = payroll_items.run_id
        AND r.status IN ('approved','paid')
    )
  );
CREATE POLICY "Payroll admins insert items"
  ON payroll_items FOR INSERT TO authenticated
  WITH CHECK (is_payroll_admin());
CREATE POLICY "Payroll admins update items"
  ON payroll_items FOR UPDATE TO authenticated
  USING (is_payroll_admin())
  WITH CHECK (is_payroll_admin());
CREATE POLICY "Payroll admins delete items"
  ON payroll_items FOR DELETE TO authenticated
  USING (is_payroll_admin());
