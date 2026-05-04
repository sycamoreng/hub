/*
  # Email templates: Satoshi font + clean light-blue CTAs + smaller type scale

  1. Changes
    - Swap all system email template bodies to use Satoshi (with web-font link + fallbacks).
    - Reduce type scale: body 13px, labels 11px, heading 20px (fluid within 18-22), small 12px.
    - Replace the brand-green pill CTA with the web app's clean light blue (#3087b9, sycamore-500)
      and matching soft-blue hero gradients.
    - Update the shared footer in email_settings to match the same stack.

  2. Security
    - No schema or RLS changes.
*/

UPDATE email_settings
SET footer_html = $$<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0b1a2c;margin-top:24px;border-radius:16px;overflow:hidden;"><tr><td style="padding:24px 28px;color:#cbd5e1;font-family:'Satoshi','Inter',system-ui,Segoe UI,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;">
<div style="height:3px;background:linear-gradient(90deg,#3087b9,#74b9e3);border-radius:2px;margin-bottom:16px;"></div>
<div style="color:#ffffff;font-weight:600;font-size:13px;margin-bottom:2px;">Sycamore Info Hub</div>
<div style="color:#94a3b8;font-size:12px;">The place where the Sycamore team stays in sync.</div>
<div style="margin-top:14px;">
  <a href="#" style="display:inline-block;margin-right:10px;color:#ffffff;text-decoration:none;font-size:14px;">f</a>
  <a href="#" style="display:inline-block;margin-right:10px;color:#ffffff;text-decoration:none;font-size:14px;">x</a>
  <a href="#" style="display:inline-block;margin-right:10px;color:#ffffff;text-decoration:none;font-size:14px;">in</a>
  <a href="#" style="display:inline-block;color:#ffffff;text-decoration:none;font-size:14px;">ig</a>
</div>
<div style="margin-top:16px;padding-top:14px;border-top:1px solid rgba(255,255,255,0.08);color:#94a3b8;font-size:11px;">
  You are receiving this email because you are part of the Sycamore team.
  <a href="{{unsubscribe_url}}" style="color:#74b9e3;text-decoration:underline;">Manage your email preferences</a>.
</div>
<div style="margin-top:6px;color:#64748b;font-size:10px;">&copy; 2026 Sycamore Integrated Solutions Limited</div>
</td></tr></table>$$,
    updated_at = now()
WHERE id IS NOT NULL;

-- Announcement
UPDATE email_templates SET html_body = $$<link href="https://api.fontshare.com/v2/css?f[]=satoshi@400,500,700,900&display=swap" rel="stylesheet"><div style="background:#eaf4fb;padding:24px 0;font-family:'Satoshi','Inter',system-ui,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:22px 28px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:18px;letter-spacing:-0.01em;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;padding:0;">
    <div style="background:linear-gradient(135deg,#d2e8f6 0%,#eaf4fb 60%,#ffffff 100%);padding:28px;border-bottom:1px solid #e2e8f0;">
      <div style="display:inline-block;background:#3087b9;color:#ffffff;font-size:10px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:5px 10px;border-radius:999px;">New announcement</div>
      <h1 style="margin:14px 0 4px;font-size:20px;line-height:1.25;color:#0b1a2c;font-weight:800;">{{announcement_title}}</h1>
      <div style="color:#475569;font-size:12px;">Hi {{first_name}}, fresh news on the Hub.</div>
    </div>
    <div style="padding:24px 28px;color:#0f172a;font-size:13px;line-height:1.7;">
      {{announcement_body}}
      <div style="margin-top:22px;">
        <a href="{{announcement_url}}" style="display:inline-block;background:#3087b9;color:#ffffff;padding:10px 20px;border-radius:999px;font-weight:700;text-decoration:none;font-size:12px;box-shadow:0 4px 12px rgba(48,135,185,0.25);">Read on the Hub &rarr;</a>
      </div>
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='announcement_published';

