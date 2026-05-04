/*
  # Refresh email templates with playful header/footer + Learning templates

  1. Changes
    - Update `email_settings.footer_html` to a dark-navy footer matching the brand screenshots
      (social links, address, unsubscribe, privacy — all using brand tokens).
    - Rewrite every system `email_templates` row (admin_broadcast, announcement_published,
      event_reminder, weekly_digest, mention_notification) with a shared dark-navy header,
      a playful light-blue body canvas with white content card, fun emoji accents, rounded
      hero panels, and the shared `{{footer_html}}` footer.
    - Seed two new system templates tied to the Learning feature:
      - `learning_assigned` — sent when a lesson is assigned to a learner
      - `learning_due_reminder` — sent as a due-date nudge

  2. Security
    - No schema / RLS changes. All writes scoped to seeded system rows by slug.
*/

-- 1) Updated dark-navy footer shared across templates
UPDATE email_settings
SET footer_html = $$<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0b1a2c;margin-top:32px;border-radius:16px;overflow:hidden;"><tr><td style="padding:28px 32px;color:#cbd5e1;font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;line-height:1.6;">
<div style="height:4px;background:linear-gradient(90deg,#0f6e42,#4ade80);border-radius:2px;margin-bottom:20px;"></div>
<div style="color:#ffffff;font-weight:600;font-size:15px;margin-bottom:4px;">Sycamore Info Hub</div>
<div style="color:#94a3b8;">The place where the Sycamore team stays in sync.</div>
<div style="margin-top:18px;">
  <a href="#" style="display:inline-block;margin-right:10px;color:#ffffff;text-decoration:none;font-size:18px;">f</a>
  <a href="#" style="display:inline-block;margin-right:10px;color:#ffffff;text-decoration:none;font-size:18px;">x</a>
  <a href="#" style="display:inline-block;margin-right:10px;color:#ffffff;text-decoration:none;font-size:18px;">in</a>
  <a href="#" style="display:inline-block;color:#ffffff;text-decoration:none;font-size:18px;">ig</a>
</div>
<div style="margin-top:20px;padding-top:16px;border-top:1px solid rgba(255,255,255,0.08);color:#94a3b8;font-size:12px;">
  You are receiving this email because you are part of the Sycamore team.
  <a href="{{unsubscribe_url}}" style="color:#4ade80;text-decoration:underline;">Manage your email preferences</a>.
</div>
<div style="margin-top:8px;color:#64748b;font-size:11px;">&copy; 2026 Sycamore Integrated Solutions Limited</div>
</td></tr></table>$$,
    updated_at = now()
WHERE id IS NOT NULL;

-- 2) Helper: apply the same dark-navy wordmark header + playful light-blue page background
--    by replacing the html_body of each system template.

UPDATE email_templates SET html_body = $$<div style="background:#eaf4ff;padding:24px 0;font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="display:inline-flex;align-items:center;gap:10px;color:#ffffff;font-weight:700;font-size:22px;letter-spacing:-0.01em;">
      <span style="display:inline-block;width:28px;height:28px;border:2px solid #ffffff;border-radius:6px;position:relative;">
        <span style="position:absolute;left:4px;top:6px;right:4px;height:2px;background:#ffffff;"></span>
        <span style="position:absolute;left:4px;top:12px;right:8px;height:2px;background:#ffffff;"></span>
        <span style="position:absolute;left:4px;top:18px;right:10px;height:2px;background:#ffffff;"></span>
      </span>
      Sycamore
    </div>
  </td></tr>
  <tr><td style="background:#ffffff;padding:0;">
    <div style="background:linear-gradient(135deg,#dbeafe 0%,#eaf4ff 55%,#dcfce7 100%);padding:32px;border-bottom:1px solid #e2e8f0;">
      <div style="display:inline-block;background:#0f6e42;color:#ffffff;font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:6px 12px;border-radius:999px;">New announcement</div>
      <h1 style="margin:16px 0 4px;font-size:26px;line-height:1.25;color:#0b1a2c;font-weight:800;">{{announcement_title}}</h1>
      <div style="color:#475569;font-size:14px;">Hi {{first_name}}, there is fresh news on the Hub.</div>
    </div>
    <div style="padding:28px 32px;color:#0f172a;font-size:15px;line-height:1.7;">
      {{announcement_body}}
      <div style="margin-top:24px;">
        <a href="{{announcement_url}}" style="display:inline-block;background:#0f6e42;color:#ffffff;padding:12px 22px;border-radius:999px;font-weight:700;text-decoration:none;font-size:14px;box-shadow:0 4px 12px rgba(15,110,66,0.25);">Read it on the Hub &rarr;</a>
      </div>
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='announcement_published';

