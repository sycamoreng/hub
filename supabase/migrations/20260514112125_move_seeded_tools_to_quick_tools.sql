/*
  # Move seeded tools list to quick_tools

  ## Summary
  The previous migration seeded a long list of tools into `tech_stack`.
  Per request, those entries belong on the Tools page (`quick_tools`),
  not on the Technology page (`tech_stack`).

  ## Changes
  1. Delete the seeded rows from `tech_stack` by name match.
  2. Insert the same list into `quick_tools` (idempotent: skips names that
     already exist).

  ## Safety
  - Only deletes rows whose `name` matches an entry in the seeded list.
  - User-created `tech_stack` rows are preserved.
*/

WITH names(name) AS (
  VALUES
    ('GitHub'),('VS Code'),('IntelliJ IDEA'),('Xcode'),('Android Studio'),
    ('Zed'),('Arc'),('Warp'),('Obsidian'),('GitLens'),
    ('Figma'),('FigJam'),('Miro'),('Envato'),('Freepik'),('WordPress'),('Elementor'),
    ('PostgreSQL'),('pgAdmin'),('TablePlus'),
    ('Google Cloud Platform'),('Firebase'),('Render'),('Hostinger'),('Huawei'),('Office 365'),
    ('Grafana'),('Metabase'),('Mixpanel'),('Google Analytics'),('Microsoft Clarity'),('Appsflyer'),
    ('Postman'),('Newman'),('k6'),('Appium'),('Playwright'),('Scandium'),('AI Test tool'),
    ('ChatGPT'),('Claude'),('Gemini'),('Antigravity'),('UX Pilot'),
    ('Slack'),('Microsoft Teams'),('Zoom'),('WhatsApp'),('Skype'),
    ('SendGrid'),('Mailtrap'),('Go-mailer'),('Netcore'),('Termii'),('Africa''s Talking'),
    ('Monty Mobile'),('Sochitel'),('Bulk SMS Africa'),
    ('Paystack'),('Monnify'),('Fincra'),('Korapay'),('Mono'),('Bankly'),('Remita'),
    ('VTPass'),('Providus'),('Squad Sandbox'),('Merchant Dashboard'),
    ('Hyperverge'),('Dojah'),('Prembly (Identity Pass)'),('QoreID (Youverify)'),('OKHi'),('Checkpoint Harmony'),
    ('Lendsqr'),('Periculum'),('Fineract (Mifos)'),
    ('Coda'),('Jira'),('Sprout'),('SeamlessHR'),('Freshdesk'),('Canny'),('roadmap.sh'),
    ('Beezop'),('MBS2026'),
    ('Apple Store Console'),('Google Play Console'),('Amazon Appstore'),
    ('Omada portal'),('MainOne portal'),('PCX')
)
DELETE FROM public.tech_stack t
USING names n
WHERE lower(t.name) = lower(n.name);