-- Event reminder
UPDATE email_templates SET html_body = $$<link href="https://api.fontshare.com/v2/css?f[]=satoshi@400,500,700,900&display=swap" rel="stylesheet"><div style="background:#eaf4fb;padding:24px 0;font-family:'Satoshi','Inter',system-ui,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:22px 28px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:18px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#d2e8f6 0%,#eaf4fb 60%,#ffffff 100%);padding:28px;">
      <div style="display:inline-block;background:#0b1a2c;color:#ffffff;font-size:10px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:5px 10px;border-radius:999px;">Save the date</div>
      <h1 style="margin:14px 0 4px;font-size:20px;line-height:1.25;color:#0b1a2c;font-weight:800;">{{event_title}}</h1>
      <div style="color:#475569;font-size:12px;">{{event_type}}</div>
    </div>
    <div style="padding:24px 28px;color:#0f172a;font-size:13px;line-height:1.7;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#eaf4fb;border:1px solid #a0d2ff;border-radius:12px;margin-bottom:18px;">
        <tr>
          <td style="padding:14px 18px;width:56px;vertical-align:middle;">
            <div style="width:40px;height:40px;background:#3087b9;color:#ffffff;border-radius:10px;text-align:center;line-height:40px;font-weight:800;font-size:14px;">&#128197;</div>
          </td>
          <td style="padding:14px 4px 14px 0;vertical-align:middle;">
            <div style="font-size:10px;color:#64748b;text-transform:uppercase;letter-spacing:0.08em;font-weight:700;">When</div>
            <div style="font-size:14px;color:#0b1a2c;font-weight:700;">{{event_date}}</div>
          </td>
        </tr>
      </table>
      <p style="margin:0 0 14px;">Hi {{first_name}}, quick nudge so it does not slip your calendar.</p>
      <div>{{event_description}}</div>
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='event_reminder';

-- Weekly digest
UPDATE email_templates SET html_body = $$<link href="https://api.fontshare.com/v2/css?f[]=satoshi@400,500,700,900&display=swap" rel="stylesheet"><div style="background:#eaf4fb;padding:24px 0;font-family:'Satoshi','Inter',system-ui,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:22px 28px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:18px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#d2e8f6 0%,#eaf4fb 55%,#ffffff 100%);padding:28px;">
      <div style="display:inline-block;background:#3087b9;color:#ffffff;font-size:10px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:5px 10px;border-radius:999px;">Weekly roundup</div>
      <h1 style="margin:14px 0 4px;font-size:20px;color:#0b1a2c;font-weight:800;">This week at Sycamore &#9994;</h1>
      <div style="color:#475569;font-size:12px;">Here is what you may have missed, {{first_name}}.</div>
    </div>
    <div style="padding:24px 28px;color:#0f172a;font-size:13px;line-height:1.7;">
      {{digest_body}}
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='weekly_digest';

-- Mention
UPDATE email_templates SET html_body = $$<link href="https://api.fontshare.com/v2/css?f[]=satoshi@400,500,700,900&display=swap" rel="stylesheet"><div style="background:#eaf4fb;padding:24px 0;font-family:'Satoshi','Inter',system-ui,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:22px 28px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:18px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#d2e8f6 0%,#eaf4fb 100%);padding:28px;">
      <div style="display:inline-block;background:#0b1a2c;color:#ffffff;font-size:10px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:5px 10px;border-radius:999px;">Someone tagged you &#64;</div>
      <h1 style="margin:14px 0 4px;font-size:19px;color:#0b1a2c;font-weight:800;">{{mentioner_name}} mentioned you</h1>
      <div style="color:#475569;font-size:12px;">They want to pull you into the conversation.</div>
    </div>
    <div style="padding:24px 28px;color:#0f172a;font-size:13px;line-height:1.7;">
      <div style="background:#eaf4fb;border-left:3px solid #3087b9;border-radius:10px;padding:14px 16px;font-style:italic;color:#334155;font-size:13px;">&#8220;{{snippet}}&#8221;</div>
      <div style="margin-top:20px;">
        <a href="{{link_url}}" style="display:inline-block;background:#3087b9;color:#ffffff;padding:10px 20px;border-radius:999px;font-weight:700;text-decoration:none;font-size:12px;">Jump into the thread &rarr;</a>
      </div>
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='mention_notification';

-- Admin broadcast
UPDATE email_templates SET html_body = $$<link href="https://api.fontshare.com/v2/css?f[]=satoshi@400,500,700,900&display=swap" rel="stylesheet"><div style="background:#eaf4fb;padding:24px 0;font-family:'Satoshi','Inter',system-ui,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:22px 28px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:18px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#d2e8f6 0%,#eaf4fb 100%);padding:28px;">
      <div style="display:inline-block;background:#3087b9;color:#ffffff;font-size:10px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:5px 10px;border-radius:999px;">From the team</div>
      <h1 style="margin:14px 0 4px;font-size:19px;color:#0b1a2c;font-weight:800;">{{heading}}</h1>
      <div style="color:#475569;font-size:12px;">Hi {{first_name}},</div>
    </div>
    <div style="padding:24px 28px;color:#0f172a;font-size:13px;line-height:1.7;">
      {{body}}
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='admin_broadcast';

