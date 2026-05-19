/*
  # Backfill Staff DOB and Staff ID from CSV Import

  1. Modified Tables
    - `staff_members` - sets staff_id for each matched staff member
    - `staff_private_data` - inserts date_of_birth for each matched staff member

  2. Notes
    - Matches by email (case-insensitive, trimmed)
    - Skips entries where email is empty or not found
    - Date formats in the CSV vary widely; this uses a helper function to parse them
    - Staff IDs are normalized (spaces removed)
*/

-- Temporary function to parse the varied date formats in the CSV
CREATE OR REPLACE FUNCTION private.parse_dob(raw text) RETURNS date LANGUAGE plpgsql AS $$
DECLARE
  cleaned text;
  result date;
  parts text[];
  month_num int;
  day_num int;
  year_num int;
  month_names text[] := ARRAY['january','february','march','april','may','june','july','august','september','october','november','december'];
  m text;
BEGIN
  IF raw IS NULL OR trim(raw) = '' THEN RETURN NULL; END IF;
  
  cleaned := trim(raw);
  -- Remove surrounding quotes
  cleaned := trim(both '"' from cleaned);
  -- Replace dots used as separators with spaces
  cleaned := replace(cleaned, '.', ' ');
  -- Normalize multiple spaces/commas
  cleaned := regexp_replace(cleaned, '[,\s]+', ' ', 'g');
  cleaned := trim(cleaned);
  
  -- Try standard PostgreSQL cast first
  BEGIN
    result := cleaned::date;
    RETURN result;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  
  -- Split into parts
  parts := regexp_split_to_array(cleaned, '\s+');
  
  -- Find month name, day, year from parts
  month_num := NULL;
  day_num := NULL;
  year_num := NULL;
  
  FOR i IN 1..array_length(parts, 1) LOOP
    -- Check if it's a month name
    FOR j IN 1..12 LOOP
      IF lower(parts[i]) = month_names[j] OR lower(parts[i]) = left(month_names[j], 3) THEN
        month_num := j;
        EXIT;
      END IF;
    END LOOP;
    
    -- Check if it's a number
    IF parts[i] ~ '^\d+$' THEN
      IF parts[i]::int > 31 THEN
        year_num := parts[i]::int;
      ELSIF day_num IS NULL AND parts[i]::int <= 31 THEN
        day_num := parts[i]::int;
      ELSIF year_num IS NULL THEN
        year_num := parts[i]::int;
      END IF;
    END IF;
  END LOOP;
  
  IF month_num IS NOT NULL AND day_num IS NOT NULL AND year_num IS NOT NULL THEN
    IF year_num < 100 THEN year_num := year_num + 1900; END IF;
    BEGIN
      result := make_date(year_num, month_num, day_num);
      RETURN result;
    EXCEPTION WHEN OTHERS THEN RETURN NULL;
    END;
  END IF;
  
  RETURN NULL;
END;
$$;

-- Backfill data
DO $$
DECLARE
  rec RECORD;
