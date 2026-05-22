/*
  # Insert Exited Staff Members (v2)

  1. Purpose
    - Adds ~139 historical exited employees to staff_members for records and analytics
    - Each mapped to appropriate department by job function
    - All marked inactive with exit dates/reasons (except 2 future-dated)
    - Uses placeholder emails for 4 records missing email data

  2. Approach
    - INSERT ... SELECT with NOT EXISTS check on staff_id to skip duplicates
    - Employees with no email get a unique placeholder: exited.<staff_id>@placeholder.local
    - SISL-2022-068 already exists (Mercy Akore QA) - use SISL-2022-074 for the second Mercy Akore
    - Does NOT mark SISL-2025-274 or SISL-2024-164 as inactive (future exits)
*/

DO $$
DECLARE
  dept_sales uuid := 'bfb4ae97-d261-4b3e-a90b-30647ac18970';
  dept_investment uuid := 'c1ce4a5d-44ef-47a7-98b3-72723be3b9b0';
  dept_tech uuid := 'f025ab8d-af61-46ef-a396-7b5214769dd2';
  dept_finance uuid := 'b0b319ef-e03e-4bc4-ad4f-86e5b36d3451';
  dept_risk uuid := '4be1d0ae-5900-4dff-bc0b-a82f42e3d912';
  dept_cx uuid := 'c2549413-eb37-4a9f-a8e8-a700cd51b27a';
  dept_hc uuid := 'e4c70718-1791-40ea-9e38-b9aa63d08f05';
  dept_marketing uuid := '26d6a89e-574e-43a4-8253-c6168362fc0d';
  dept_product uuid := 'efe6157a-ff99-42cb-a96b-3d5859adf877';
  dept_internal_ctrl uuid := 'edc285df-54c1-4a66-9c33-0d4a8df9c770';
  dept_exec uuid := '77e00385-0cde-481a-af38-764b78c969a1';
  dept_remedial uuid := 'afaeacf4-6176-4013-bd77-d36f7627aa95';
  dept_sam uuid := 'c0736dc3-bf6c-4eb4-baab-28c7a437f45c';