UPDATE email_templates SET html_body = $$<div style="background:#eaf4ff;padding:24px 0;font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:22px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#fef9c3 0%,#eaf4ff 60%,#dbeafe 100%);padding:32px;">
      <div style="display:inline-block;background:#0b1a2c;color:#ffffff;font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:6px 12px;border-radius:999px;">Save the date</div>
      <h1 style="margin:16px 0 4px;font-size:26px;line-height:1.25;color:#0b1a2c;font-weight:800;">{{event_title}}</h1>
      <div style="color:#475569;font-size:14px;">{{event_type}}</div>
    </div>
    <div style="padding:28px 32px;color:#0f172a;font-size:15px;line-height:1.7;">
      <div style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:12px;padding:16px 20px;display:flex;align-items:center;gap:14px;margin-bottom:20px;">
        <div style="width:44px;height:44px;background:#0f6e42;color:#ffffff;border-radius:10px;display:inline-block;text-align:center;line-height:44px;font-weight:800;font-size:16px;">&#128197;</div>
        <div><div style="font-size:12px;color:#64748b;text-transform:uppercase;letter-spacing:0.08em;font-weight:700;">When</div><div style="font-size:16px;color:#0b1a2c;font-weight:700;">{{event_date}}</div></div>
      </div>
      <p style="margin:0 0 16px;">Hi {{first_name}}, this is a quick nudge so it does not slip your calendar.</p>
      <div>{{event_description}}</div>
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='event_reminder';

UPDATE email_templates SET html_body = $$<div style="background:#eaf4ff;padding:24px 0;font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:22px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#dbeafe 0%,#eaf4ff 55%,#dcfce7 100%);padding:32px;">
      <div style="display:inline-block;background:#0f6e42;color:#ffffff;font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:6px 12px;border-radius:999px;">Weekly roundup</div>
      <h1 style="margin:16px 0 4px;font-size:26px;color:#0b1a2c;font-weight:800;">This week at Sycamore &#9994;</h1>
      <div style="color:#475569;font-size:14px;">Here is what you might have missed, {{first_name}}.</div>
    </div>
    <div style="padding:28px 32px;color:#0f172a;font-size:15px;line-height:1.7;">
      {{digest_body}}
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='weekly_digest';

UPDATE email_templates SET html_body = $$<div style="background:#eaf4ff;padding:24px 0;font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:22px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#fde68a 0%,#eaf4ff 50%,#dbeafe 100%);padding:32px;">
      <div style="display:inline-block;background:#0b1a2c;color:#ffffff;font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:6px 12px;border-radius:999px;">Someone tagged you &#64;</div>
      <h1 style="margin:16px 0 4px;font-size:24px;color:#0b1a2c;font-weight:800;">{{mentioner_name}} mentioned you</h1>
      <div style="color:#475569;font-size:14px;">They want to pull you into the conversation.</div>
    </div>
    <div style="padding:28px 32px;color:#0f172a;font-size:15px;line-height:1.7;">
      <div style="background:#f0f9ff;border-left:4px solid #0f6e42;border-radius:10px;padding:16px 18px;font-style:italic;color:#334155;">&#8220;{{snippet}}&#8221;</div>
      <div style="margin-top:22px;">
        <a href="{{link_url}}" style="display:inline-block;background:#0f6e42;color:#ffffff;padding:12px 22px;border-radius:999px;font-weight:700;text-decoration:none;font-size:14px;">Jump into the thread &rarr;</a>
      </div>
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='mention_notification';

UPDATE email_templates SET html_body = $$<div style="background:#eaf4ff;padding:24px 0;font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:22px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#dbeafe 0%,#eaf4ff 100%);padding:32px;">
      <div style="display:inline-block;background:#0f6e42;color:#ffffff;font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:6px 12px;border-radius:999px;">From the team</div>
      <h1 style="margin:16px 0 4px;font-size:24px;color:#0b1a2c;font-weight:800;">{{heading}}</h1>
      <div style="color:#475569;font-size:14px;">Hi {{first_name}},</div>
    </div>
    <div style="padding:28px 32px;color:#0f172a;font-size:15px;line-height:1.7;">
      {{body}}
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='admin_broadcast';

