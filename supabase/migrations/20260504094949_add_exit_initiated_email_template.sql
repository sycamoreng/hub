/*
  # Exit initiated email template

  ## Summary
  Adds an `exit_initiated` email template used by the `email/notify_exit_initiated`
  edge function to notify the HOD of each exit unit when a resignation or
  termination is opened for a staff member.

  ## Changes
  1. Inserts a new row into `email_templates` with slug `exit_initiated`.
*/

insert into public.email_templates (slug, name, description, subject, html_body, text_body, variables, is_system, is_active)
select
  'exit_initiated',
  'Exit initiated',
  'Sent to each unit HOD when a resignation or termination is opened.',
  '{{exit_label}}: {{staff_name}} — action required',
  '<div style="font-family:system-ui,Segoe UI,sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#0f172a;">'
  || '<h1 style="color:{{brand_color}};margin:0 0 8px;font-size:20px;">{{exit_label}} initiated</h1>'
  || '<p style="margin:0 0 12px;">Hi {{first_name}},</p>'
  || '<p style="margin:0 0 12px;">An exit case has been opened for <strong>{{staff_name}}</strong> ({{staff_role}}{{staff_department_suffix}}).</p>'
  || '<table style="width:100%;border-collapse:collapse;margin:0 0 16px;font-size:14px;">'
  || '<tr><td style="padding:6px 0;color:#64748b;">Type</td><td style="padding:6px 0;">{{exit_label}}</td></tr>'
  || '<tr><td style="padding:6px 0;color:#64748b;">Effective date</td><td style="padding:6px 0;">{{effective_date}}</td></tr>'
  || '<tr><td style="padding:6px 0;color:#64748b;">Last working day</td><td style="padding:6px 0;">{{last_working_day}}</td></tr>'
  || '<tr><td style="padding:6px 0;color:#64748b;vertical-align:top;">Your unit</td><td style="padding:6px 0;">{{unit_name}}</td></tr>'
  || '</table>'
  || '<p style="margin:0 0 16px;">Please review and action your checklist in the Hub.</p>'
  || '<p style="margin:0 0 24px;"><a href="{{case_url}}" style="background:{{brand_color}};color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none;display:inline-block;">Open exit case</a></p>'
  || '{{footer_html}}'
  || '</div>',
  '{{exit_label}} initiated for {{staff_name}} ({{staff_role}}).'
  || E'\n\nEffective date: {{effective_date}}'
  || E'\nLast working day: {{last_working_day}}'
  || E'\nYour unit: {{unit_name}}'
  || E'\n\nOpen: {{case_url}}',
  ARRAY['first_name','staff_name','staff_role','staff_department_suffix','exit_label','effective_date','last_working_day','unit_name','case_url','brand_color','footer_html'],
  true,
  true
where not exists (select 1 from public.email_templates where slug = 'exit_initiated');
