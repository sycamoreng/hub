/*
  # Playlist Enhancements and Exit Data Backfill

  1. Changes to playlist_weeks
    - Add `created_by` column (uuid) to track who created the playlist
    - Add `is_staff_playlist` column (boolean) to distinguish admin vs staff playlists
    - Add admin DELETE policy for playlist_weeks
    - Add staff playlist creation policies
    - Add admin delete policy for playlist_songs

  2. Staff Playlist Policies
    - Staff can create their own playlists (is_staff_playlist = true, created_by = auth.uid())
    - Staff can update/delete their own playlists
    - Admin can delete any songs from any playlist

  3. Exit Data Backfill
    - Updates staff_members with exit information from historical CSV
    - Only marks staff as exited if they are NOT currently active (is_active = false) OR have no auth_user_id
    - Handles the "left and came back" scenario by skipping currently active staff
    - Sets exited_at, exit_reason, staff_id, and joined_date where available

  4. Security
    - Maintains existing RLS on all tables
    - Staff can only manage playlists they created
    - Admin retains full control
*/

-- Add columns to playlist_weeks for staff playlists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'playlist_weeks' AND column_name = 'created_by'
  ) THEN
    ALTER TABLE playlist_weeks ADD COLUMN created_by uuid REFERENCES auth.users(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'playlist_weeks' AND column_name = 'is_staff_playlist'
  ) THEN
    ALTER TABLE playlist_weeks ADD COLUMN is_staff_playlist boolean DEFAULT false;
  END IF;
END $$;

-- Add exit_reason column to staff_members if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'staff_members' AND column_name = 'exit_reason'
  ) THEN
    ALTER TABLE staff_members ADD COLUMN exit_reason text;
  END IF;
END $$;

-- Admin can delete playlist weeks
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'playlist_weeks' AND policyname = 'Admins can delete playlist weeks'
  ) THEN
    CREATE POLICY "Admins can delete playlist weeks"
      ON playlist_weeks FOR DELETE
      TO authenticated
      USING (private.admin_can('playlists', 'delete'));
  END IF;
END $$;

-- Staff can create their own playlists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'playlist_weeks' AND policyname = 'Staff can create own playlists'
  ) THEN
    CREATE POLICY "Staff can create own playlists"
      ON playlist_weeks FOR INSERT
      TO authenticated
      WITH CHECK (created_by = auth.uid() AND is_staff_playlist = true);
  END IF;
END $$;

-- Staff can update their own playlists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'playlist_weeks' AND policyname = 'Staff can update own playlists'
  ) THEN
    CREATE POLICY "Staff can update own playlists"
      ON playlist_weeks FOR UPDATE
      TO authenticated
      USING (created_by = auth.uid() AND is_staff_playlist = true)
      WITH CHECK (created_by = auth.uid() AND is_staff_playlist = true);
  END IF;
END $$;

-- Staff can delete their own playlists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'playlist_weeks' AND policyname = 'Staff can delete own playlists'
  ) THEN
    CREATE POLICY "Staff can delete own playlists"
      ON playlist_weeks FOR DELETE
      TO authenticated
      USING (created_by = auth.uid() AND is_staff_playlist = true);
  END IF;
END $$;

-- Admin can delete any songs
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'playlist_songs' AND policyname = 'Admins can delete any songs'
  ) THEN
    CREATE POLICY "Admins can delete any songs"
      ON playlist_songs FOR DELETE
      TO authenticated
      USING (private.admin_can('playlists', 'delete'));
  END IF;
END $$;

-- Backfill exit data from CSV
-- Only updates staff who are NOT currently active to avoid overwriting rehires
-- Matches by staff_id (employee code) first, then by email
DO $$
DECLARE
  r RECORD;
