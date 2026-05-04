/*
  # Leave handover notes & relief officer

  Extends leave_requests to capture who will cover the requester's
  responsibilities while they are away, plus a structured handover.

  1. Schema changes on leave_requests
    - `relief_officer_id` uuid references staff_members — nominated
      colleague who will cover responsibilities.
    - `relief_accepted_at` timestamptz — when the relief officer
      accepted. NULL = still pending acceptance.
    - `relief_declined_at` timestamptz — when the relief officer
      declined. Mutually exclusive with accepted.
    - `relief_response_notes` text — optional note from the relief
      officer when accepting/declining.
    - `handover_notes` text — free-form notes describing tasks,
      contacts, deadlines, passwords-location, etc.

  2. Security
    - A new RLS policy allows the nominated relief officer to UPDATE
      the relief_accepted_at / relief_declined_at / relief_response_notes
      columns on requests where they are the relief.
    - Existing SELECT policy extended so the relief officer can also
      read requests where they are nominated.
*/

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='relief_officer_id') THEN
    ALTER TABLE leave_requests ADD COLUMN relief_officer_id uuid REFERENCES staff_members(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='relief_accepted_at') THEN
    ALTER TABLE leave_requests ADD COLUMN relief_accepted_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='relief_declined_at') THEN
    ALTER TABLE leave_requests ADD COLUMN relief_declined_at timestamptz;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='relief_response_notes') THEN
    ALTER TABLE leave_requests ADD COLUMN relief_response_notes text DEFAULT '';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='leave_requests' AND column_name='handover_notes') THEN
    ALTER TABLE leave_requests ADD COLUMN handover_notes text DEFAULT '';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS leave_requests_relief_idx ON leave_requests(relief_officer_id);

DROP POLICY IF EXISTS "Staff read own or managed leave requests" ON leave_requests;
CREATE POLICY "Staff read own or managed leave requests"
  ON leave_requests FOR SELECT TO authenticated
  USING (
    requester_user_id = auth.uid()
    OR private.admin_can('attendance','read')
    OR EXISTS (
      SELECT 1 FROM staff_members subj, staff_members mgr
      WHERE subj.id = leave_requests.staff_id
        AND subj.manager_id = mgr.id
        AND mgr.auth_user_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM staff_members relief
      WHERE relief.id = leave_requests.relief_officer_id
        AND relief.auth_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Relief officer updates acceptance" ON leave_requests;
CREATE POLICY "Relief officer updates acceptance"
  ON leave_requests FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM staff_members relief
      WHERE relief.id = leave_requests.relief_officer_id
        AND relief.auth_user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM staff_members relief
      WHERE relief.id = leave_requests.relief_officer_id
        AND relief.auth_user_id = auth.uid()
    )
  );
