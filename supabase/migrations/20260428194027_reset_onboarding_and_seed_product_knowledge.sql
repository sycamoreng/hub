/*
  # Reset onboarding LMS and seed standard product-knowledge curriculum

  1. Cleanup
    - User-authorised deletion of all rows in `onboarding_resources`,
      `onboarding_progress`, and `onboarding_steps` so we can replace the
      content with a standard tailored learning path.

  2. Seed (product knowledge first)
    - Inserts a standard learning path covering:
      - Welcome & culture (intro, mission/vision, values)
      - Sycamore products: Sprout, Mobile App, Web Dashboard, Metrics
      - Tools, security, paperwork
    - Each product step is a `module` with attached resources (article + link).
    - All steps marked active; required steps flagged where appropriate.

  3. Notes
    - Resources cascade-delete with their parent step.
    - Existing onboarding_progress rows are removed because their step_ids
      will no longer exist.
*/

DELETE FROM public.onboarding_progress;
DELETE FROM public.onboarding_resources;
DELETE FROM public.onboarding_steps;

WITH inserted AS (
  INSERT INTO public.onboarding_steps
    (title, description, category, content_type, body, video_url, cover_image_url, resource_url, estimated_minutes, display_order, is_required, is_active)
  VALUES
    -- Welcome & culture
    ('Welcome to Sycamore',
     'Start here. A short tour of who we are, where we operate, and what we are building together.',
     'general', 'article',
     E'Welcome to Sycamore.\n\nSycamore.ng is a financial technology company empowering businesses and individuals across Africa with savings, investments, lending, and borrowing tools.\n\nIn this learning path you will get oriented across:\n  - Our mission, vision and values\n  - Our products and how they fit together\n  - The tools and systems you will use day-to-day\n  - Compliance, security and people processes\n\nYou can complete the steps in any order, but the product knowledge modules are highly recommended early on so you can confidently talk about what we build.',
     '', '', '', 10, 10, true, true),

    ('Our mission, vision and values',
     'The why behind Sycamore and the principles we hold each other to.',
     'culture', 'article',
     E'Mission: To deliver innovative technology solutions that empower businesses across Africa and beyond, driving digital transformation and sustainable growth.\n\nVision: To be Africa''s leading technology partner, recognized globally for excellence, innovation, and impact.\n\nCore values: Innovation, Integrity, Collaboration, Excellence, Customer-Centricity, Sustainability.\n\nThese are not posters on a wall - they show up in how we plan, ship, and treat each other.',
     '', '', '', 8, 20, true, true),

    -- Product knowledge (priority)
    ('Product overview: the Sycamore stack',
     'A high-level map of every product we build and who uses them.',
     'product', 'module',
     E'Sycamore ships four flagship products that work together:\n\n1) Sprout - our in-house core banking platform. The system of record for ledgering, customer accounts, lending and operational workflows.\n\n2) Sycamore Mobile App - the customer-facing app on iOS and Android.\n\n3) Web Dashboard - the browser experience for managing investments, loans and account info.\n\n4) Sycamore Metrics - the internal real-time business KPI dashboard.\n\nIn the next modules you will go deeper on each one.',
     '', '', '', 12, 30, true, true),

    ('Sprout - core banking platform',
     'Deep-dive on Sprout: the engine that powers ledgering, accounts, lending, and ops.',
     'product', 'module',
     E'Sprout is the heart of Sycamore. Every customer balance, transaction, loan and operational workflow flows through it.\n\nWho uses it: Operations, Finance, Engineering, Risk, Customer Support.\n\nKey concepts to learn:\n  - The ledger model and how journals are recorded\n  - Customer accounts and KYC tiers\n  - Lending workflow: origination, disbursement, repayment, write-off\n  - Operational tooling for Customer Support\n\nAsk your buddy for a Sprout sandbox login and walk through a real customer journey end-to-end.',
     '', '', '', 25, 40, true, true),

    ('Sycamore Mobile App',
     'How customers experience Sycamore from their phone.',
     'product', 'module',
     E'The Mobile App is the front door for most of our customers - available on the App Store and Google Play.\n\nWhat customers can do:\n  - Open and fund a Sycamore account\n  - Save and invest into curated products\n  - Apply for and manage loans\n  - View statements and transaction history\n  - Get support in-app\n\nDownload the app, create a test account in the staging environment and complete a full onboarding flow yourself - it is the fastest way to internalise how customers think.',
     '', '', '', 20, 50, true, true),

    ('Web Dashboard',
     'The browser experience for customers managing their money on a bigger screen.',
     'product', 'module',
     E'The Web Dashboard mirrors the Mobile App on desktop and is preferred by customers managing larger investment positions or repaying loans.\n\nFamiliarise yourself with:\n  - The investment products surface\n  - Loan repayment flows and schedules\n  - Account settings and security controls\n  - Cross-device parity with the Mobile App\n\nLog in with a test account and try the same journeys you tried on mobile - note where the experience differs.',
     '', '', '', 15, 60, false, true),

    ('Sycamore Metrics',
     'Our internal KPI cockpit: how we measure the business in real time.',
     'product', 'module',
     E'Sycamore Metrics is our internal dashboard surfacing real-time business and platform KPIs across products, regions, and teams.\n\nWhat to look at first:\n  - Active customers (DAU/MAU) and growth\n  - Assets under management and deposit balances\n  - Loan book health, default rates, recoveries\n  - Platform reliability: uptime, latency, error rates\n\nYour manager will grant access and walk you through the KPIs most relevant to your role.',
     '', '', '', 12, 70, false, true),

    -- Systems & access
    ('Tools and systems you will use',
     'Slack, Google Workspace, Notion, GitHub, Linear and the rest.',
     'systems', 'article',
     E'Day-to-day Sycamore runs on:\n  - Google Workspace (mail, calendar, docs)\n  - Slack for chat\n  - Notion for written knowledge\n  - GitHub for code\n  - Linear for issue tracking\n  - 1Password for shared secrets\n\nIT will provision access in your first week. If something is missing after day three, message #it-help on Slack.',
     '', '', '', 10, 80, true, true),

    ('Security and acceptable use',
     'How we keep customer data and our platform safe.',
     'compliance', 'article',
     E'Sycamore handles regulated financial data. A few non-negotiables:\n  - Use 1Password for every credential. No spreadsheets, no sticky notes.\n  - Enable hardware-backed MFA on every account.\n  - Lock your laptop whenever you leave it.\n  - Never share customer data outside approved tooling.\n  - Report anything suspicious to security@sycamore.ng or #security on Slack.\n\nYou will complete a short security training in your first two weeks.',
     '', '', '', 15, 90, true, true),

    -- Paperwork
    ('Paperwork and your first paycheck',
     'Documents, payroll, benefits enrolment.',
     'paperwork', 'task',
     E'People Ops will share a checklist on day one. Make sure you complete:\n  - Signed offer and contract\n  - Bank details for payroll\n  - Tax/identification documents\n  - Benefits enrolment\n  - Emergency contact form\n\nReach out to hr@sycamore.ng if anything is unclear.',
     '', '', '', 20, 100, true, true)
  RETURNING id, title
)
INSERT INTO public.onboarding_resources (step_id, kind, title, description, url, body, display_order)
SELECT i.id, r.kind, r.title, r.description, r.url, r.body, r.display_order
FROM inserted i
JOIN (VALUES
  ('Sprout - core banking platform', 'article', 'Ledger 101: how money moves on Sprout',
   'A short primer on double-entry ledgers and how Sprout records every transaction.',
   '',
   E'Every movement of money on Sprout is recorded as a balanced journal: one or more debits and credits across accounts that always sum to zero.\n\nThis is the same accounting model used by every modern bank and fintech - it makes it impossible to "lose" money in the system without leaving a trace.\n\nAsk your buddy to walk you through a real journal in the Sprout admin tool.',
   1),
  ('Sprout - core banking platform', 'link', 'Open the Sprout admin (staging)',
   'Bookmark this for the rest of your onboarding.',
   'https://sprout.staging.sycamore.ng', '', 2),
  ('Sycamore Mobile App', 'link', 'Download on the App Store',
   'iOS download link.',
   'https://apps.apple.com/app/sycamore', '', 1),
  ('Sycamore Mobile App', 'link', 'Download on Google Play',
   'Android download link.',
   'https://play.google.com/store/apps/details?id=ng.sycamore.app', '', 2),
  ('Web Dashboard', 'link', 'Open the customer dashboard',
   'Sign in with a test account.',
   'https://app.sycamore.ng', '', 1),
  ('Sycamore Metrics', 'article', 'How to read our KPIs',
   'A glossary of every KPI surfaced on Metrics.',
   '',
   E'Active customers - any customer with at least one transaction in the last 30 days.\nAssets under management - the total value of customer deposits and investments.\nLoan book - the aggregate outstanding principal across all open loans.\nDefault rate - portion of loans 90+ days past due.\n\nIf a number looks off, raise it in #metrics on Slack before assuming it''s wrong.',
   1),
  ('Tools and systems you will use', 'link', 'Sycamore Slack',
   '',
   'https://sycamore.slack.com', '', 1),
  ('Tools and systems you will use', 'link', 'Sycamore Notion',
   '',
   'https://notion.so/sycamore', '', 2),
  ('Security and acceptable use', 'article', 'Reporting an incident',
   'What to do if you see something off.',
   '',
   E'If you suspect a security incident:\n  1. Do not try to fix it alone.\n  2. Post in #security on Slack with as much context as you have.\n  3. Email security@sycamore.ng if Slack is unavailable.\n  4. Preserve any evidence (screenshots, logs).\n\nThere is no penalty for raising a false alarm - we always prefer over-reporting.',
   1)
) AS r(step_title, kind, title, description, url, body, display_order)
ON i.title = r.step_title;
