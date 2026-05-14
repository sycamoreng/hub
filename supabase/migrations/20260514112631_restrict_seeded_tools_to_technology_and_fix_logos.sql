/*
  # Restrict seeded tools to Technology department and fix logos

  ## Summary
  - The seeded tools added in the previous migration should only be visible
    to the Technology team.
  - Their logos used `logo.clearbit.com`, which is blocked / unreliable.
    Switch to Google's favicon service (`google.com/s2/favicons`), which is
    already used by the rest of the quick tools in this app.

  ## Changes
  1. Update `allowed_departments` to `{Technology}` for the seeded rows.
  2. Replace clearbit logo URLs with Google s2 favicon URLs derived from the
     tool's URL hostname.
*/

UPDATE public.quick_tools
SET allowed_departments = ARRAY['Technology']::text[],
    logo_url = CASE
      WHEN url IS NULL OR url = '' OR url = '#' THEN ''
      ELSE 'https://www.google.com/s2/favicons?domain='
           || regexp_replace(regexp_replace(url, '^https?://', ''), '/.*$', '')
           || '&sz=128'
    END,
    updated_at = now()
WHERE name IN (
  'GitHub','VS Code','IntelliJ IDEA','Xcode','Android Studio',
  'Zed','Arc','Warp','Obsidian','GitLens',
  'Figma','FigJam','Miro','Envato','Freepik','WordPress','Elementor',
  'PostgreSQL','pgAdmin','TablePlus',
  'Google Cloud Platform','Firebase','Render','Hostinger','Huawei','Office 365',
  'Grafana','Metabase','Mixpanel','Google Analytics','Microsoft Clarity','Appsflyer',
  'Postman','Newman','k6','Appium','Playwright','Scandium','AI Test tool',
  'ChatGPT','Claude','Gemini','Antigravity','UX Pilot',
  'Microsoft Teams','Zoom','WhatsApp','Skype',
  'SendGrid','Mailtrap','Go-mailer','Netcore','Termii','Africa''s Talking',
  'Monty Mobile','Sochitel','Bulk SMS Africa',
  'Paystack','Monnify','Fincra','Korapay','Mono','Bankly','Remita',
  'VTPass','Providus','Squad Sandbox','Merchant Dashboard',
  'Hyperverge','Dojah','Prembly (Identity Pass)','QoreID (Youverify)','OKHi','Checkpoint Harmony',
  'Lendsqr','Periculum','Fineract (Mifos)',
  'Coda','Jira','roadmap.sh','Canny','Beezop','MBS2026',
  'Apple Store Console','Google Play Console','Amazon Appstore',
  'Omada portal','MainOne portal','PCX'
);