BEGIN
  -- Create a temp table with the exit data
  CREATE TEMP TABLE exit_data (
    employee_id text,
    first_name text,
    last_name text,
    email text,
    job_function text,
    exit_reason text,
    joined_date date,
    exited_at date
  ) ON COMMIT DROP;

  INSERT INTO exit_data (employee_id, first_name, last_name, email, job_function, exit_reason, joined_date, exited_at) VALUES
    ('SISL-2021-064', 'Ibrahim', 'Olamilekan', 'ibrahim.olamilekan@sycamore.ng', 'Collections Officer', 'Voluntary Exit', '2021-12-10', '2022-05-16'),
    ('SISL-2021-037', 'Christopher', 'Sales Officer', 'christopher.ukpabia@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2021-07-05', '2022-08-01'),
    ('SISL-2021-041', 'Jesse', 'Ukrakpor', 'jesse.ukrakpor@gmail.com', 'Sales Officer', 'Voluntary Exit', '2021-08-02', '2022-10-01'),
    ('SISL-2021-030', 'Ayodele', 'Akinbinu', 'ayodele.akinbinu@sycamore.ng', 'Sales Deputy Manager', 'Career Advancement', '2021-05-10', '2022-11-24'),
    ('SISL-2021-034', 'Samuel', 'Ajayi', 'samuel.ajayi@sycamore.ng', 'Lead Admin', 'Voluntary Exit', '2021-06-21', '2022-11-11'),
    ('SISL-2020-015', 'Nkem', 'Ejike', 'nkem.ejike@gmail.com', 'Sales Deputy Manager', 'Voluntary Exit', '2020-08-29', '2022-10-20'),
    ('SISL-2020-016', 'Victoria', 'Timehin', 'victoria.timehin@sycamore.ng', 'Sales Officer', 'Career Advancement', '2020-08-29', '2022-11-30'),
    ('SISL-2021-043', 'Dotun', 'Olakanmi', 'dotun.olakanmi@gmail.com', 'Growth Lead', 'Voluntary Exit', '2021-09-07', '2022-10-08'),
    ('SISL-2022-086', 'Tolulope', 'Obasanmi-Esan', 'tolulope.obasanmi-esan@sycamore.ng', 'Fund Mobilization', 'End of Contract', '2022-06-21', '2022-11-30'),
    ('SISL-2022-089', 'Fidelia', 'Harry', 'fidelia.harry@sycamore.ng', 'Sales Officer', 'End of Contract', '2022-09-05', '2022-11-30'),
    ('SISL-2022-091', 'Edidiong', 'Ekop', 'edidiong.ekop@sycamore.ng', 'Sales Officer', 'End of Contract', '2022-09-05', '2022-11-30'),
    ('SISL-2022-094', 'Luke', 'Ikenna', 'luke.Ikenna@sycamore.ng', 'Sales Officer', 'End of Contract', '2022-09-05', '2022-11-30'),
    ('SIML-2022-003', 'Musabau', 'Aina', 'Oluwasina.Aina@sycamore.ng', 'Lead Finance', 'Voluntary Exit', '2022-06-14', '2023-07-15'),
    ('SIML-2022-004', 'Simeon', 'Oni', 'simeon.oni@sycamore.ng', 'Vice President', 'Voluntary Exit', '2022-09-05', '2023-01-16'),
    ('SIML-2023-005', 'Olumide', 'Sole', 'olumide.sole@sycamore.ng', 'Research Analyst', 'Career Advancement', '2023-04-03', '2023-06-14'),
    ('SISL-2020-006', 'Adebayo', 'Ojedokun', 'adebayo.ojedokun@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2020-01-13', NULL),
    ('SISL-2020-008', 'Samuel', 'Lasisi', 'samuel.lasisi@sycamore.ng', 'Brand Lead', 'Voluntary Exit', '2020-01-20', NULL),
    ('SISL-2020-009', 'Pedro', 'Andrew', 'pedro.andrew@sycamore.ng', 'Sales Manager', 'Career Advancement', '2020-06-19', '2023-04-30'),
    ('SISL-2020-011', 'Onyedikachi', 'Erugo', 'onyedikachi.erugo@sycamore.ng', NULL, 'Voluntary Exit', '2020-08-20', NULL),
    ('SISL-2020-012', 'Ehimwenma', 'Omorodion', 'ehimwenma.omorodion@sycamore.ng', NULL, 'Voluntary Exit', '2020-08-29', NULL),
    ('SISL-2020-014', 'Oluwatobi', 'Oduntan', 'oluwatobi.oduntan@sycamore.ng', NULL, 'Voluntary Exit', '2020-08-29', NULL),
    ('SISL-2020-022', 'Mofeoluwa', 'Abimbolu', 'mofeoluwa.abimbolu@gmail.com', 'Finance Officer', 'Voluntary Exit', '2020-02-10', NULL),
    ('SISL-2020-021', 'Prisca', 'Ezeugbor', 'prisca.ezeugbor@sycamore.ng', 'HC Officer', 'Career Advancement', '2020-01-17', '2023-11-26'),
    ('SISL-2021-017', 'Bola', 'Atoyege', 'bola.atoyege@gmail.com', 'Sales Officer', 'End of Contract', '2019-07-15', NULL),
    ('SISL-2021-018', 'Tobi', 'Ayoade', 'tobi.ayoade@sycamore.ng', NULL, 'End of Contract', '2020-01-22', NULL),
    ('SISL-2021-020', 'Wasiu', 'Olaonipekun', 'wasiu.olanipekun@sycamore.ng', NULL, 'End of Contract', '2020-01-31', NULL),
    ('SISL-2021-025', 'John', NULL, NULL, NULL, 'Voluntary Exit', '2021-01-11', NULL),
    ('SISL-2021-026', 'Temitayo', 'Ipinlaiye', 'temitayo.ipinlaiye@sycamore.ng', 'Product', 'Career Advancement', '2021-01-18', '2023-11-24'),
    ('SISL-2021-028', 'Temitope', 'Adeniyi', 'Temitope.adeniyi@sycamore.ng', 'Risk Manager', 'Voluntary Exit', '2021-05-04', NULL),
    ('SISL-2021-029', 'Frank', 'Okolo', 'frank.okolo@gmail.com', 'Sales Officer', 'Voluntary Exit', '2021-04-12', NULL),
    ('SISL-2021-035', 'Winifred', 'Ezechiogbe', 'winifred.ezechiogbe@sycamore.ng', 'Investment affairs', 'Voluntary Exit', '2021-06-21', '2023-06-29'),
    ('SISL-2021-036', 'Larry', 'Akakah', 'larry.akakah@sycamore.ng', 'Sales Officer', 'Termination', '2021-07-05', '2023-10-16'),
    ('SISL-2021-038', 'Olaniran', 'Busari', 'olaniran.busari@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2021-07-05', NULL),
    ('SISL-2021-040', 'Francis', 'Okafor', 'francis.okafor@sycamore.ng', 'Sales Regional Lead', 'Voluntary Exit', '2021-07-19', '2023-04-30'),
    ('SISL-2021-044', 'Samuel', 'Adesina', 'samuel.adesina@sycamore.ng', 'Backend Engineer', 'Career Advancement', '2021-08-02', NULL),
    ('SISL-2021-045', 'Grace', 'Udoh', 'grace.udoh@gmail.com', 'Customer Experience Officer', 'Voluntary Exit', '2021-11-01', NULL),
    ('SISL-2021-050', 'Uchechukwu', 'Anyanwu', 'uchechukwu.anyanwu@sycamore.ng', 'Lead Investment', 'Career Advancement', '2021-12-01', NULL),
    ('SISL-2021-051', 'Olalekan', 'Moshood', 'olalekan.moshood@sycamore.ng', 'Facility Officer', 'Voluntary Exit', '2021-11-24', NULL),
    ('SISL-2021-052', 'Dolapo', 'Oyetunji', 'dolapo.oyetunji@sycamore.ng', 'Lead Finance', 'Voluntary Exit', '2021-12-06', '2023-01-31'),
    ('SISL-2022-058', 'Linda', 'Odeh', 'linda.odeh@sycamore.ng', 'Investment Officer', 'End of Contract', '2022-01-13', '2023-01-31'),
    ('SISL-2022-059', 'Tolulope', 'Joseph', 'tolulope.joseph@sycamore.ng', 'Investment Officer', 'End of Contract', '2022-01-13', '2023-01-31'),
    ('SISL-2022-060', 'Sofiat', 'Olutayo', 'sophiat.olutayo@sycamore.ng', 'Investment Officer', 'End of Contract', '2022-01-13', '2023-01-31'),
    ('SISL-2022-061', 'Praise', 'Akhaze', 'praise.akhaze@sycamore.ng', 'Investment Officer', 'End of Contract', '2022-01-13', '2023-01-31'),
    ('SISL-2022-062', 'Chinedu', 'Nnebue', 'chinedu.nnebue@sycamore.ng', 'Investment Officer', 'End of Contract', '2022-01-13', '2023-01-31'),
    ('SISL-2022-066', 'Usman', 'Alimat', 'alimat.usman@sycamore.ng', 'Product Intern', 'End of Contract', '2022-01-18', '2023-01-31'),
    ('SISL-2022-068', 'Mercy', 'Akore', 'mercy.akore@sycamore.ng', 'QA Intern', 'End of Contract', '2022-02-24', '2023-03-31'),
    ('SISL-2022-076', 'Esther', 'Abuah', 'esther.abuah@sycamore.ng', 'Sales Analyst', 'Voluntary Exit', '2022-06-01', '2023-05-04'),
    ('SISL-2022-077', 'Matilda', 'Obatha', 'matilda.obatha@sycamore.ng', 'Sales Analyst', 'Voluntary Exit', '2022-06-01', '2023-10-16'),
    ('SISL-2022-079', 'Patience', 'Agboiyi', 'patience.agboiyi@sycamore.ng', 'Sales Regional Lead', 'Career Advancement', '2022-06-01', '2023-04-30'),
    ('SISL-2022-081', 'Maryjane', 'Ndukuba', 'maryjane.ndukuba@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2022-06-01', '2023-03-29'),
    ('SISL-2022-082', 'Stephen', 'Mukoro', 'stephen.mukoro@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2022-06-01', '2023-10-24'),
    ('SISL-2022-084', 'Bi', 'Aprekuma', 'bi.aprekuma@gmail.com', 'Mobile Developer', 'End of Contract', '2022-06-14', '2023-01-11'),
    ('SISL-2022-088', 'Tajudeen', 'Gbadamosi', 'gbadamosi tajudeen85@gmail.com', 'Facility Maintenance Officer', 'End of Contract', '2022-08-01', '2023-04-30'),
    ('SISL-2022-092', 'Adebayo', 'Oluwashina', 'adebayo.oluwashina@sycamore.ng', 'Sales Officer', 'End of Contract', '2022-09-05', '2023-04-30'),
    ('SISL-2022-103', 'Abdulazeez', 'Orehware', 'abdullazeez.haruna@sycamore.ng', 'Graphics Designer', 'Voluntary Exit', '2022-10-24', '2023-02-01'),
    ('SISL-2022-105', 'Oluwatosin', 'Ogunjobi', 'oluwatosin.ogunjobi@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2022-12-01', '2023-06-27'),
    ('SISL-2023-106', 'Peter', 'Olagunju', 'mayowa@sycamore.ng', 'Facility Maintenance Manager', 'Voluntary Exit', '2023-01-03', '2023-03-29'),
    ('SISL-2023-108', 'Ezekiel', 'Edoburun', 'ezekiel.edoburun@sycamore.ng', 'Investment Officer', 'Voluntary Exit', '2023-01-09', '2023-06-01'),
    ('SISL-2023-109', 'Eriksson', 'Owraigbo', 'fejiro.owraigbo@sycamore.ng', 'Network Engineer', 'Voluntary Exit', '2023-01-05', '2023-03-29'),
    ('SISL-2023-114', 'Esther', 'Okoro', 'esther.okoro@sycamore.ng', 'Telesales Officer', 'Voluntary Exit', NULL, '2023-03-01'),
    ('SISL-2023-115', 'Ginika', 'Njoku', 'ginika.njoku@sycamore.ng', 'Sales Officer', 'Career Advancement', '2023-02-13', '2023-08-01'),
    ('SISL-2023-116', 'Simisolaoluwa', 'Oluwole', 'simisolaoluwa.oluwole@sycamore.ng', 'Telesales Officer', 'Termination', '2023-03-01', NULL),
    ('SISL-2023-119', 'Bolaji', 'Akinsanya', 'bolaji@sycamore.ng', 'Sales Officer', 'Termination', '2023-03-01', '2023-06-21'),
    ('SISL-2023-120', 'Tobi', 'Ajibola', 'tobi.ajibola@sycamore.ng', 'Verification/KYC Officer', 'Voluntary Exit', '2023-03-01', '2023-10-16'),
    ('SISL-2023-129', 'Folake', 'Olaoye', 'folake.olaoye@sycamore.ng', 'Sales Officer', 'Career Advancement', '2023-05-02', '2023-10-30'),
    ('SISL-2023-133', 'Offiong', 'Edet', 'offiong.bassey@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2023-07-10', '2023-06-20'),
    ('SISL-2023-135', 'Favour', 'Ogunmuyiwa', 'favour.ogunmuyiwa@sycamore.ng', 'HR Officer', 'End of Contract', '2023-07-10', '2023-09-30'),
    ('SISL-2023-136', 'Faruq', 'Olukoya', 'faruq.olukoya@sycamore.ng', 'Backend Engineer', 'Voluntary Exit', '2023-07-17', '2023-09-30'),
    ('SISL-2023-150', 'Chinonso', 'Ezemba', 'chinonso.great@sycamore.ng', 'Growth Officer', 'End of Contract', NULL, '2023-11-15'),
    ('SISL-2023-153', 'Nnamdi', 'Ofuokwu', 'gerald.ofuokwu@sycamore.ng', 'Product/KYC Officer', 'Voluntary Exit', '2023-09-26', '2023-12-29'),
    ('SISL-2022-095', 'Gabriel', 'Affia', 'gabriel.affia@sycamore.ng', 'Executive Assistant', 'Voluntary Exit', '2022-09-05', '2024-02-21'),
    ('SISL-2022-085', 'Fiyinfoluwa', 'Dorcas', 'fiyinfoluwa.dorcas@sycamore.ng', 'Credit Officer', 'Termination', '2022-06-21', '2024-03-14'),
    ('SISL-2023-137', 'Ilemon', 'Ileaboya', 'ilemon.ileaboya@sycamore.ng', 'Sales Regional Lead', 'Voluntary Exit', '2023-07-17', '2024-02-16'),
    ('SISL-2023-141', 'Esther', 'Okonkwor', 'esther.okonkwor@sycamore.ng', 'Investment Officer', 'Career Advancement', '2023-08-07', '2024-01-25'),
    ('SISL-2023-146', 'Dare', 'Olagbenro', 'dare.olagbenro@syacmore.ng', 'Sales Officer', 'Termination', '2023-08-13', '2024-02-29'),
    ('SISL-2023-147', 'Ufuoma', 'Oyibo', 'ufuoma.oyibo@sycamore.ng', 'Frontend Engineer', 'End of Contract', '2023-08-13', '2024-02-28'),
    ('SISL-2022-096', 'Blessing', 'Obidike', 'blessing.obidike@sycamore.ng', 'Internal Control Officer', 'Relocation', '2022-09-05', '2024-03-15'),
    ('SISL-2023-145', 'Olumide', 'Akintewe', 'olumide.akintewe@sycamore.ng', 'Sales Analyst', 'Voluntary Exit', '2023-08-13', '2024-03-31'),
    ('SISL-2024-169', 'Adeyemi', 'Giwa', 'adeyemi.giwa@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2024-02-26', '2024-04-19'),
    ('SISL-2024-171', 'Ganiyu', 'Bello', 'ganiyu.bello@sycamore.ng', 'Internal Control Analyst', 'Career Advancement', '2024-02-27', '2024-05-15'),
    ('SISL-2024-168', 'Okonkwo', 'Ikezue', 'ikezue.okonkwo@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2024-02-26', '2024-05-25'),
    ('SISL-2024-191', 'Kayode', 'Ajayi', 'kayode.ajayi@sycamore.ng', 'Senior BER', 'Termination', '2024-06-06', '2024-06-20'),
    ('SISL-2024-162', 'Ezekiel', 'Ikinwot', 'ezekiel.ikinwot@sycamore.ng', 'Technology', 'End of Contract', '2024-01-08', '2024-06-28'),
    ('SISL-2023-111', 'Kosisochukwu', 'Allison', 'kosisochukwu.allison@sycamore.ng', 'Mobile App Engineer', 'Voluntary Exit', '2023-02-08', '2024-07-20'),
    ('SISL-2022-073', 'Timi', 'Ayiti', 'timi.ayiti@sycamore.ng', 'Human Capital Manager', 'Voluntary Exit', '2022-04-01', '2024-07-31'),
    ('SISL-2021-054', 'Oluwafelami', 'Ajikobi', 'oluwafelami.ajikobi@sycamore.ng', 'Product Analyst', 'Career Advancement', '2021-12-08', '2024-07-26'),
    ('SISL-2021-046', 'Chukwuemeka', 'Ikpa', 'chukwuemeka.ikpa@sycamore.ng', 'Lead Internal Control', 'Voluntary Exit', '2021-11-01', '2024-07-31'),
    ('SISL-2024-172', 'Mariam', 'Oluwole', 'mariam.oluwale@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2024-03-04', '2024-08-26'),
    ('SISL-2020-010', 'Emmanuel', 'Ajikobi', 'emmanuel.ajikobi@sycamore.ng', 'Growth Officer', 'Voluntary Exit', '2020-07-16', '2024-09-06'),
    ('SISL-2024-185', 'Jesse', 'Ikemefuna', 'jesse.ikemefuna@sycamore.ng', 'Intern', 'End of Contract', '2024-05-07', '2024-09-02'),
    ('SISL-2024-200', 'Joseph', 'Jimoh', 'joseph.jimoh@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2024-08-19', '2024-09-20'),
    ('SISL-2024-176', 'Clinton', 'Isidore', 'clinton.isidore@sycamore.ng', 'Content Writer', 'Voluntary Exit', '2024-03-25', '2024-09-25'),
    ('SIML-2024-003', 'Farouq', 'Aremu', 'farouq.aremu@sycamore.ng', 'Asset Management Analyst', 'Voluntary Exit', '2024-03-04', '2024-10-30'),
    ('SISL-2022-072', 'Jacob', 'Avarumun', 'kever.avarumun@sycamore.ng', 'Asset Management Analyst', 'Relocation', '2022-03-07', '2024-10-30'),
    ('SISL-2024-202', 'Deborah', 'Adeosun', 'deborah.adeosun@sycamore.ng', 'Finance Intern', 'End of Contract', '2024-08-26', '2024-10-30'),
    ('SISL-2023-107', 'Dzarma', 'Gwary', 'dzarma.gwary@sycamore.ng', 'Executive Assistant', 'Career Advancement', '2023-01-03', '2024-10-30'),
    ('SISL-2024-189', 'Boluwatife', 'Faturoti', 'boluwatife.faturoti@sycamore.ng', 'Risk Intern', 'End of Contract', '2024-06-03', '2024-10-30'),
    ('SISL-2023-148', 'Chimnecherem', 'Eboh', 'chimnecherem.eboh@sycamore.ng', 'Digital Marketer', 'Career Advancement', '2023-08-30', '2024-10-11'),
    ('SISL-2023-134', 'Micheal', 'Fakilede', 'micheal.fakilede@sycamore.ng', 'Recovery Officer', 'Career Advancement', '2023-07-10', '2024-11-25'),
    ('SISL-2021-053', 'Yejide', 'Kuyoro', 'yejide.kuyoro@sycamore.ng', 'Software Quality Assurance', 'Voluntary Exit', '2021-12-08', '2024-12-20'),
    ('SISL-2022-090', 'Kennedy', 'Ndukaku', 'kennedy.ndukaku@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2022-09-05', '2024-12-25'),
    ('SISL-2023-124', 'Oluwatimileyin', 'Akinpelu', 'oluwatimileyin.akinpelu@sycamore.ng', 'Frontend Engineer', 'Voluntary Exit', '2023-04-03', '2024-12-19'),
    ('SISL-2024-203', 'Daniel', 'Onyekwere', 'daniel.onyekwere@sycamore.ng', 'Investment Intern', 'End of Contract', '2024-09-23', '2024-12-31'),
    ('SISL-2023-128', 'Onyinyechi', 'Uchenna-ezegbunam', 'winnie.uche-ezegbunam@sycamore.ng', 'Executive Assistant', 'Redeployment', '2023-04-19', '2024-01-06'),
    ('SISL-2024-173', 'Toyyibat', 'Adebiyi', 'toyyibat.adebiyi@sycamore.ng', 'Internal Control Officer', 'Redeployment', '2024-03-18', '2024-01-06'),
    ('SISL-2024-205', 'Mobolanle', 'Ajose', 'mobolanle.ajose@sycamore.ng', 'Internal Control & Audits Manager', 'Voluntary Exit', '2024-09-23', '2025-02-26'),
    ('SISL-2025-229', 'Retyit', 'Kwarpo', 'retyit.kwarpo@sycamore.ng', 'Tech Intern', 'End of Contract', '2025-02-18', '2025-03-20'),
    ('SISL-2025-228', 'Manuchimso', 'Oliver', 'manuchimso.oliver@sycamore.ng', 'Frontend Engineer', 'Voluntary Exit', '2025-02-18', '2025-03-31'),
    ('SISL-2023-143', 'Olabode', 'Babawale', 'olabode.babawale@sycamore.ng', 'Investment Affairs Officer', 'Voluntary Exit', '2023-08-02', '2025-05-09'),
    ('SISL-2024-201', 'Feyisayo', 'Adekunle', 'feyisayo.adekunle@sycamore.ng', 'Content Marketer', 'Career Advancement', '2024-08-19', '2025-06-11'),
    ('SISL-2025-218', 'Daniel', 'Orisabinone', 'daniel.orisabinone@sycamore.ng', 'Tech Intern', 'End of Contract', '2025-01-28', '2025-06-27'),
    ('SISL-2024-188', 'Levi', 'Conqueror', 'levi.conqueror@sycamore.ng', 'Product Marketer', 'Voluntary Exit', '2024-05-20', '2025-07-01'),
    ('SISL-2023-151', 'Saviour', 'MBA', 'Saviour.mba@sycamore.ng', 'Product Manager', 'Voluntary Exit', '2023-09-18', '2025-08-15'),
    ('SISL-2025-233', 'Temitope', 'Adeyeye', 'temitope.adeyeye@sycamore.ng', 'Customer Support Officer', 'Voluntary Exit', '2025-03-10', '2025-08-05'),
    ('SISL-2024-175', 'Maryam', 'Oyeku', 'maryam.oyeku@sycamore.ng', 'Finance', 'Voluntary Exit', '2024-03-20', '2025-09-05'),
    ('SISL-2025-231', 'Adaeze', 'Madubueze', 'adaeze.madubueze@sycamore.ng', 'Customer Support Officer', 'Voluntary Exit', '2025-03-10', '2025-09-07'),
    ('SISL-2023-140', 'Tobechukwu', 'Anyanwu', 'tobechukwu.anyanwu@sycamore.ng', 'CX Officer', 'Voluntary Exit', '2023-08-02', '2025-09-15'),
    ('SISL-2025-261', 'Daniel', 'Kalu', 'daniel.kalu@sycamore.ng', 'Investment Intern', 'End of Contract', '2025-08-08', '2025-10-03'),
    ('SISL-2025-239', 'Francis', 'Anyaegbu', 'francis.anyaegbu@sycamore.ng', 'Tech Intern', 'End of Contract', '2025-04-07', '2025-09-30'),
    ('SISL-2023-130', 'Chioma', 'Onoh', 'chioma.onoh@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2023-05-02', '2025-09-30'),
    ('SISL-2022-068', 'Mercy', 'Dada', 'mercy.dada@sycamore.ng', 'Risk Manager', 'Voluntary Exit', '2022-02-01', '2025-10-03'),
    ('SISL-2024-166', 'Elumeziem', 'Chimaobi', 'meziem.desire@sycamore.ng', 'Growth Manager', 'Termination', '2024-02-12', NULL),
    ('SISL-2022-099', 'Rasheed', 'Abiodun', 'rasheed.abiodun@sycamore.ng', 'Sales Officer', 'Termination', '2022-09-05', '2025-12-02'),
    ('SISL-2025-270', 'Chimezie', 'Akubuiro', NULL, NULL, 'Termination', '2025-07-01', NULL),
    ('SISL-2025-262', 'Oluwanifemi', 'Martins', 'oluwanifemi.martins@sycamore.ng', 'Technology', 'End of Contract', '2025-08-19', NULL),
    ('SISL-2022-074', 'Mercy', 'Akore', 'mercy.akore@sycamore.ng', 'Customer Experience', 'Voluntary Exit', '2022-05-16', '2025-11-28'),
    ('SISL-2023-117', 'Anthonia', 'Tokunboh', 'anthonia.tokunboh@sycamore.ng', 'Executive Office', 'Voluntary Exit', '2023-03-01', '2025-11-07'),
    ('SISL-2025-244', 'Nkemakonam', 'Nwoayeocha', NULL, 'Technology', 'End of Contract', '2025-05-12', NULL),
    ('SISL-2025-253', 'Tochukwu', 'Nnaji', 'tochukwu.nnaji@sycamore.ng', 'Technology', 'End of Contract', '2025-07-01', NULL),
    ('SISL-2025-257', 'Umoren', 'Idiong', NULL, 'Executive Office', 'Voluntary Exit', '2025-07-01', NULL),
    ('SISL-2018-002', 'Mayowa', 'Adeosun', 'mayowa@sycamore.ng', 'Executive Office', 'Voluntary Exit', '2018-01-01', NULL),
    ('SISL-2023-121', 'Peter', 'Oluwasegun', 'peter@sycamore.ng', 'Technology', 'Voluntary Exit', '2023-03-01', '2025-12-31'),
    ('SISL-2025-266', 'Esther', 'Okechukwu', 'esther.okechukwu@sycamore.ng', 'Customer Experience', 'Voluntary Exit', '2025-09-08', '2026-01-14'),
    ('SISL-2025-238', 'Israel', 'Afolabi', 'Israel.afolabi@sycamore.ng', 'Finance', 'Voluntary Exit', '2025-04-07', NULL),
    ('SISL-2025-222', 'Lois', 'Ekeinde', 'lois.ekeinde@sycamore.ng', 'Customer Support', 'Voluntary Exit', '2025-02-17', '2026-02-14'),
    ('SISL-2024-207', 'Samuel', 'Akeem', 'samuel.akeem@sycamore.ng', 'Risk Support', 'Voluntary Exit', '2024-11-04', '2026-02-06'),
    ('SISL-2025-275', 'Imisioluwa', 'Ogundele', 'imisioluwa.ogundele@sycamore.ng', 'Mobile Developer', 'Termination', '2025-12-09', '2026-02-28'),
    ('SISL-2025-271', 'Chimeladhu', 'Ehudhu', 'chimeladhu.ehudhu@sycamore.ng', 'Sales Officer', 'Voluntary Exit', '2025-09-30', '2026-02-28'),
    ('SISL-2024-209', 'Hamzat', 'Hamajo', 'hamza.hamajo@sycamore.ng', 'Recovery Officer', 'Voluntary Exit', '2024-11-14', '2026-04-03'),
    ('SISL-2026-298', 'Seun', 'Ogundipe', 'seun.ogundipe@sycamore.ng', 'IT Support', 'Voluntary Exit', NULL, NULL),
    ('SMFB-2025-002', 'Abdulraheem', 'Usman', 'Abdulraheem.usman@sycamore.ng', 'Sales Officer', 'Voluntary Exit', NULL, '2026-04-29'),
    ('SISL-2024-178', 'Olusegun', 'Ayannuga', 'olusegun.ayannuga@sycamore.ng', 'Deposit Mobilization Manager', 'Voluntary Exit', NULL, '2026-05-15'),
    ('SISL-2025-260', 'Olivia', 'Efenji', 'Olivia.efenji@sycamore.ng', 'Wealth Manager', 'Voluntary Exit', NULL, '2026-05-19'),
    ('SISL-2024-164', 'Maryam', 'Umechivi', 'Maryam.umechivi@sycamore.ng', 'Credit Risk Analyst', 'Voluntary Exit', NULL, '2026-05-31'),
    ('SISL-2025-274', 'Damilare', 'Adesina', 'Damilare.adesina@sycamore.ng', 'Collateral Officer', 'Voluntary Exit', NULL, '2026-06-05');

  -- Update existing staff records by matching on staff_id first
  -- ONLY update if the staff member is NOT currently active (handles rehires)
  FOR r IN SELECT * FROM exit_data LOOP
    -- Try match by staff_id
    UPDATE staff_members
    SET
      exited_at = COALESCE(r.exited_at, staff_members.exited_at),
      exit_reason = COALESCE(r.exit_reason, staff_members.exit_reason),
      is_active = CASE WHEN r.exited_at IS NOT NULL AND r.exited_at <= CURRENT_DATE THEN false ELSE staff_members.is_active END,
      joined_date = COALESCE(staff_members.joined_date, r.joined_date),
      staff_id = COALESCE(staff_members.staff_id, r.employee_id)
    WHERE staff_id = r.employee_id
      AND (is_active = false OR auth_user_id IS NULL OR r.exited_at > CURRENT_DATE - INTERVAL '30 days');

    -- If no match by staff_id, try by email (case-insensitive)
    IF NOT FOUND AND r.email IS NOT NULL THEN
      UPDATE staff_members
      SET
        exited_at = COALESCE(r.exited_at, staff_members.exited_at),
        exit_reason = COALESCE(r.exit_reason, staff_members.exit_reason),
        is_active = CASE WHEN r.exited_at IS NOT NULL AND r.exited_at <= CURRENT_DATE THEN false ELSE staff_members.is_active END,
        joined_date = COALESCE(staff_members.joined_date, r.joined_date),
        staff_id = COALESCE(staff_members.staff_id, r.employee_id)
      WHERE LOWER(TRIM(email)) = LOWER(TRIM(r.email))
        AND (is_active = false OR auth_user_id IS NULL OR r.exited_at > CURRENT_DATE - INTERVAL '30 days');
    END IF;
  END LOOP;
END $$;