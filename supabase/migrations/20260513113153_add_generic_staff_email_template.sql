/*
  # Generic staff notification email template

  1. New email_templates row
    - slug `staff_notification`: a flexible template used by notify_user edge action so any in-app notification (leave, finance, performance, etc.) can also fan out to email without us hand-rolling a template per type.

  2. Notes
    - Variables expected: `{{first_name}}`, `{{title}}`, `{{body_html}}`, `{{link_url}}`, `{{link_label}}`, `{{brand_color}}`, `{{footer_html}}`, `{{unsubscribe_url}}`.
*/

INSERT INTO email_templates (slug, name, subject, html_body, text_body, is_active)
VALUES (
  'staff_notification',
  'Generic staff notification',
  '{{title}}',
  '<div style="font-family:system-ui,Segoe UI,sans-serif;background:#f6faf7;padding:32px 16px;">' ||
  '<div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;border:1px solid #e2e8f0;overflow:hidden;">' ||
  '<div style="background:{{brand_color}};color:#ffffff;padding:20px 24px;font-weight:700;font-size:16px;">{{title}}</div>' ||
  '<div style="padding:24px;color:#1f2937;font-size:15px;line-height:1.55;">' ||
  '<p style="margin:0 0 12px;">Hi {{first_name}},</p>' ||
  '<div>{{body_html}}</div>' ||
  '<p style="margin:24px 0 0;"><a href="{{link_url}}" style="display:inline-block;background:{{brand_color}};color:#fff;text-decoration:none;padding:10px 18px;border-radius:9999px;font-weight:600;">{{link_label}}</a></p>' ||
  '</div>' ||
  '<div style="padding:16px 24px;background:#f1f5f9;color:#64748b;font-size:12px;">{{footer_html}}</div>' ||
  '</div></div>',
  'Hi {{first_name}},' || E'\n\n' || '{{title}}' || E'\n\n' || '{{link_label}}: {{link_url}}',
  true
)
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  subject = EXCLUDED.subject,
  html_body = EXCLUDED.html_body,
  text_body = EXCLUDED.text_body,
  is_active = true;