BEGIN
  -- Each row: staff_id, email, dob_raw
  FOR rec IN (
    SELECT * FROM (VALUES
      ('SISL-2018-001', 'tunde@sycamore.ng', 'June 21, 1989'),
      ('SISL-2019-005', 'tosin.enikuomehin@sycamore.ng', 'March 4, 1993'),
      ('SISL-2020-007', 'segun.afuwape@sycamore.ng', 'July 31, 1987'),
      ('SISL-2021-019', 'charles.akoko@sycamore.ng', 'November 30, 1981'),
      ('SISL-2020-013', 'adedeji.akinsemoyin@sycamore.ng', 'March 7, 1986'),
      ('SISL-2021-023', 'adeyemi.adeleke@sycamore.ng', 'March 20, 2000'),
      ('SISL-2021-024', 'bayo.adenaike@sycamore.ng', 'July 10, 1980'),
      ('SISL-2021-027', 'daniel.anyaegbu@sycamore.ng', 'February 28, 2000'),
      ('SISL-2021-031', 'chidubem.oyio@sycamore.ng', 'July 25, 1989'),
      ('SISL-2021-032', 'blessing.ogbonna@sycamore.ng', 'January 27, 1996'),
      ('SISL-2021-033', 'ante.esang@sycamore.ng', 'May 8, 1994'),
      ('SISL-2021-039', 'idongesit.efre@sycamore.ng', 'November 26, 1982'),
      ('SISL-2021-042', 'kingsley.makinde@sycamore.ng', 'August 12, 1995'),
      ('SISL-2021-047', 'akinboluwarin.akinwande@sycamore.ng', 'January 15, 1998'),
      ('SISL-2021-048', 'ezekiel.ariyo@sycamore.ng', 'May 20, 1993'),
      ('SISL-2021-049', 'oludipe.elijah@sycamore.ng', 'August 29, 1998'),
      ('SISL-2021-055', 'tosin.adesua@sycamore.ng', 'July 10, 1997'),
      ('SISL-2021-056', 'adetola.salami@sycamore.ng', 'June 13, 1998'),
      ('SISL-2021-057', 'pius.iniobong@sycamore.ng', 'April 6, 1998'),
      ('SISL-2022-065', 'ernest.amadi@sycamore.ng', 'April 18, 1999'),
      ('SISL-2022-063', 'oluwatobi.alpha@sycamore.ng', 'October 3, 1993'),
      ('SISL-2022-067', 'uchenna.obidike@sycamore.ng', 'June 6, 1999'),
      ('SISL-2022-064', 'oluwatomi.ayobami@sycamore.ng', 'April 29, 1994'),
      ('SISL-2022-070', 'eniolaoluwa.oluwole@sycamore.ng', 'November 27, 1997'),
      ('SISL-2022-071', 'adewunmi.awofadeju@sycamore.ng', 'April 10, 1991'),
      ('SISL-2022-078', 'faith.okpotono@sycamore.ng', 'January 3, 1993'),
      ('SISL-2022-080', 'favour.odoemelam@sycamore.ng', 'July 14, 1993'),
      ('SISL-2022-083', 'babatunde.olubummo@sycamore.ng', 'April 4, 1984'),
      ('SIML-2022-001', 'gbengamag@sycamore.ng', 'May 15, 1981'),
      ('SIML-2022-002', 'oluwakemi.ogunjimi@sycamore.ng', 'April 22, 1977'),
      ('SISL-2022-087', 'jennifer.ehizenaga@sycamore.ng', 'March 2, 1992'),
      ('SISL-2022-097', 'gift.omelazu@sycamore.ng', 'August 10, 1994'),
      ('SISL-2022-098', 'oluwafunke.ikulala@sycamore.ng', 'July 14, 1986'),
      ('SISL-2022-093', 'funmilayo.betiku@sycamore.ng', 'August 28, 1995'),
      ('SISL-2022-101', 'victoria.akudo@sycamore.ng', 'March 7, 1999'),
      ('SISL-2022-100', 'ndabai.augustina@sycamore.ng', 'August 6, 1995'),
      ('SISL-2022-102', 'yetunde.jeariogbe@sycamore.ng', 'May 26, 1993'),
      ('SISL-2022-104', 'mojisola.fagbohunlu@sycamore.ng', 'March 16, 1989'),
      ('SISL-2023-112', 'sonia.igheneki@sycamore.ng', 'October 25, 1995'),
      ('SISL-2023-113', 'gift.oruoka@sycamore.ng', 'May 1, 1992'),
      ('SISL-2023-122', 'samuel.david@sycamore.ng', 'April 5, 1997'),
      ('SISL-2023-123', 'elizabeth.oyelade@sycamore.ng', 'April 17, 1995'),
      ('SISL-2023-125', 'nelson.amos@sycamore.ng', 'February 11, 1990'),
      ('SISL-2023-126', 'francis.agim@sycamore.ng', 'August 23, 1986'),
      ('SISL-2023-127', 'adeleke.adewale@sycamore.ng', 'November 28, 1982'),
      ('SISL-2023-131', 'temitope.munza@sycamore.ng', 'July 8, 1991'),
      ('SISL-2023-132', 'aminat.shittu@sycamore.ng', 'November 23, 1989'),
      ('SISL-2023-138', 'chinye.odiaka@sycamore.ng', 'September 26, 1990'),
      ('SISL-2023-139', 'peace.nwolisa@sycamore.ng', 'October 3, 1991'),
      ('SISL-2023-142', 'bukola.taiwo@sycamore.ng', 'October 22, 1992'),
      ('SISL-2023-144', 'damilola.ogunbiyi@sycamore.ng', 'August 15, 1995'),
      ('SISL-2023-149', 'stanley.okereke@sycamore.ng', 'December 28, 1988'),
      ('SISL-2023-152', 'jumai.owolawi@sycamore.ng', 'January 31, 1997'),
      ('SISL-2023-154', 'grace.amah@sycamore.ng', 'May 18, 1989'),
      ('SISL-2023-155', 'elizabeth.maborukoje@sycamore.ng', 'November 8, 1983'),
      ('SISL-2023-156', 'ifeoma.obiegue@sycamore.ng', 'April 4, 1995'),
      ('SISL-2023-157', 'anthony.agbo@sycamore.ng', 'October 31, 1992'),
      ('SISL-2023-158', 'ololade.oni@sycamore.ng', 'January 3, 1993'),
      ('SISL-2023-159', 'taiwo.oladele@sycamore.ng', 'August 19, 1997'),
      ('SISL-2023-160', 'paul.bawa@sycamore.ng', 'June 9, 1997'),
      ('SISL-2023-161', 'john.olawale@sycamore.ng', 'January 25, 1985'),
      ('SISL-2024-164', 'maryam.umechivi@sycamore.ng', 'December 5, 2000'),
      ('SISL-2023-116', 'simisolaoluwa.oluwole@sycamore.ng', 'November 8, 1999'),
      ('SISL-2024-163', 'oluwatobi.aremu@sycamore.ng', 'January 21, 1994'),
      ('SISL-2024-167', 'olufemi.osibajo@sycamore.ng', 'January 8, 1985'),
      ('SISL-2024-170', 'adedoyin.kolade@sycamore.ng', 'November 20, 1996'),
      ('SISL-2024-165', 'saheed.babajide@sycamore.ng', 'August 31, 1982'),
      ('SISL-2024-177', 'oyekolade.oyediran@sycamore.ng', 'October 29, 1994'),
      ('SISL-2024-178', 'oluwasegun.ayannuga@sycamore.ng', 'October 28, 1983'),
      ('SISL-2024-179', 'ewere.idu@sycamore.ng', 'June 12, 1985'),
      ('SISL-2024-180', 'bamise.omotoso@sycamore.ng', 'June 2, 1991'),
      ('SISL-2024-181', 'oluwatoyin.okwudibie@sycamore.ng', 'October 1, 1987'),
      ('SISL-2024-182', 'oghenero.kunu@sycamore.ng', 'April 5, 1986'),
      ('SISL-2024-183', 'jane.obop@sycamore.ng', 'December 22, 1992'),
      ('SISL-2024-184', 'chioma.emina@sycamore.ng', 'June 27, 1988'),
      ('SISL-2024-186', 'elijah.ayemhenre@sycamore.ng', 'January 1, 1988'),
      ('SISL-2024-187', 'ololade.adebayo@sycamore.ng', 'December 4, 1982'),
      ('SISL-2024-190', 'olajinmi.ojo@sycamore.ng', 'December 30, 1991'),
      ('SISL-2024-192', 'hamed.soremekun@sycamore.ng', 'January 26, 1996'),
      ('SISL-2024-193', 'emmanuel.udoh@sycamore.ng', 'December 7, 1989'),
      ('SISL-2024-194', 'taiwo.erinle@sycamore.ng', 'December 9, 1982'),
      ('SISL-2024-195', 'tola.abiodun@sycmaore.ng', 'November 9, 1988'),
      ('SISL-2024-196', 'clinton.ukachukwu@sycamore.ng', 'January 28, 1993'),
      ('SISL-2024-197', 'rachel.afolabi@sycamore.ng', 'August 26, 2001'),
      ('SISL-2024-198', 'itohan.oboye@sycamore.ng', 'April 14, 1989'),
      ('SISL-2024-199', 'elegba.francis@sycamore.ng', 'August 1, 1983'),
      ('SISL-2024-204', 'habeeb.yakasai@sycamore.ng', 'May 25, 1995'),
      ('SISL-2024-206', 'akintunde.ogunleye@sycamore.ng', 'May 5, 1975'),
      ('SISL-2024-208', 'toluwase.olugbemiro@sycamore.ng', 'May 2, 1998'),
      ('SISL-2024-210', 'david.olaniyi@sycamore.ng', 'May 10, 2005'),
      ('SISL-2024-211', 'ekaji.ibe@sycamore.ng', 'January 3, 1999'),
      ('SISL-2024-212', 'emmanuel.adekuoroye@sycamore.ng', 'October 5, 1995'),
      ('SISL-2024-213', 'sihiyona.moshood@sycamore.ng', 'December 13, 1997'),
      ('SISL-2025-214', 'precious.chukwudi@sycamore.ng', 'May 2, 1996'),
      ('SIML-2025-003', 'uche.eguh@sycamore.ng', 'April 14, 1986'),
      ('SISL-2025-215', 'nathaniel.azamosa@sycamore.ng', 'August 8, 1988'),
      ('SIML-2025-004', 'ihuoma.okereke@sycamore.ng', 'August 22, 1985'),
      ('SISL-2025-216', 'chinedu.umeh@sycamore.ng', 'May 26, 1989'),
      ('SISL-2025-217', 'tomiloba.babajide@sycamore.ng', 'July 9, 2003'),
      ('SISL-2025-219', 'daniel.godwin@sycamore.ng', 'July 16, 1998'),
      ('SISL-2025-220', 'dasola.adumadehin@sycamore.ng', 'June 14, 1999'),
      ('SIML-2025-005', 'taiwo.oshundina@sycamore.ng', 'October 20, 1997'),
      ('SISL-2025-223', 'gloria.edwin@sycamore.ng', 'July 10, 1994'),
      ('SISL-2025-224', 'oladipupo.lawal@sycamore.ng', 'April 9, 2003'),
      ('SISL-2025-225', 'olaitan.fatomi@sycamore.ng', 'November 17, 2002'),
      ('SISL-2025-226', 'aaron.sotunde@sycamore.ng', 'November 30, 2000'),
      ('SISL-2025-227', 'emmanuel.okeibunor@sycamore.ng', 'December 18, 2000'),
      ('SISL-2025-230', 'timothy.oke@sycamore.ng', 'February 20, 1995'),
      ('SISL-2025-232', 'samuel.ogunlana@sycamore.ng', 'June 26, 1996'),
      ('SISL-2025-234', 'damilola.adeyemi@sycamore.ng', 'April 22, 1997'),
      ('SISL-2025-235', 'adeyinka.aribatise@sycamore.ng', 'December 7, 1994'),
      ('SISL-2025-236', 'olalekan.akande@sycamore.ng', 'May 24, 1988'),
      ('SISL-2025-237', 'jessica.sam@sycamore.ng', 'August 30, 1997'),
      ('SISL-2025-240', 'fehintoluwa.deleojo@sycamore.ng', 'January 31, 1997'),
      ('SISL-2025-241', 'sotonye.ogan@sycamore.ng', 'July 17, 1997'),
      ('SISL-2025-242', 'esther.fashoranti@sycamore.ng', 'March 19, 1994'),
      ('SISL-2025-243', 'david.ohanuna@sycamore.ng', 'October 6, 1993'),
      ('SISL-2025-245', 'miriam.sunday@sycamore.ng', 'May 19, 1993'),
      ('SISL-2025-246', 'pauline.banye@sycamore.ng', 'March 11, 1984'),
      ('SISL-2025-247', 'olabanji.ajiboye@sycamore.ng', 'March 16, 1995'),
      ('SISL-2025-248', 'enoch.adegbite@sycamore.ng', 'July 7, 2002'),
      ('SISL-2025-249', 'favour.michael@sycamore.ng', 'April 20, 2001'),
      ('SISL-2025-250', 'idaraobong.umoren@sycamore.ng', 'April 5, 1995'),
      ('SISL-2025-251', 'felista.ofodum@sycamore.ng', 'February 1, 2002'),
      ('SMFB-2025-001', 'emmanuel.atiati@sycamore.ng', 'January 3, 1979'),
      ('SISL-2025-252', 'ayobami.ayo-salami@sycamore.ng', 'February 12, 1997'),
      ('SISL-2025-254', 'solomon.esso@sycamore.ng', 'July 29, 1991'),
      ('SISL-2025-255', 'simisola.olunlade@sycamore.ng', 'January 21, 1996'),
      ('SISL-2023-135', 'favour.ogunmuyiwa@sycamore.ng', 'August 30, 2003'),
      ('SISL-2025-256', 'mfonobong.umouman@sycamore.ng', 'February 6, 1996'),
      ('SISL-2025-259', 'tochukwu.ndife@sycamore.ng', 'October 8, 1988'),
      ('SISL-2025-260', 'olivia.efenji@sycamore.ng', 'April 27, 1986'),
      ('SISL-2020-010', 'emmanuel.ajikobi@sycamore.ng', 'March 12, 1995'),
      ('SISL-2025-263', 'ireoluwa.akinrinola@sycamore.ng', 'December 12, 1997'),
      ('SMFB-2025-004', 'amasha.zira@sycamore.ng', 'January 18, 2000'),
      ('SMFB-2025-003', 'adamu.muhammed@sycamore.ng', 'October 10, 1997'),
      ('SISL-2025-264', 'deborah.emmanuel@sycamore.ng', 'May 23, 1998'),
      ('SISL-2025-265', 'imade.omo@sycamore.ng', 'February 17, 1996'),
      ('SISL-2025-267', 'victor.umoh@sycamore.ng', 'January 23, 1990'),
      ('SISL-2025-268', 'imaobong.essien@sycamore.ng', 'May 8, 1999'),
      ('SISL-2025-269', 'alphonsus.igaga@sycamore.ng', 'May 24, 1998'),
      ('SIML-2025-006', 'anointing.maxwell@sycamore.ng', 'August 6, 2001'),
      ('SISL-2025-272', 'muritala.kazeem@sycamore.ng', 'May 7, 1982'),
      ('SISL-2025-273', 'tracy.thomas@sycamore.ng', 'May 20, 1995'),
      ('SISL-2025-274', 'damilare.adesina@sycamore.ng', 'July 3, 1995'),
      ('SISL-2025-276', 'oluwatosin.ogunleye@sycamore.ng', 'December 16, 1993'),
      ('SISL-2026-277', 'chika.iwugoh@sycamore.ng', 'July 21, 1989'),
      ('SISL-2026-278', 'emeka.athnasis@sycamore.ng', 'May 19, 1993'),
      ('SISL-2026-279', 'chinedu.ogbonna@sycamore.ng', 'February 25, 1993'),
      ('SISL-2026-280', 'senami.hundeyin@sycamore.ng', 'February 9, 1999'),
      ('SISL-2026-281', 'ifeanyi.okpala@sycamore.ng', 'December 1, 1996'),
      ('SISL-2026-282', 'omolegho.ojeikere@sycamore.ng', 'June 28, 1993'),
      ('SISL-2026-283', 'kristabel.muo@sycamore.ng', 'March 20, 2006'),
      ('SISL-2026-284', 'emmanuel.werna@sycamore.ng', 'July 2, 1996'),
      ('SISL-2026-285', 'miriam.emmanuel@sycamore.ng', 'April 12, 2003'),
      ('SISL-2026-286', 'penuel.awoyemi@sycamore.ng', 'July 23, 2001'),
      ('SISL-2026-287', 'chinedu.njoku@sycamore.ng', 'July 20, 1988'),
      ('SISL-2026-288', 'florence.oshobu@sycamore.ng', 'May 16, 1992'),
      ('SISL-2026-289', 'stephen.oriri@sycamore.ng', 'June 12, 1993'),
      ('SISL-2026-290', 'olamide.olabintan@sycamore.ng', 'March 8, 2001'),
      ('SISL-2026-291', 'agbama.agbama@sycamore.ng', 'May 30, 1994'),
      ('SISL-2026-292', 'chioma.edeh@sycamore.ng', 'August 5, 1995'),
      ('SISL-2026-293', 'oluwaseun.oyewole@sycamore.ng', 'June 28, 2001'),
      ('SISL-2026-294', 'daniel.olabemiwo@sycamore.ng', 'August 3, 2001'),
      ('SISL-2026-295', 'grace.olugbodi@sycamore.ng', 'June 5, 1978'),
      ('SISL-2026-296', 'idowu.adekunle@sycamore.ng', 'June 22, 2002'),
      ('SISL-2026-297', 'mojisola.otusheso@sycamore.ng', 'April 29, 2000'),
      ('SISL-2026-299', 'ayomide.abiola@sycamore.ng', 'February 11, 2004'),
      ('SISL-2026-300', 'emmanuel.nwogu@sycamore.ng', 'June 25, 1996'),
      ('SISL-2026-301', 'ifeoluwatobi.adeniji@sycamore.ng', 'October 27, 1994'),
      ('SISL-2026-302', 'olamide.aboyeji@sycamore.ng', 'August 28, 2000'),
      ('SISL-2026-303', 'ibraheem.owoade@sycamore.ng', 'September 6, 1999'),
      ('SISL-2026-304', 'adewale.akinwale@sycamore.ng', 'May 17, 1982'),
      ('SISL-2026-305', 'john.ayinde@sycamore.ng', 'July 13, 1998'),
      ('SISL-2026-306', 'uzo.okpala@sycamore.ng', 'December 5, 1988'),
      ('SISL-2026-307', 'mayowa.ayodele@sycamore.ng', 'September 12, 1996'),
      ('SISL-2026-308', 'chidiebere.ohakamma@sycamore.ng', 'August 13, 1990'),
      ('SMFB-2026-008', 'abdulwahab.sadiq@sycamore.ng', 'June 10, 1984'),
      ('SMFB-2026-009', 'daniel.dickson@sycamore.ng', 'September 7, 1988'),
      ('SMFB-2026-010', 'victor.lamba@sycamore.ng', 'September 19, 1993'),
      ('SISL-2026-309', 'olamide.asenuga@sycamore.ng', 'March 24, 1998'),
      ('SISL-2026-310', 'bolaji.adeyeye@sycamore.ng', 'April 18, 1997'),
      ('SISL-2026-311', 'tunde.adeyeye@sycamore.ng', 'December 3, 1994'),
      ('SISL-2026-312', 'success.nnaji@sycamore.ng', 'September 18, 1996')
    ) AS t(staff_id, email, dob_raw)
  ) LOOP
    -- Update staff_id on staff_members
    UPDATE staff_members 
    SET staff_id = rec.staff_id
    WHERE lower(trim(email)) = lower(trim(rec.email))
      AND (staff_id IS NULL OR staff_id != rec.staff_id);

    -- Upsert DOB into staff_private_data
    INSERT INTO staff_private_data (id, date_of_birth, updated_at)
    SELECT sm.id, private.parse_dob(rec.dob_raw), now()
    FROM staff_members sm
    WHERE lower(trim(sm.email)) = lower(trim(rec.email))
    ON CONFLICT (id) DO UPDATE 
      SET date_of_birth = EXCLUDED.date_of_birth,
          updated_at = now();
  END LOOP;
END $$;

-- Clean up the helper function
DROP FUNCTION IF EXISTS private.parse_dob(text);
