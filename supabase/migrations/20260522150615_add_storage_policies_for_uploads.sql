/*
  # Add Storage Policies for Uploads Bucket

  1. Security
    - Allow authenticated users to upload files to 'uploads' bucket
    - Allow public read access to uploaded files
    - Users can only delete their own uploads (path starts with user id)
*/

-- Allow authenticated users to upload
CREATE POLICY "Authenticated users can upload files"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'uploads' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Allow public read
CREATE POLICY "Anyone can view uploaded files"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'uploads');

-- Allow users to delete own files
CREATE POLICY "Users can delete own uploads"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'uploads' AND (storage.foldername(name))[1] = auth.uid()::text);