WITH seed(name, url, logo_url, sort_order) AS (
  VALUES
    ('GitHub','https://github.com','https://logo.clearbit.com/github.com',10),
    ('VS Code','https://code.visualstudio.com','https://logo.clearbit.com/visualstudio.com',20),
    ('IntelliJ IDEA','https://www.jetbrains.com/idea','https://logo.clearbit.com/jetbrains.com',30),
    ('Xcode','https://developer.apple.com/xcode','https://logo.clearbit.com/apple.com',40),
    ('Android Studio','https://developer.android.com/studio','https://logo.clearbit.com/android.com',50),
    ('Zed','https://zed.dev','https://logo.clearbit.com/zed.dev',60),
    ('Arc','https://arc.net','https://logo.clearbit.com/arc.net',70),
    ('Warp','https://warp.dev','https://logo.clearbit.com/warp.dev',80),
    ('Obsidian','https://obsidian.md','https://logo.clearbit.com/obsidian.md',90),
    ('GitLens','https://www.gitkraken.com/gitlens','https://logo.clearbit.com/gitkraken.com',100),
    ('Figma','https://figma.com','https://logo.clearbit.com/figma.com',110),
    ('FigJam','https://figma.com/figjam','https://logo.clearbit.com/figma.com',120),
    ('Miro','https://miro.com','https://logo.clearbit.com/miro.com',130),
    ('Envato','https://envato.com','https://logo.clearbit.com/envato.com',140),
    ('Freepik','https://freepik.com','https://logo.clearbit.com/freepik.com',150),
    ('WordPress','https://wordpress.org','https://logo.clearbit.com/wordpress.org',160),
    ('Elementor','https://elementor.com','https://logo.clearbit.com/elementor.com',170),
    ('PostgreSQL','https://www.postgresql.org','https://logo.clearbit.com/postgresql.org',200),
    ('pgAdmin','https://pgadmin.org','https://logo.clearbit.com/pgadmin.org',210),
    ('TablePlus','https://tableplus.com','https://logo.clearbit.com/tableplus.com',220),
    ('Google Cloud Platform','https://cloud.google.com','https://logo.clearbit.com/cloud.google.com',300),
    ('Firebase','https://firebase.google.com','https://logo.clearbit.com/firebase.google.com',310),
    ('Render','https://render.com','https://logo.clearbit.com/render.com',320),
    ('Hostinger','https://hostinger.com','https://logo.clearbit.com/hostinger.com',330),
    ('Huawei','https://huawei.com','https://logo.clearbit.com/huawei.com',340),
    ('Office 365','https://www.office.com','https://logo.clearbit.com/office.com',350),
    ('Grafana','https://grafana.com','https://logo.clearbit.com/grafana.com',400),
    ('Metabase','https://metabase.com','https://logo.clearbit.com/metabase.com',410),
    ('Mixpanel','https://mixpanel.com','https://logo.clearbit.com/mixpanel.com',420),
    ('Google Analytics','https://analytics.google.com','https://logo.clearbit.com/analytics.google.com',430),
    ('Microsoft Clarity','https://clarity.microsoft.com','https://logo.clearbit.com/clarity.microsoft.com',440),
    ('Appsflyer','https://appsflyer.com','https://logo.clearbit.com/appsflyer.com',450),
    ('Postman','https://postman.com','https://logo.clearbit.com/postman.com',500),
    ('Newman','https://www.npmjs.com/package/newman','https://logo.clearbit.com/postman.com',510),
    ('k6','https://k6.io','https://logo.clearbit.com/k6.io',520),
    ('Appium','https://appium.io','https://logo.clearbit.com/appium.io',530),
    ('Playwright','https://playwright.dev','https://logo.clearbit.com/playwright.dev',540),
    ('Scandium','https://scandium.com','',550),
    ('AI Test tool','','',560),
    ('ChatGPT','https://chat.openai.com','https://logo.clearbit.com/openai.com',600),
    ('Claude','https://claude.ai','https://logo.clearbit.com/anthropic.com',610),
    ('Gemini','https://gemini.google.com','https://logo.clearbit.com/gemini.google.com',620),
    ('Antigravity','https://antigravity.google','',630),
    ('UX Pilot','https://uxpilot.ai','https://logo.clearbit.com/uxpilot.ai',640),
    ('Slack','https://slack.com','https://logo.clearbit.com/slack.com',700),
    ('Microsoft Teams','https://www.microsoft.com/microsoft-teams','https://logo.clearbit.com/microsoft.com',710),
    ('Zoom','https://zoom.us','https://logo.clearbit.com/zoom.us',720),
    ('WhatsApp','https://whatsapp.com','https://logo.clearbit.com/whatsapp.com',730),
    ('Skype','https://skype.com','https://logo.clearbit.com/skype.com',740),
    ('SendGrid','https://sendgrid.com','https://logo.clearbit.com/sendgrid.com',800),
    ('Mailtrap','https://mailtrap.io','https://logo.clearbit.com/mailtrap.io',810),
    ('Go-mailer','https://go-mailer.com','https://logo.clearbit.com/go-mailer.com',820),
    ('Netcore','https://netcorecloud.com','https://logo.clearbit.com/netcorecloud.com',830),
    ('Termii','https://termii.com','https://logo.clearbit.com/termii.com',840),
    ('Africa''s Talking','https://africastalking.com','https://logo.clearbit.com/africastalking.com',850),
    ('Monty Mobile','https://montymobile.com','https://logo.clearbit.com/montymobile.com',860),
    ('Sochitel','https://sochitel.com','https://logo.clearbit.com/sochitel.com',870),
    ('Bulk SMS Africa','','',880),
    ('Paystack','https://paystack.com','https://logo.clearbit.com/paystack.com',900),
    ('Monnify','https://monnify.com','https://logo.clearbit.com/monnify.com',910),
    ('Fincra','https://fincra.com','https://logo.clearbit.com/fincra.com',920),
    ('Korapay','https://korapay.com','https://logo.clearbit.com/korapay.com',930),
    ('Mono','https://mono.co','https://logo.clearbit.com/mono.co',940),
    ('Bankly','https://bankly.africa','https://logo.clearbit.com/bankly.africa',950),
    ('Remita','https://remita.net','https://logo.clearbit.com/remita.net',960),
    ('VTPass','https://vtpass.com','https://logo.clearbit.com/vtpass.com',970),
    ('Providus','https://providusbank.com','https://logo.clearbit.com/providusbank.com',980),
    ('Squad Sandbox','https://squadco.com','https://logo.clearbit.com/squadco.com',990),
    ('Merchant Dashboard','','',1000),
    ('Hyperverge','https://hyperverge.co','https://logo.clearbit.com/hyperverge.co',1100),
    ('Dojah','https://dojah.io','https://logo.clearbit.com/dojah.io',1110),
    ('Prembly (Identity Pass)','https://prembly.com','https://logo.clearbit.com/prembly.com',1120),
    ('QoreID (Youverify)','https://qoreid.com','https://logo.clearbit.com/qoreid.com',1130),
    ('OKHi','https://okhi.com','https://logo.clearbit.com/okhi.com',1140),
    ('Checkpoint Harmony','https://www.checkpoint.com/harmony','https://logo.clearbit.com/checkpoint.com',1150),
    ('Lendsqr','https://lendsqr.com','https://logo.clearbit.com/lendsqr.com',1200),
    ('Periculum','https://periculum.io','https://logo.clearbit.com/periculum.io',1210),
    ('Fineract (Mifos)','https://mifos.org','https://logo.clearbit.com/mifos.org',1220),
    ('Coda','https://coda.io','https://logo.clearbit.com/coda.io',1300),
    ('Jira','https://www.atlassian.com/software/jira','https://logo.clearbit.com/atlassian.com',1310),
    ('Sprout','https://sprout.ph','https://logo.clearbit.com/sprout.ph',1320),
    ('SeamlessHR','https://seamlesshr.com','https://logo.clearbit.com/seamlesshr.com',1330),
    ('Freshdesk','https://freshdesk.com','https://logo.clearbit.com/freshdesk.com',1340),
    ('Canny','https://canny.io','https://logo.clearbit.com/canny.io',1350),
    ('roadmap.sh','https://roadmap.sh','https://logo.clearbit.com/roadmap.sh',1360),
    ('Beezop','','',1370),
    ('MBS2026','','',1380),
    ('Apple Store Console','https://appstoreconnect.apple.com','https://logo.clearbit.com/apple.com',1400),
    ('Google Play Console','https://play.google.com/console','https://logo.clearbit.com/google.com',1410),
    ('Amazon Appstore','https://developer.amazon.com/apps-and-games','https://logo.clearbit.com/amazon.com',1420),
    ('Omada portal','','',1500),
    ('MainOne portal','https://mainone.net','https://logo.clearbit.com/mainone.net',1510),
    ('PCX','','',1520)
)
INSERT INTO public.quick_tools (name, url, logo_url, allowed_departments, sort_order, is_active)
SELECT s.name, COALESCE(NULLIF(s.url,''), '#'), s.logo_url, '{}'::text[], s.sort_order, true
FROM seed s
WHERE NOT EXISTS (
  SELECT 1 FROM public.quick_tools q WHERE lower(q.name) = lower(s.name)
);
