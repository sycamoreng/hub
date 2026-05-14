/*
  # Add logo_url to tech_stack and seed common tools

  ## Changes
  1. Add `logo_url` column to `tech_stack` (text, defaults to '').
  2. Bulk-insert the technology and tooling list provided by the admin.
     Each row uses `ON CONFLICT (lower(name))` -- via a NOT EXISTS guard --
     so the insert is idempotent and does not overwrite manual edits.

  ## Notes
  - Logo URLs use Clearbit's logo CDN (`https://logo.clearbit.com/<domain>`)
    for tools whose domain is well-known. Tools without a confident
    domain match are inserted with an empty `logo_url`; the UI falls back
    to a generic icon for those.
  - Categories use the existing taxonomy plus a few additions
    (`ai`, `communication`, `payments`, `design`, `productivity`,
    `testing`, `finance`) which are simple text values; no constraint
    change required.

  ## Safety
  - No destructive changes. Existing rows are preserved.
*/

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'tech_stack' AND column_name = 'logo_url'
  ) THEN
    ALTER TABLE public.tech_stack ADD COLUMN logo_url text DEFAULT '';
  END IF;
END $$;

WITH seed(name, category, used_for, url, logo_url, display_order) AS (
  VALUES
    -- Source control & collaboration
    ('GitHub','tooling','Source control, code review, and CI/CD','https://github.com','https://logo.clearbit.com/github.com',10),
    ('VS Code','tooling','Primary code editor','https://code.visualstudio.com','https://logo.clearbit.com/visualstudio.com',20),
    ('IntelliJ IDEA','tooling','JetBrains IDE for backend services','https://www.jetbrains.com/idea','https://logo.clearbit.com/jetbrains.com',30),
    ('Xcode','tooling','iOS app builds and signing','https://developer.apple.com/xcode','https://logo.clearbit.com/apple.com',40),
    ('Android Studio','tooling','Android app builds and signing','https://developer.android.com/studio','https://logo.clearbit.com/android.com',50),
    ('Zed','tooling','Lightweight collaborative editor','https://zed.dev','https://logo.clearbit.com/zed.dev',60),
    ('Arc','tooling','Browser used for daily work','https://arc.net','https://logo.clearbit.com/arc.net',70),
    ('Warp','tooling','Modern terminal','https://warp.dev','https://logo.clearbit.com/warp.dev',80),
    ('Obsidian','tooling','Personal knowledge base','https://obsidian.md','https://logo.clearbit.com/obsidian.md',90),
    ('GitLens','tooling','Git history and blame inside VS Code','https://www.gitkraken.com/gitlens','https://logo.clearbit.com/gitkraken.com',100),

    -- Design & content
    ('Figma','design','Product and brand design','https://figma.com','https://logo.clearbit.com/figma.com',110),
    ('FigJam','design','Whiteboarding inside Figma','https://figma.com/figjam','https://logo.clearbit.com/figma.com',120),
    ('Miro','design','Whiteboarding and workshops','https://miro.com','https://logo.clearbit.com/miro.com',130),
    ('Envato','design','Stock assets for design and content','https://envato.com','https://logo.clearbit.com/envato.com',140),
    ('Freepik','design','Stock illustrations and vectors','https://freepik.com','https://logo.clearbit.com/freepik.com',150),
    ('WordPress','design','Marketing sites and content','https://wordpress.org','https://logo.clearbit.com/wordpress.org',160),
    ('Elementor','design','Page builder for WordPress','https://elementor.com','https://logo.clearbit.com/elementor.com',170),

    -- Databases & data tooling
    ('PostgreSQL','database','Primary relational database','https://www.postgresql.org','https://logo.clearbit.com/postgresql.org',200),
    ('pgAdmin','tooling','PostgreSQL admin GUI','https://pgadmin.org','https://logo.clearbit.com/pgadmin.org',210),
    ('TablePlus','tooling','Database client','https://tableplus.com','https://logo.clearbit.com/tableplus.com',220),

    -- Cloud & hosting
    ('Google Cloud Platform','cloud','Cloud infrastructure','https://cloud.google.com','https://logo.clearbit.com/cloud.google.com',300),
    ('Firebase','cloud','Mobile backend and analytics','https://firebase.google.com','https://logo.clearbit.com/firebase.google.com',310),
    ('Render','cloud','App and service hosting','https://render.com','https://logo.clearbit.com/render.com',320),
    ('Hostinger','cloud','Web hosting','https://hostinger.com','https://logo.clearbit.com/hostinger.com',330),
    ('Huawei','cloud','Huawei integrations','https://huawei.com','https://logo.clearbit.com/huawei.com',340),
    ('Office 365','general','Email, docs, and collaboration','https://www.office.com','https://logo.clearbit.com/office.com',350),

    -- Observability & quality
    ('Grafana','observability','Dashboards and alerting','https://grafana.com','https://logo.clearbit.com/grafana.com',400),
    ('Metabase','data','Self-serve analytics','https://metabase.com','https://logo.clearbit.com/metabase.com',410),
    ('Mixpanel','data','Product analytics','https://mixpanel.com','https://logo.clearbit.com/mixpanel.com',420),
    ('Google Analytics','data','Web analytics','https://analytics.google.com','https://logo.clearbit.com/analytics.google.com',430),
    ('Microsoft Clarity','data','Session recordings and heatmaps','https://clarity.microsoft.com','https://logo.clearbit.com/clarity.microsoft.com',440),
    ('Appsflyer','data','Mobile attribution','https://appsflyer.com','https://logo.clearbit.com/appsflyer.com',450),

    -- Testing
    ('Postman','devops','API design and testing','https://postman.com','https://logo.clearbit.com/postman.com',500),
    ('Newman','devops','Postman CLI runner','https://www.npmjs.com/package/newman','https://logo.clearbit.com/postman.com',510),
    ('k6','devops','Load and performance testing','https://k6.io','https://logo.clearbit.com/k6.io',520),
    ('Appium','testing','Mobile UI automation','https://appium.io','https://logo.clearbit.com/appium.io',530),
    ('Playwright','testing','Cross-browser end-to-end testing','https://playwright.dev','https://logo.clearbit.com/playwright.dev',540),
    ('Scandium','testing','No-code test automation','https://scandium.com','',550),
    ('AI Test tool','testing','AI-assisted QA workflows','','',560),

    -- AI assistants
    ('ChatGPT','ai','OpenAI assistant','https://chat.openai.com','https://logo.clearbit.com/openai.com',600),
    ('Claude','ai','Anthropic assistant','https://claude.ai','https://logo.clearbit.com/anthropic.com',610),
    ('Gemini','ai','Google assistant','https://gemini.google.com','https://logo.clearbit.com/gemini.google.com',620),
    ('Antigravity','ai','AI coding workspace','https://antigravity.google','',630),
    ('UX Pilot','ai','AI design assistant','https://uxpilot.ai','https://logo.clearbit.com/uxpilot.ai',640),

    -- Communication & messaging
    ('Slack','general','Team chat','https://slack.com','https://logo.clearbit.com/slack.com',700),
    ('Microsoft Teams','general','Team chat and meetings','https://www.microsoft.com/microsoft-teams','https://logo.clearbit.com/microsoft.com',710),
    ('Zoom','general','Video conferencing','https://zoom.us','https://logo.clearbit.com/zoom.us',720),
    ('WhatsApp','general','Customer messaging','https://whatsapp.com','https://logo.clearbit.com/whatsapp.com',730),
    ('Skype','general','Calls and chat','https://skype.com','https://logo.clearbit.com/skype.com',740),

    -- Email & SMS
    ('SendGrid','communication','Transactional email','https://sendgrid.com','https://logo.clearbit.com/sendgrid.com',800),
    ('Mailtrap','communication','Email testing','https://mailtrap.io','https://logo.clearbit.com/mailtrap.io',810),
    ('Go-mailer','communication','Email delivery','https://go-mailer.com','https://logo.clearbit.com/go-mailer.com',820),
    ('Netcore','communication','Marketing automation','https://netcorecloud.com','https://logo.clearbit.com/netcorecloud.com',830),
    ('Termii','communication','SMS and OTP delivery','https://termii.com','https://logo.clearbit.com/termii.com',840),
    ('Africa''s Talking','communication','SMS and voice APIs','https://africastalking.com','https://logo.clearbit.com/africastalking.com',850),
    ('Monty Mobile','communication','SMS aggregation','https://montymobile.com','https://logo.clearbit.com/montymobile.com',860),
    ('Sochitel','communication','Telco aggregator','https://sochitel.com','https://logo.clearbit.com/sochitel.com',870),
    ('Bulk SMS Africa','communication','SMS delivery','','',880),

    -- Payments & banking
    ('Paystack','payments','Card and bank payments','https://paystack.com','https://logo.clearbit.com/paystack.com',900),
    ('Monnify','payments','Bank transfer collections','https://monnify.com','https://logo.clearbit.com/monnify.com',910),
    ('Fincra','payments','Cross-border payments','https://fincra.com','https://logo.clearbit.com/fincra.com',920),
    ('Korapay','payments','Payments integration','https://korapay.com','https://logo.clearbit.com/korapay.com',930),
    ('Mono','payments','Open banking','https://mono.co','https://logo.clearbit.com/mono.co',940),
    ('Bankly','payments','Agent banking integration','https://bankly.africa','https://logo.clearbit.com/bankly.africa',950),
    ('Remita','payments','Payment processing','https://remita.net','https://logo.clearbit.com/remita.net',960),
    ('VTPass','payments','Bills and airtime','https://vtpass.com','https://logo.clearbit.com/vtpass.com',970),
    ('Providus','payments','Banking partner','https://providusbank.com','https://logo.clearbit.com/providusbank.com',980),
    ('Squad Sandbox','payments','Squad payments sandbox','https://squadco.com','https://logo.clearbit.com/squadco.com',990),
    ('Merchant Dashboard','payments','Internal merchant ops dashboard','','',1000),

    -- Identity & risk
    ('Hyperverge','security','KYC and identity','https://hyperverge.co','https://logo.clearbit.com/hyperverge.co',1100),
    ('Dojah','security','KYC and ID verification','https://dojah.io','https://logo.clearbit.com/dojah.io',1110),
    ('Prembly (Identity Pass)','security','Identity verification','https://prembly.com','https://logo.clearbit.com/prembly.com',1120),
    ('QoreID (Youverify)','security','Identity verification','https://qoreid.com','https://logo.clearbit.com/qoreid.com',1130),
    ('OKHi','security','Address verification','https://okhi.com','https://logo.clearbit.com/okhi.com',1140),
    ('Checkpoint Harmony','security','Endpoint and network security','https://www.checkpoint.com/harmony','https://logo.clearbit.com/checkpoint.com',1150),

    -- Lending & finance ops
    ('Lendsqr','finance','Lending platform','https://lendsqr.com','https://logo.clearbit.com/lendsqr.com',1200),
    ('Periculum','finance','Credit risk analytics','https://periculum.io','https://logo.clearbit.com/periculum.io',1210),
    ('Fineract (Mifos)','finance','Core banking platform','https://mifos.org','https://logo.clearbit.com/mifos.org',1220),

    -- Productivity & ops
    ('Coda','productivity','Docs and lightweight workflows','https://coda.io','https://logo.clearbit.com/coda.io',1300),
    ('Jira','productivity','Issue tracking','https://www.atlassian.com/software/jira','https://logo.clearbit.com/atlassian.com',1310),
    ('Sprout','productivity','HR and people ops','https://sprout.ph','https://logo.clearbit.com/sprout.ph',1320),
    ('SeamlessHR','productivity','HR management','https://seamlesshr.com','https://logo.clearbit.com/seamlesshr.com',1330),
    ('Freshdesk','productivity','Customer support','https://freshdesk.com','https://logo.clearbit.com/freshdesk.com',1340),
    ('Canny','productivity','Customer feedback','https://canny.io','https://logo.clearbit.com/canny.io',1350),
    ('roadmap.sh','productivity','Engineering learning roadmaps','https://roadmap.sh','https://logo.clearbit.com/roadmap.sh',1360),
    ('Beezop','productivity','SOPs and team docs','','',1370),
    ('MBS2026','productivity','Internal program reference','','',1380),

    -- App stores
    ('Apple Store Console','tooling','App Store Connect','https://appstoreconnect.apple.com','https://logo.clearbit.com/apple.com',1400),
    ('Google Play Console','tooling','Play Console for Android','https://play.google.com/console','https://logo.clearbit.com/google.com',1410),
    ('Amazon Appstore','tooling','Amazon Appstore for Android','https://developer.amazon.com/apps-and-games','https://logo.clearbit.com/amazon.com',1420),

    -- Network / portals
    ('Omada portal','tooling','Network controller portal','','',1500),
    ('MainOne portal','tooling','Connectivity provider portal','https://mainone.net','https://logo.clearbit.com/mainone.net',1510),
    ('PCX','tooling','Internal PCX portal','','',1520)
)
INSERT INTO public.tech_stack (name, category, used_for, url, logo_url, display_order, is_active)
SELECT s.name, s.category, s.used_for, s.url, s.logo_url, s.display_order, true
FROM seed s
WHERE NOT EXISTS (
  SELECT 1 FROM public.tech_stack t WHERE lower(t.name) = lower(s.name)
);
