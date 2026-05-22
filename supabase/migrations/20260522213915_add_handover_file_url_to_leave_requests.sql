/*
  # Add Handover File URL to Leave Requests

  1. Changes
    - Adds `handover_file_url` column (text, nullable) to `leave_requests`
    - Stores the public URL of an uploaded handover document
    - Relevant parties (relief officer, manager, admin) can access the link

  2. Security
    - No new RLS needed - existing leave_requests policies cover this column
    - File stored in public 'uploads' bucket under leave-handover/ prefix
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'leave_requests' AND column_name = 'handover_file_url'
  ) THEN
    ALTER TABLE leave_requests ADD COLUMN handover_file_url text;
  END IF;
END $$;