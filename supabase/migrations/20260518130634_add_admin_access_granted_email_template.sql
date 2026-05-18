/*
  # Add admin_access_granted email template

  1. New email template
    - `admin_access_granted` slug used to notify a user that they've been
      granted admin access to the Hub.
    - Variables: first_name, role_label, added_by, link_url, link_label,
      brand_color, footer_html.

  2. Notes
    - Idempotent: inserts only if the slug does not already exist.
    - Marked as a system template so it cannot be deleted by admins.
*/

INSERT INTO email_templates (slug, name, description, subject, html_body, text_body, variables, is_system, is_active)
SELECT
  'admin_access_granted',
  'Admin access granted',
  'Sent to a user when they are added as an admin or super admin.',
  'You have admin access on Sycamore Info Hub',
  '<div style="font-family:system-ui,Segoe UI,sans-serif;background:#f6faf7;padding:32px 16px;"><div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:16px;border:1px solid #e2e8f0;overflow:hidden;"><div style="background:{{brand_color}};color:#ffffff;padding:20px 24px;font-weight:700;font-size:16px;">Admin access granted</div><div style="padding:24px;color:#1f2937;font-size:15px;line-height:1.55;"><p style="margin:0 0 12px;">Hi {{first_name}},</p><p style="margin:0 0 12px;">{{added_by}} has granted you <strong>{{role_label}}</strong> access on the Sycamore Info Hub.</p><p style="margin:0 0 12px;">You can now sign in and access the admin areas you''ve been given permission for. If you weren''t expecting this, please reply to this email and we''ll review the change.</p><p style="margin:24px 0 0;"><a href="{{link_url}}" style="display:inline-block;background:{{brand_color}};color:#fff;text-decoration:none;padding:10px 18px;border-radius:9999px;font-weight:600;">{{link_label}}</a></p></div><div style="padding:16px 24px;background:#f1f5f9;color:#64748b;font-size:12px;">{{footer_html}}</div></div></div>',
  'Hi {{first_name}},

{{added_by}} has granted you {{role_label}} access on the Sycamore Info Hub.

You can now sign in and access the admin areas you have been given permission for. If you weren''t expecting this, please reply to this email and we will review the change.

Open the admin area: {{link_url}}',
  ARRAY['first_name','role_label','added_by','link_url','link_label','brand_color','footer_html'],
  true,
  true
WHERE NOT EXISTS (SELECT 1 FROM email_templates WHERE slug = 'admin_access_granted');