BEGIN
  INSERT INTO staff_members (staff_id, full_name, email, role, department_id, joined_date, exited_at, exit_reason, is_active, directory_visible)
  SELECT v.staff_id, v.full_name, v.email, v.role, v.department_id, v.joined_date, v.exited_at, v.exit_reason, v.is_active, false
  FROM (VALUES
    ('SISL-2021-064', 'Ibrahim Olamilekan', 'ibrahim.olamilekan@sycamore.ng', 'Collections Officer', dept_remedial, '2021-12-10'::date, '2022-05-16'::date, 'Voluntary Exit', false),
    ('SISL-2021-037', 'Christopher Ukpabia', 'christopher.ukpabia@sycamore.ng', 'Sales Officer', dept_sales, '2021-07-05'::date, '2022-08-01'::date, 'Voluntary Exit', false),
    ('SISL-2021-041', 'Jesse Ukrakpor', 'jesse.ukrakpor@gmail.com', 'Sales Officer', dept_sales, '2021-08-02'::date, '2022-10-01'::date, 'Voluntary Exit', false),
    ('SISL-2021-030', 'Ayodele Akinbinu', 'ayodele.akinbinu@sycamore.ng', 'Sales Deputy Manager', dept_sales, '2021-05-10'::date, '2022-11-24'::date, 'Career Advancement', false),
    ('SISL-2021-034', 'Samuel Ajayi', 'samuel.ajayi@sycamore.ng', 'Lead Admin', dept_exec, '2021-06-21'::date, '2022-11-11'::date, 'Voluntary Exit', false),
    ('SISL-2020-015', 'Nkem Ejike', 'nkem.ejike@gmail.com', 'Sales Deputy Manager', dept_sales, '2020-08-29'::date, '2022-10-20'::date, 'Voluntary Exit', false),
    ('SISL-2020-016', 'Victoria Timehin', 'victoria.timehin@sycamore.ng', 'Sales Officer', dept_sales, '2020-08-29'::date, '2022-11-30'::date, 'Career Advancement', false),
    ('SISL-2021-043', 'Dotun Olakanmi', 'dotun.olakanmi@gmail.com', 'Growth Lead', dept_sales, '2021-09-07'::date, '2022-10-08'::date, 'Voluntary Exit', false),
    ('SISL-2022-086', 'Tolulope Obasanmi-Esan', 'tolulope.obasanmi-esan@sycamore.ng', 'Fund Mobilization', dept_investment, '2022-06-21'::date, '2022-11-30'::date, 'End of Contract', false),
    ('SISL-2022-089', 'Fidelia Harry', 'fidelia.harry@sycamore.ng', 'Sales Officer', dept_sales, '2022-09-05'::date, '2022-11-30'::date, 'End of Contract', false),
    ('SISL-2022-091', 'Edidiong Ekop', 'edidiong.ekop@sycamore.ng', 'Sales Officer', dept_sales, '2022-09-05'::date, '2022-11-30'::date, 'End of Contract', false),
    ('SISL-2022-094', 'Luke Ikenna', 'luke.ikenna@sycamore.ng', 'Sales Officer', dept_sales, '2022-09-05'::date, '2022-11-30'::date, 'End of Contract', false),
    ('SIML-2022-003', 'Musabau Aina', 'oluwasina.aina@sycamore.ng', 'Lead Finance', dept_finance, '2022-06-14'::date, '2023-07-15'::date, 'Voluntary Exit', false),
    ('SIML-2022-004', 'Simeon Oni', 'simeon.oni@sycamore.ng', 'Vice President', dept_exec, '2022-09-05'::date, '2023-01-16'::date, 'Voluntary Exit', false),
    ('SIML-2023-005', 'Olumide Sole', 'olumide.sole@sycamore.ng', 'Research Analyst', dept_sam, '2023-04-03'::date, '2023-06-14'::date, 'Career Advancement', false),
    ('SISL-2020-006', 'Adebayo Ojedokun', 'adebayo.ojedokun@sycamore.ng', 'Sales Officer', dept_sales, '2020-01-13'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2020-008', 'Samuel Lasisi', 'samuel.lasisi@sycamore.ng', 'Brand Lead', dept_marketing, '2020-01-20'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2020-009', 'Pedro Andrew', 'pedro.andrew@sycamore.ng', 'Sales Manager', dept_sales, '2020-06-19'::date, '2023-04-30'::date, 'Career Advancement', false),
    ('SISL-2020-011', 'Onyedikachi Erugo', 'onyedikachi.erugo@sycamore.ng', '', dept_exec, '2020-08-20'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2020-012', 'Ehimwenma Omorodion', 'ehimwenma.omorodion@sycamore.ng', '', dept_exec, '2020-08-29'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2020-014', 'Oluwatobi Oduntan', 'oluwatobi.oduntan@sycamore.ng', '', dept_exec, '2020-08-29'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2020-022', 'Mofeoluwa Abimbolu', 'mofeoluwa.abimbolu@gmail.com', 'Finance Officer', dept_finance, '2020-02-10'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2020-021', 'Prisca Ezeugbor', 'prisca.ezeugbor@sycamore.ng', 'HC Officer', dept_hc, '2020-01-17'::date, '2023-11-26'::date, 'Career Advancement', false),
    ('SISL-2021-017', 'Bola Atoyege', 'bola.atoyege@gmail.com', 'Sales Officer', dept_sales, '2019-07-15'::date, NULL::date, 'End of Contract', false),
    ('SISL-2021-018', 'Tobi Ayoade', 'tobi.ayoade@sycamore.ng', '', dept_exec, '2020-01-22'::date, NULL::date, 'End of Contract', false),
    ('SISL-2021-020', 'Wasiu Olaonipekun', 'wasiu.olanipekun@sycamore.ng', '', dept_exec, '2020-01-31'::date, NULL::date, 'End of Contract', false),
    ('SISL-2021-025', 'John', 'exited.sisl-2021-025@placeholder.local', '', dept_exec, '2021-01-11'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2021-026', 'Temitayo Ipinlaiye', 'temitayo.ipinlaiye@sycamore.ng', 'Product', dept_product, '2021-01-18'::date, '2023-11-24'::date, 'Career Advancement', false),
    ('SISL-2021-028', 'Temitope Adeniyi', 'temitope.adeniyi@sycamore.ng', 'Risk Manager', dept_risk, '2021-05-04'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2021-029', 'Frank Okolo', 'frank.okolo@gmail.com', 'Sales Officer', dept_sales, '2021-04-12'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2021-035', 'Winifred Ezechiogbe', 'winifred.ezechiogbe@sycamore.ng', 'Investment Affairs', dept_investment, '2021-06-21'::date, '2023-06-29'::date, 'Voluntary Exit', false),
    ('SISL-2021-036', 'Larry Akakah', 'larry.akakah@sycamore.ng', 'Sales Officer', dept_sales, '2021-07-05'::date, '2023-10-16'::date, 'Termination', false),
    ('SISL-2021-038', 'Olaniran Busari', 'olaniran.busari@sycamore.ng', 'Sales Officer', dept_sales, '2021-07-05'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2021-040', 'Francis Okafor', 'francis.okafor@sycamore.ng', 'Sales Regional Lead', dept_sales, '2021-07-19'::date, '2023-04-30'::date, 'Voluntary Exit', false),
    ('SISL-2021-044', 'Samuel Adesina', 'samuel.adesina@sycamore.ng', 'Backend Engineer', dept_tech, '2021-08-02'::date, NULL::date, 'Career Advancement', false),
    ('SISL-2021-045', 'Grace Udoh', 'grace.udoh@gmail.com', 'Customer Experience Officer', dept_cx, '2021-11-01'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2021-050', 'Uchechukwu Anyanwu', 'uchechukwu.anyanwu@sycamore.ng', 'Lead Investment', dept_investment, '2021-12-01'::date, NULL::date, 'Career Advancement', false),
    ('SISL-2021-051', 'Olalekan Moshood', 'olalekan.moshood@sycamore.ng', 'Facility Officer', dept_exec, '2021-11-24'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2021-052', 'Dolapo Oyetunji', 'dolapo.oyetunji@sycamore.ng', 'Lead Finance', dept_finance, '2021-12-06'::date, '2023-01-31'::date, 'Voluntary Exit', false),
    ('SISL-2022-058', 'Linda Odeh', 'linda.odeh@sycamore.ng', 'Investment Officer', dept_investment, '2022-01-13'::date, '2023-01-31'::date, 'End of Contract', false),
    ('SISL-2022-059', 'Tolulope Joseph', 'tolulope.joseph@sycamore.ng', 'Investment Officer', dept_investment, '2022-01-13'::date, '2023-01-31'::date, 'End of Contract', false),
    ('SISL-2022-060', 'Sofiat Olutayo', 'sophiat.olutayo@sycamore.ng', 'Investment Officer', dept_investment, '2022-01-13'::date, '2023-01-31'::date, 'End of Contract', false),
    ('SISL-2022-061', 'Praise Akhaze', 'praise.akhaze@sycamore.ng', 'Investment Officer', dept_investment, '2022-01-13'::date, '2023-01-31'::date, 'End of Contract', false),
    ('SISL-2022-062', 'Chinedu Nnebue', 'chinedu.nnebue@sycamore.ng', 'Investment Officer', dept_investment, '2022-01-13'::date, '2023-01-31'::date, 'End of Contract', false),
    ('SISL-2022-066', 'Alimat Usman', 'alimat.usman@sycamore.ng', 'Product Intern', dept_product, '2022-01-18'::date, '2023-01-31'::date, 'End of Contract', false),
    ('SISL-2022-076', 'Esther Abuah', 'esther.abuah@sycamore.ng', 'Sales Analyst', dept_sales, '2022-06-01'::date, '2023-05-04'::date, 'Voluntary Exit', false),
    ('SISL-2022-077', 'Matilda Obatha', 'matilda.obatha@sycamore.ng', 'Sales Analyst', dept_sales, '2022-06-01'::date, '2023-10-16'::date, 'Voluntary Exit', false),
    ('SISL-2022-079', 'Patience Agboiyi', 'patience.agboiyi@sycamore.ng', 'Sales Regional Lead', dept_sales, '2022-06-01'::date, '2023-04-30'::date, 'Career Advancement', false),
    ('SISL-2022-081', 'Maryjane Ndukuba', 'maryjane.ndukuba@sycamore.ng', 'Sales Officer', dept_sales, '2022-06-01'::date, '2023-03-29'::date, 'Voluntary Exit', false),
    ('SISL-2022-082', 'Stephen Mukoro', 'stephen.mukoro@sycamore.ng', 'Sales Officer', dept_sales, '2022-06-01'::date, '2023-10-24'::date, 'Voluntary Exit', false),
    ('SISL-2022-084', 'Bi Aprekuma', 'bi.aprekuma@gmail.com', 'Mobile Developer', dept_tech, '2022-06-14'::date, '2023-01-11'::date, 'End of Contract', false),
    ('SISL-2022-088', 'Tajudeen Gbadamosi', 'gbadamosi.tajudeen85@gmail.com', 'Facility Maintenance Officer', dept_exec, '2022-08-01'::date, '2023-04-30'::date, 'End of Contract', false),
    ('SISL-2022-092', 'Adebayo Oluwashina', 'adebayo.oluwashina@sycamore.ng', 'Sales Officer', dept_sales, '2022-09-05'::date, '2023-04-30'::date, 'End of Contract', false),
    ('SISL-2022-103', 'Abdulazeez Orehware', 'abdullazeez.haruna@sycamore.ng', 'Graphics Designer', dept_marketing, '2022-10-24'::date, '2023-02-01'::date, 'Voluntary Exit', false),
    ('SISL-2022-105', 'Oluwatosin Ogunjobi', 'oluwatosin.ogunjobi@sycamore.ng', 'Sales Officer', dept_sales, '2022-12-01'::date, '2023-06-27'::date, 'Voluntary Exit', false),
    ('SISL-2023-106', 'Peter Olagunju', 'peter.olagunju@sycamore.ng', 'Facility Maintenance Manager', dept_exec, '2023-01-03'::date, '2023-03-29'::date, 'Voluntary Exit', false),
    ('SISL-2023-108', 'Ezekiel Edoburun', 'ezekiel.edoburun@sycamore.ng', 'Investment Officer', dept_investment, '2023-01-09'::date, '2023-06-01'::date, 'Voluntary Exit', false),
    ('SISL-2023-109', 'Eriksson Owraigbo', 'fejiro.owraigbo@sycamore.ng', 'Network Engineer', dept_tech, '2023-01-05'::date, '2023-03-29'::date, 'Voluntary Exit', false),
    ('SISL-2023-114', 'Esther Okoro', 'esther.okoro@sycamore.ng', 'Telesales Officer', dept_cx, NULL::date, '2023-03-01'::date, 'Voluntary Exit', false),
    ('SISL-2023-115', 'Ginika Njoku', 'ginika.njoku@sycamore.ng', 'Sales Officer', dept_sales, '2023-02-13'::date, '2023-08-01'::date, 'Career Advancement', false),
    ('SISL-2023-119', 'Bolaji Akinsanya', 'bolaji@sycamore.ng', 'Sales Officer', dept_sales, '2023-03-01'::date, '2023-06-21'::date, 'Termination', false),
    ('SISL-2023-120', 'Tobi Ajibola', 'tobi.ajibola@sycamore.ng', 'Verification/KYC Officer', dept_product, '2023-03-01'::date, '2023-10-16'::date, 'Voluntary Exit', false),
    ('SISL-2023-129', 'Folake Olaoye', 'folake.olaoye@sycamore.ng', 'Sales Officer', dept_sales, '2023-05-02'::date, '2023-10-30'::date, 'Career Advancement', false),
    ('SISL-2023-133', 'Offiong Edet', 'offiong.bassey@sycamore.ng', 'Sales Officer', dept_sales, '2023-07-10'::date, '2023-06-20'::date, 'Voluntary Exit', false),
    ('SISL-2023-136', 'Faruq Olukoya', 'faruq.olukoya@sycamore.ng', 'Backend Engineer', dept_tech, '2023-07-17'::date, '2023-09-30'::date, 'Voluntary Exit', false),
    ('SISL-2023-150', 'Chinonso Ezemba', 'chinonso.great@sycamore.ng', 'Growth Officer', dept_sales, NULL::date, '2023-11-15'::date, 'End of Contract', false),
    ('SISL-2023-153', 'Nnamdi Ofuokwu', 'gerald.ofuokwu@sycamore.ng', 'Product/KYC Officer', dept_product, '2023-09-26'::date, '2023-12-29'::date, 'Voluntary Exit', false),
    ('SISL-2022-095', 'Gabriel Affia', 'gabriel.affia@sycamore.ng', 'Executive Assistant', dept_exec, '2022-09-05'::date, '2024-02-21'::date, 'Voluntary Exit', false),
    ('SISL-2022-085', 'Fiyinfoluwa Dorcas', 'fiyinfoluwa.dorcas@sycamore.ng', 'Credit Officer', dept_risk, '2022-06-21'::date, '2024-03-14'::date, 'Termination', false),
    ('SISL-2023-137', 'Ilemon Ileaboya', 'ilemon.ileaboya@sycamore.ng', 'Sales Regional Lead', dept_sales, '2023-07-17'::date, '2024-02-16'::date, 'Voluntary Exit', false),
    ('SISL-2023-141', 'Esther Okonkwor', 'esther.okonkwor@sycamore.ng', 'Investment Officer', dept_investment, '2023-08-07'::date, '2024-01-25'::date, 'Career Advancement', false),
    ('SISL-2023-146', 'Dare Olagbenro', 'dare.olagbenro@sycamore.ng', 'Sales Officer', dept_sales, '2023-08-13'::date, '2024-02-29'::date, 'Termination', false),
    ('SISL-2023-147', 'Ufuoma Oyibo', 'ufuoma.oyibo@sycamore.ng', 'Frontend Engineer', dept_tech, '2023-08-13'::date, '2024-02-28'::date, 'End of Contract', false),
    ('SISL-2022-096', 'Blessing Obidike', 'blessing.obidike@sycamore.ng', 'Internal Control Officer', dept_internal_ctrl, '2022-09-05'::date, '2024-03-15'::date, 'Relocation', false),
    ('SISL-2023-145', 'Olumide Akintewe', 'olumide.akintewe@sycamore.ng', 'Sales Analyst', dept_sales, '2023-08-13'::date, '2024-03-31'::date, 'Voluntary Exit', false),
    ('SISL-2024-169', 'Adeyemi Giwa', 'adeyemi.giwa@sycamore.ng', 'Sales Officer', dept_sales, '2024-02-26'::date, '2024-04-19'::date, 'Voluntary Exit', false),
    ('SISL-2024-171', 'Ganiyu Bello', 'ganiyu.bello@sycamore.ng', 'Internal Control Analyst', dept_internal_ctrl, '2024-02-27'::date, '2024-05-15'::date, 'Career Advancement', false),
    ('SISL-2024-168', 'Okonkwo Ikezue', 'ikezue.okonkwo@sycamore.ng', 'Sales Officer', dept_sales, '2024-02-26'::date, '2024-05-25'::date, 'Voluntary Exit', false),
    ('SISL-2024-191', 'Kayode Ajayi', 'kayode.ajayi@sycamore.ng', 'Senior BER', dept_tech, '2024-06-06'::date, '2024-06-20'::date, 'Termination', false),
    ('SISL-2024-162', 'Ezekiel Ikinwot', 'ezekiel.ikinwot@sycamore.ng', 'Technology', dept_tech, '2024-01-08'::date, '2024-06-28'::date, 'End of Contract', false),
    ('SISL-2023-111', 'Kosisochukwu Allison', 'kosisochukwu.allison@sycamore.ng', 'Mobile App Engineer', dept_tech, '2023-02-08'::date, '2024-07-20'::date, 'Voluntary Exit', false),
    ('SISL-2022-073', 'Timi Ayiti', 'timi.ayiti@sycamore.ng', 'Human Capital Manager', dept_hc, '2022-04-01'::date, '2024-07-31'::date, 'Voluntary Exit', false),
    ('SISL-2021-054', 'Oluwafelami Ajikobi', 'oluwafelami.ajikobi@sycamore.ng', 'Product Analyst', dept_product, '2021-12-08'::date, '2024-07-26'::date, 'Career Advancement', false),
    ('SISL-2021-046', 'Chukwuemeka Ikpa', 'chukwuemeka.ikpa@sycamore.ng', 'Lead Internal Control', dept_internal_ctrl, '2021-11-01'::date, '2024-07-31'::date, 'Voluntary Exit', false),
    ('SISL-2024-172', 'Mariam Oluwole', 'mariam.oluwale@sycamore.ng', 'Sales Officer', dept_sales, '2024-03-04'::date, '2024-08-26'::date, 'Voluntary Exit', false),
    ('SISL-2024-185', 'Jesse Ikemefuna', 'jesse.ikemefuna@sycamore.ng', 'Intern', dept_exec, '2024-05-07'::date, '2024-09-02'::date, 'End of Contract', false),
    ('SISL-2024-200', 'Joseph Jimoh', 'joseph.jimoh@sycamore.ng', 'Sales Officer', dept_sales, '2024-08-19'::date, '2024-09-20'::date, 'Voluntary Exit', false),
    ('SISL-2024-176', 'Clinton Isidore', 'clinton.isidore@sycamore.ng', 'Content Writer', dept_marketing, '2024-03-25'::date, '2024-09-25'::date, 'Voluntary Exit', false),
    ('SIML-2024-003', 'Farouq Aremu', 'farouq.aremu@sycamore.ng', 'Asset Management Analyst', dept_sam, '2024-03-04'::date, '2024-10-30'::date, 'Voluntary Exit', false),
    ('SISL-2022-072', 'Jacob Avarumun', 'kever.avarumun@sycamore.ng', 'Asset Management Analyst', dept_sam, '2022-03-07'::date, '2024-10-30'::date, 'Relocation', false),
    ('SISL-2024-202', 'Deborah Adeosun', 'deborah.adeosun@sycamore.ng', 'Finance Intern', dept_finance, '2024-08-26'::date, '2024-10-30'::date, 'End of Contract', false),
    ('SISL-2023-107', 'Dzarma Gwary', 'dzarma.gwary@sycamore.ng', 'Executive Assistant', dept_exec, '2023-01-03'::date, '2024-10-30'::date, 'Career Advancement', false),
    ('SISL-2024-189', 'Boluwatife Faturoti', 'boluwatife.faturoti@sycamore.ng', 'Risk Intern', dept_risk, '2024-06-03'::date, '2024-10-30'::date, 'End of Contract', false),
    ('SISL-2023-148', 'Chimnecherem Eboh', 'chimnecherem.eboh@sycamore.ng', 'Digital Marketer', dept_marketing, '2023-08-30'::date, '2024-10-11'::date, 'Career Advancement', false),
    ('SISL-2023-134', 'Micheal Fakilede', 'micheal.fakilede@sycamore.ng', 'Recovery Officer', dept_remedial, '2023-07-10'::date, '2024-11-25'::date, 'Career Advancement', false),
    ('SISL-2021-053', 'Yejide Kuyoro', 'yejide.kuyoro@sycamore.ng', 'Software Quality Assurance', dept_tech, '2021-12-08'::date, '2024-12-20'::date, 'Voluntary Exit', false),
    ('SISL-2022-090', 'Kennedy Ndukaku', 'kennedy.ndukaku@sycamore.ng', 'Sales Officer', dept_sales, '2022-09-05'::date, '2024-12-25'::date, 'Voluntary Exit', false),
    ('SISL-2023-124', 'Oluwatimileyin Akinpelu', 'oluwatimileyin.akinpelu@sycamore.ng', 'Frontend Engineer', dept_tech, '2023-04-03'::date, '2024-12-19'::date, 'Voluntary Exit', false),
    ('SISL-2024-203', 'Daniel Onyekwere', 'daniel.onyekwere@sycamore.ng', 'Investment Intern', dept_investment, '2024-09-23'::date, '2024-12-31'::date, 'End of Contract', false),
    ('SISL-2023-128', 'Onyinyechi Uchenna-ezegbunam', 'winnie.uche-ezegbunam@sycamore.ng', 'Executive Assistant', dept_exec, '2023-04-19'::date, '2024-01-06'::date, 'Redeployment', false),
    ('SISL-2024-173', 'Toyyibat Adebiyi', 'toyyibat.adebiyi@sycamore.ng', 'Internal Control Officer', dept_internal_ctrl, '2024-03-18'::date, '2024-01-06'::date, 'Redeployment', false),
    ('SISL-2024-205', 'Mobolanle Ajose', 'mobolanle.ajose@sycamore.ng', 'Internal Control & Audits Manager', dept_internal_ctrl, '2024-09-23'::date, '2025-02-26'::date, 'Voluntary Exit', false),
    ('SISL-2025-229', 'Retyit Kwarpo', 'retyit.kwarpo@sycamore.ng', 'Tech Intern', dept_tech, '2025-02-18'::date, '2025-03-20'::date, 'End of Contract', false),
    ('SISL-2025-228', 'Manuchimso Oliver', 'manuchimso.oliver@sycamore.ng', 'Frontend Engineer', dept_tech, '2025-02-18'::date, '2025-03-31'::date, 'Voluntary Exit', false),
    ('SISL-2023-143', 'Olabode Babawale', 'olabode.babawale@sycamore.ng', 'Investment Affairs Officer', dept_investment, '2023-08-02'::date, '2025-05-09'::date, 'Voluntary Exit', false),
    ('SISL-2024-201', 'Feyisayo Adekunle', 'feyisayo.adekunle@sycamore.ng', 'Content Marketer', dept_marketing, '2024-08-19'::date, '2025-06-11'::date, 'Career Advancement', false),
    ('SISL-2025-218', 'Daniel Orisabinone', 'daniel.orisabinone@sycamore.ng', 'Tech Intern', dept_tech, '2025-01-28'::date, '2025-06-27'::date, 'End of Contract', false),
    ('SISL-2024-188', 'Levi Conqueror', 'levi.conqueror@sycamore.ng', 'Product Marketer', dept_marketing, '2024-05-20'::date, '2025-07-01'::date, 'Voluntary Exit', false),
    ('SISL-2023-151', 'Saviour MBA', 'saviour.mba@sycamore.ng', 'Product Manager', dept_product, '2023-09-18'::date, '2025-08-15'::date, 'Voluntary Exit', false),
    ('SISL-2025-233', 'Temitope Adeyeye', 'temitope.adeyeye@sycamore.ng', 'Customer Support Officer', dept_cx, '2025-03-10'::date, '2025-08-05'::date, 'Voluntary Exit', false),
    ('SISL-2024-175', 'Maryam Oyeku', 'maryam.oyeku@sycamore.ng', 'Finance', dept_finance, '2024-03-20'::date, '2025-09-05'::date, 'Voluntary Exit', false),
    ('SISL-2025-231', 'Adaeze Madubueze', 'adaeze.madubueze@sycamore.ng', 'Customer Support Officer', dept_cx, '2025-03-10'::date, '2025-09-07'::date, 'Voluntary Exit', false),
    ('SISL-2023-140', 'Tobechukwu Anyanwu', 'tobechukwu.anyanwu@sycamore.ng', 'CX Officer', dept_cx, '2023-08-02'::date, '2025-09-15'::date, 'Voluntary Exit', false),
    ('SISL-2025-261', 'Daniel Kalu', 'daniel.kalu@sycamore.ng', 'Investment Intern', dept_investment, '2025-08-08'::date, '2025-10-03'::date, 'End of Contract', false),
    ('SISL-2025-239', 'Francis Anyaegbu', 'francis.anyaegbu@sycamore.ng', 'Tech Intern', dept_tech, '2025-04-07'::date, '2025-09-30'::date, 'End of Contract', false),
    ('SISL-2023-130', 'Chioma Onoh', 'chioma.onoh@sycamore.ng', 'Sales Officer', dept_sales, '2023-05-02'::date, '2025-09-30'::date, 'Voluntary Exit', false),
    ('SISL-2024-166', 'Elumeziem Chimaobi', 'meziem.desire@sycamore.ng', 'Growth Manager', dept_sales, '2024-02-12'::date, NULL::date, 'Termination', false),
    ('SISL-2022-099', 'Rasheed Abiodun', 'rasheed.abiodun@sycamore.ng', 'Sales Officer', dept_sales, '2022-09-05'::date, '2025-12-02'::date, 'Termination', false),
    ('SISL-2025-270', 'Chimezie Akubuiro', 'exited.sisl-2025-270@placeholder.local', '', dept_exec, '2025-07-01'::date, NULL::date, 'Termination', false),
    ('SISL-2025-262', 'Oluwanifemi Martins', 'oluwanifemi.martins@sycamore.ng', 'Technology', dept_tech, '2025-08-19'::date, NULL::date, 'End of Contract', false),
    ('SISL-2022-074', 'Mercy Akore', 'mercy.akore.cx@sycamore.ng', 'Customer Experience', dept_cx, '2022-05-16'::date, '2025-11-28'::date, 'Voluntary Exit', false),
    ('SISL-2023-117', 'Anthonia Tokunboh', 'anthonia.tokunboh@sycamore.ng', 'Executive Office', dept_exec, '2023-03-01'::date, '2025-11-07'::date, 'Voluntary Exit', false),
    ('SISL-2025-244', 'Nkemakonam Nwoayeocha', 'exited.sisl-2025-244@placeholder.local', 'Technology', dept_tech, '2025-05-12'::date, NULL::date, 'End of Contract', false),
    ('SISL-2025-253', 'Tochukwu Nnaji', 'tochukwu.nnaji@sycamore.ng', 'Technology', dept_tech, '2025-07-01'::date, NULL::date, 'End of Contract', false),
    ('SISL-2025-257', 'Umoren Idiong', 'exited.sisl-2025-257@placeholder.local', 'Executive Office', dept_exec, '2025-07-01'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2018-002', 'Mayowa Adeosun', 'mayowa@sycamore.ng', 'Executive Office', dept_exec, '2018-01-01'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2023-121', 'Peter Oluwasegun', 'peter@sycamore.ng', 'Technology', dept_tech, '2023-03-01'::date, '2025-12-31'::date, 'Voluntary Exit', false),
    ('SISL-2025-266', 'Esther Okechukwu', 'esther.okechukwu@sycamore.ng', 'Customer Experience', dept_cx, '2025-09-08'::date, '2026-01-14'::date, 'Voluntary Exit', false),
    ('SISL-2025-238', 'Israel Afolabi', 'israel.afolabi@sycamore.ng', 'Finance', dept_finance, '2025-04-07'::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2025-222', 'Lois Ekeinde', 'lois.ekeinde@sycamore.ng', 'Customer Support', dept_cx, '2025-02-17'::date, '2026-02-14'::date, 'Voluntary Exit', false),
    ('SISL-2024-207', 'Samuel Akeem', 'samuel.akeem@sycamore.ng', 'Risk Support', dept_risk, '2024-11-04'::date, '2026-02-06'::date, 'Voluntary Exit', false),
    ('SISL-2025-275', 'Imisioluwa Ogundele', 'imisioluwa.ogundele@sycamore.ng', 'Mobile Developer', dept_tech, '2025-12-09'::date, '2026-02-28'::date, 'Termination', false),
    ('SISL-2025-271', 'Chimeladhu Ehudhu', 'chimeladhu.ehudhu@sycamore.ng', 'Sales Officer', dept_sales, '2025-09-30'::date, '2026-02-28'::date, 'Voluntary Exit', false),
    ('SISL-2024-209', 'Hamzat Hamajo', 'hamza.hamajo@sycamore.ng', 'Recovery Officer', dept_remedial, '2024-11-14'::date, '2026-04-03'::date, 'Voluntary Exit', false),
    ('SISL-2026-298', 'Seun Ogundipe', 'seun.ogundipe@sycamore.ng', 'IT Support', dept_tech, NULL::date, NULL::date, 'Voluntary Exit', false),
    ('SISL-2022-068-B', 'Mercy Dada', 'mercy.dada@sycamore.ng', 'Risk Manager', dept_risk, '2022-02-01'::date, '2025-10-03'::date, 'Voluntary Exit', false)
  ) AS v(staff_id, full_name, email, role, department_id, joined_date, exited_at, exit_reason, is_active)
  WHERE NOT EXISTS (
    SELECT 1 FROM staff_members sm WHERE sm.staff_id = v.staff_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM staff_members sm WHERE sm.email = v.email
  );

  -- Update the existing records that need exit info
  UPDATE staff_members
  SET exited_at = '2024-09-06', exit_reason = 'Voluntary Exit', is_active = false, directory_visible = false
  WHERE staff_id = 'SISL-2020-010' AND is_active = true;

  UPDATE staff_members
  SET exit_reason = 'Termination', is_active = false, directory_visible = false
  WHERE staff_id = 'SISL-2023-116' AND is_active = true;

  UPDATE staff_members
  SET exited_at = '2023-09-30', exit_reason = 'End of Contract', is_active = false, directory_visible = false
  WHERE staff_id = 'SISL-2023-135' AND is_active = true;

  -- Update SISL-2022-068 (Mercy Akore - QA Intern who already exists) with exit info
  UPDATE staff_members
  SET exited_at = '2023-03-31', exit_reason = 'End of Contract', is_active = false, directory_visible = false
  WHERE staff_id = 'SISL-2022-068' AND is_active = true;

END $$;