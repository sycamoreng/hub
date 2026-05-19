/*
  # Add Knowledge Base Documents Table for File Uploads

  1. New Tables
    - `kb_documents`
      - `id` (uuid, primary key)
      - `user_id` (uuid, FK to auth.users) - uploader
      - `title` (text) - display name
      - `file_name` (text) - original filename
      - `file_type` (text) - file extension/mime
      - `file_size` (integer) - bytes
      - `chunk_count` (integer, default 0)
      - `status` (text, default 'processing') - processing | ready | error
      - `error_message` (text, nullable)
      - `created_at` (timestamptz)
      - `updated_at` (timestamptz)

  2. Modified Tables
    - `kb_chunks`
      - Add `document_id` column (uuid, nullable, FK to kb_documents)
      - Add index on document_id

  3. Security
    - Enable RLS on kb_documents
    - Admin-only CRUD policies using private.admin_can helper
    - Admin insert/delete policies on kb_chunks

  4. Notes
    - Existing kb_chunks structure preserved (source_table, source_id still work)
    - document_id is nullable so existing rows without a document remain valid
    - Uses 'chatbot' section for admin permission checks
*/

-- Create kb_documents table
CREATE TABLE IF NOT EXISTS kb_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  title text NOT NULL DEFAULT '',
  file_name text NOT NULL DEFAULT '',
  file_type text NOT NULL DEFAULT '',
  file_size integer NOT NULL DEFAULT 0,
  chunk_count integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'processing',
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE kb_documents ENABLE ROW LEVEL SECURITY;

-- Add document_id to kb_chunks
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'kb_chunks' AND column_name = 'document_id'
  ) THEN
    ALTER TABLE kb_chunks ADD COLUMN document_id uuid REFERENCES kb_documents(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_kb_chunks_document_id ON kb_chunks(document_id);

-- RLS policies for kb_documents (using private.admin_can helper)
CREATE POLICY "Admins can view kb documents"
  ON kb_documents FOR SELECT
  TO authenticated
  USING (private.admin_can('chatbot', 'read'));

CREATE POLICY "Admins can insert kb documents"
  ON kb_documents FOR INSERT
  TO authenticated
  WITH CHECK (private.admin_can('chatbot', 'create'));

CREATE POLICY "Admins can update kb documents"
  ON kb_documents FOR UPDATE
  TO authenticated
  USING (private.admin_can('chatbot', 'update'))
  WITH CHECK (private.admin_can('chatbot', 'update'));

CREATE POLICY "Admins can delete kb documents"
  ON kb_documents FOR DELETE
  TO authenticated
  USING (private.admin_can('chatbot', 'delete'));

-- Additional policies for kb_chunks (admin insert/delete)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'kb_chunks' AND policyname = 'Admins can insert kb chunks'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "Admins can insert kb chunks"
        ON kb_chunks FOR INSERT
        TO authenticated
        WITH CHECK (private.admin_can('chatbot', 'create'))
    $pol$;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'kb_chunks' AND policyname = 'Admins can delete kb chunks'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "Admins can delete kb chunks"
        ON kb_chunks FOR DELETE
        TO authenticated
        USING (private.admin_can('chatbot', 'delete'))
    $pol$;
  END IF;
END $$;