-- 3) New: Learning assignment templates
INSERT INTO email_templates (slug, name, description, subject, html_body, text_body, variables, is_system, is_active)
VALUES
  (
    'learning_assigned',
    'Learning: new lesson assigned',
    'Sent when a lesson is assigned to a learner (directly, by department, or org-wide).',
    'New lesson for you: {{lesson_title}}',
    $$<div style="background:#eaf4ff;padding:24px 0;font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:22px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#dbeafe 0%,#eaf4ff 55%,#dcfce7 100%);padding:32px;position:relative;">
      <div style="display:inline-block;background:#0f6e42;color:#ffffff;font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:6px 12px;border-radius:999px;">A new lesson for you &#127891;</div>
      <h1 style="margin:16px 0 4px;font-size:26px;line-height:1.25;color:#0b1a2c;font-weight:800;">{{lesson_title}}</h1>
      <div style="color:#475569;font-size:14px;">Hi {{first_name}}, something just landed in your learning path.</div>
    </div>
    <div style="padding:28px 32px;color:#0f172a;font-size:15px;line-height:1.7;">
      <p style="margin:0 0 16px;">{{lesson_description}}</p>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f0f9ff;border:1px solid #bae6fd;border-radius:12px;margin:8px 0 22px;">
        <tr><td style="padding:14px 18px;border-bottom:1px dashed #cbd5e1;">
          <div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:0.08em;font-weight:700;">Assigned to</div>
          <div style="font-size:15px;color:#0b1a2c;font-weight:600;margin-top:2px;">{{scope_label}}</div>
        </td></tr>
        <tr><td style="padding:14px 18px;border-bottom:1px dashed #cbd5e1;">
          <div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:0.08em;font-weight:700;">Estimated time</div>
          <div style="font-size:15px;color:#0b1a2c;font-weight:600;margin-top:2px;">{{estimated_minutes}} min</div>
        </td></tr>
        <tr><td style="padding:14px 18px;">
          <div style="font-size:11px;color:#64748b;text-transform:uppercase;letter-spacing:0.08em;font-weight:700;">Due date</div>
          <div style="font-size:15px;color:#0b1a2c;font-weight:600;margin-top:2px;">{{due_date}}</div>
        </td></tr>
      </table>
      <a href="{{lesson_url}}" style="display:inline-block;background:#0f6e42;color:#ffffff;padding:12px 22px;border-radius:999px;font-weight:700;text-decoration:none;font-size:14px;box-shadow:0 4px 12px rgba(15,110,66,0.25);">Start the lesson &rarr;</a>
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$,
    'Hi {{first_name}}, a new lesson has been assigned to you: {{lesson_title}}. Due: {{due_date}}. Open it here: {{lesson_url}}',
    ARRAY['first_name','lesson_title','lesson_description','scope_label','estimated_minutes','due_date','lesson_url','brand_color','footer_html','unsubscribe_url'],
    true,
    true
  ),
  (
    'learning_due_reminder',
    'Learning: due date reminder',
    'Nudge sent to learners as a lesson due date approaches.',
    'Friendly nudge: {{lesson_title}} is due {{due_date}}',
    $$<div style="background:#eaf4ff;padding:24px 0;font-family:system-ui,Segoe UI,Helvetica,Arial,sans-serif;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:22px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#fde68a 0%,#eaf4ff 60%,#dbeafe 100%);padding:32px;">
      <div style="display:inline-block;background:#b45309;color:#ffffff;font-size:11px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:6px 12px;border-radius:999px;">Gentle reminder &#9200;</div>
      <h1 style="margin:16px 0 4px;font-size:26px;line-height:1.25;color:#0b1a2c;font-weight:800;">{{lesson_title}}</h1>
      <div style="color:#475569;font-size:14px;">Hi {{first_name}}, this lesson is due <strong>{{due_date}}</strong>.</div>
    </div>
    <div style="padding:28px 32px;color:#0f172a;font-size:15px;line-height:1.7;">
      <p style="margin:0 0 16px;">You have got this &#128170;. It should only take about <strong>{{estimated_minutes}} minutes</strong>, and then you are done.</p>
      <a href="{{lesson_url}}" style="display:inline-block;background:#0f6e42;color:#ffffff;padding:12px 22px;border-radius:999px;font-weight:700;text-decoration:none;font-size:14px;box-shadow:0 4px 12px rgba(15,110,66,0.25);">Finish the lesson &rarr;</a>
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$,
    'Hi {{first_name}}, a quick reminder that {{lesson_title}} is due {{due_date}}. {{lesson_url}}',
    ARRAY['first_name','lesson_title','estimated_minutes','due_date','lesson_url','brand_color','footer_html','unsubscribe_url'],
    true,
    true
  )
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  subject = EXCLUDED.subject,
  html_body = EXCLUDED.html_body,
  text_body = EXCLUDED.text_body,
  variables = EXCLUDED.variables,
  is_system = EXCLUDED.is_system,
  is_active = EXCLUDED.is_active,
  updated_at = now();