-- Learning assigned
UPDATE email_templates SET html_body = $$<link href="https://api.fontshare.com/v2/css?f[]=satoshi@400,500,700,900&display=swap" rel="stylesheet"><div style="background:#eaf4fb;padding:24px 0;font-family:'Satoshi','Inter',system-ui,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:22px 28px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:18px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#d2e8f6 0%,#eaf4fb 55%,#ffffff 100%);padding:28px;">
      <div style="display:inline-block;background:#3087b9;color:#ffffff;font-size:10px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:5px 10px;border-radius:999px;">A new lesson for you &#127891;</div>
      <h1 style="margin:14px 0 4px;font-size:20px;line-height:1.25;color:#0b1a2c;font-weight:800;">{{lesson_title}}</h1>
      <div style="color:#475569;font-size:12px;">Hi {{first_name}}, something just landed in your learning path.</div>
    </div>
    <div style="padding:24px 28px;color:#0f172a;font-size:13px;line-height:1.7;">
      <p style="margin:0 0 14px;">{{lesson_description}}</p>
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#eaf4fb;border:1px solid #a0d2ff;border-radius:12px;margin:4px 0 20px;">
        <tr><td style="padding:12px 16px;border-bottom:1px dashed #c5d8e6;">
          <div style="font-size:10px;color:#64748b;text-transform:uppercase;letter-spacing:0.08em;font-weight:700;">Assigned to</div>
          <div style="font-size:13px;color:#0b1a2c;font-weight:600;margin-top:2px;">{{scope_label}}</div>
        </td></tr>
        <tr><td style="padding:12px 16px;border-bottom:1px dashed #c5d8e6;">
          <div style="font-size:10px;color:#64748b;text-transform:uppercase;letter-spacing:0.08em;font-weight:700;">Estimated time</div>
          <div style="font-size:13px;color:#0b1a2c;font-weight:600;margin-top:2px;">{{estimated_minutes}} min</div>
        </td></tr>
        <tr><td style="padding:12px 16px;">
          <div style="font-size:10px;color:#64748b;text-transform:uppercase;letter-spacing:0.08em;font-weight:700;">Due date</div>
          <div style="font-size:13px;color:#0b1a2c;font-weight:600;margin-top:2px;">{{due_date}}</div>
        </td></tr>
      </table>
      <a href="{{lesson_url}}" style="display:inline-block;background:#3087b9;color:#ffffff;padding:10px 20px;border-radius:999px;font-weight:700;text-decoration:none;font-size:12px;box-shadow:0 4px 12px rgba(48,135,185,0.25);">Start the lesson &rarr;</a>
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='learning_assigned';

-- Learning due reminder
UPDATE email_templates SET html_body = $$<link href="https://api.fontshare.com/v2/css?f[]=satoshi@400,500,700,900&display=swap" rel="stylesheet"><div style="background:#eaf4fb;padding:24px 0;font-family:'Satoshi','Inter',system-ui,Segoe UI,Helvetica,Arial,sans-serif;font-size:13px;">
<table role="presentation" width="640" align="center" cellpadding="0" cellspacing="0" style="max-width:640px;margin:0 auto;">
  <tr><td style="background:#0b1a2c;border-radius:16px 16px 0 0;padding:22px 28px;text-align:center;">
    <div style="color:#ffffff;font-weight:700;font-size:18px;">Sycamore</div>
  </td></tr>
  <tr><td style="background:#ffffff;">
    <div style="background:linear-gradient(135deg,#d2e8f6 0%,#eaf4fb 60%,#ffffff 100%);padding:28px;">
      <div style="display:inline-block;background:#0b1a2c;color:#ffffff;font-size:10px;font-weight:700;letter-spacing:0.14em;text-transform:uppercase;padding:5px 10px;border-radius:999px;">Gentle reminder &#9200;</div>
      <h1 style="margin:14px 0 4px;font-size:20px;line-height:1.25;color:#0b1a2c;font-weight:800;">{{lesson_title}}</h1>
      <div style="color:#475569;font-size:12px;">Hi {{first_name}}, this lesson is due <strong>{{due_date}}</strong>.</div>
    </div>
    <div style="padding:24px 28px;color:#0f172a;font-size:13px;line-height:1.7;">
      <p style="margin:0 0 14px;">You have got this &#128170;. It should only take about <strong>{{estimated_minutes}} minutes</strong>.</p>
      <a href="{{lesson_url}}" style="display:inline-block;background:#3087b9;color:#ffffff;padding:10px 20px;border-radius:999px;font-weight:700;text-decoration:none;font-size:12px;box-shadow:0 4px 12px rgba(48,135,185,0.25);">Finish the lesson &rarr;</a>
    </div>
  </td></tr>
  <tr><td>{{footer_html}}</td></tr>
</table>
</div>$$
WHERE slug='learning_due_reminder';