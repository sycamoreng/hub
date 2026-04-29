import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function render(template: string, vars: Record<string, string>) {
  return template.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_m, key) => vars[key] ?? "");
}

function stripHtml(html: string) {
  return html.replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<[^>]+>/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

async function sendViaSendGrid(args: {
  apiKey: string;
  fromName: string;
  fromEmail: string;
  replyTo?: string;
  to: string;
  toName?: string;
  subject: string;
  html: string;
  text: string;
}) {
  const body: Record<string, unknown> = {
    personalizations: [{ to: [{ email: args.to, name: args.toName || undefined }] }],
    from: { email: args.fromEmail, name: args.fromName },
    subject: args.subject,
    content: [
      { type: "text/plain", value: args.text || stripHtml(args.html) },
      { type: "text/html", value: args.html },
    ],
  };
  if (args.replyTo) body.reply_to = { email: args.replyTo };

  const res = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${args.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`SendGrid ${res.status}: ${text}`);
  }

  return res.headers.get("x-message-id") ?? "";
}

async function requireAdmin(authHeader: string) {
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return { admin: false, user: null };
  const email = (userData.user.email ?? "").toLowerCase();
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data } = await admin
    .from("admin_users")
    .select("email")
    .eq("email", email)
    .maybeSingle();
  return { admin: !!data, user: userData.user };
}

function firstName(name?: string | null) {
  if (!name) return "there";
  return name.trim().split(/\s+/)[0] || "there";
}

async function getSettings(admin: ReturnType<typeof createClient>) {
  const { data } = await admin
    .from("email_settings")
    .select("*")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  return data;
}

async function getTemplate(admin: ReturnType<typeof createClient>, slug: string) {
  const { data } = await admin
    .from("email_templates")
    .select("*")
    .eq("slug", slug)
    .maybeSingle();
  return data;
}

async function ensurePrefs(
  admin: ReturnType<typeof createClient>,
  userId: string,
) {
  const { data } = await admin
    .from("notification_preferences")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();
  if (data) return data;
  const { data: created } = await admin
    .from("notification_preferences")
    .insert({ user_id: userId })
    .select("*")
    .maybeSingle();
  return created;
}

function appBaseUrl() {
  return Deno.env.get("APP_BASE_URL") ?? "";
}

async function appBaseUrlFromSettings(admin: ReturnType<typeof createClient>) {
  const s = await getSettings(admin);
  return (s as any)?.app_base_url || appBaseUrl();
}

function buildVars(base: Record<string, string>, settings: any, unsubToken: string, appUrl: string) {
  const unsub = appUrl && unsubToken ? `${appUrl.replace(/\/$/, "")}/unsubscribe?token=${unsubToken}` : "";
  const vars: Record<string, string> = {
    ...base,
    brand_color: settings?.brand_color || "#0f6e42",
    unsubscribe_url: unsub,
  };
  vars.footer_html = render(settings?.footer_html || "", vars);
  return vars;
}

async function queueFromTemplate(
  adminClient: ReturnType<typeof createClient>,
  slug: string,
  recipient: { email: string; name?: string; user_id?: string | null; unsubscribe_token?: string | null },
  vars: Record<string, string>,
  trigger: string,
  reference: Record<string, unknown>,
) {
  const template = await getTemplate(adminClient, slug);
  if (!template || template.is_active === false) return false;
  const subject = render(template.subject, vars);
  const html = render(template.html_body, vars);
  const text = render(template.text_body || "", vars);
  await adminClient.from("email_queue").insert({
    to_email: recipient.email,
    to_name: recipient.name ?? "",
    subject,
    html_body: html,
    text_body: text,
    template_slug: slug,
    trigger,
    payload: vars,
    reference_id: reference,
    user_id: recipient.user_id ?? null,
    status: "pending",
  });
  return true;
}

async function dailyReminders(adminClient: ReturnType<typeof createClient>, leadDays = 3) {
  const settings = await getSettings(adminClient);
  if (!settings || settings.default_enabled === false) return { queued: 0 };

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const target = new Date(today);
  target.setDate(target.getDate() + leadDays);
  const targetStr = target.toISOString().slice(0, 10);

  const { data: events } = await adminClient
    .from("holidays_events")
    .select("*")
    .eq("event_date", targetStr);
  if (!events || events.length === 0) return { queued: 0 };

  const { data: staff } = await adminClient
    .from("staff_members")
    .select("id,full_name,email,auth_user_id")
    .eq("is_active", true)
    .not("email", "is", null);
  if (!staff || staff.length === 0) return { queued: 0 };

  const appUrl = (settings as any).app_base_url || appBaseUrl();
  let queued = 0;
  for (const event of events) {
    for (const s of staff) {
      if (!s.email) continue;
      let unsubToken = "";
      if (s.auth_user_id) {
        const prefs = await ensurePrefs(adminClient, s.auth_user_id);
        if (prefs && prefs.email_event_reminders === false) continue;
        unsubToken = prefs?.unsubscribe_token ?? "";
      }
      const vars = buildVars({
        first_name: firstName(s.full_name),
        event_title: event.title ?? "",
        event_date: new Date(event.event_date).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" }),
        event_type: event.event_type ?? "Event",
        event_description: event.description ?? "",
      }, settings, unsubToken, appUrl);
      const ok = await queueFromTemplate(
        adminClient,
        "event_reminder",
        { email: s.email, name: s.full_name, user_id: s.auth_user_id, unsubscribe_token: unsubToken },
        vars,
        "event_reminder",
        { event_id: event.id },
      );
      if (ok) queued++;
    }
  }
  return { queued };
}

async function weeklyDigest(adminClient: ReturnType<typeof createClient>) {
  const settings = await getSettings(adminClient);
  if (!settings || settings.default_enabled === false) return { queued: 0 };

  const since = new Date();
  since.setDate(since.getDate() - 7);
  const sinceIso = since.toISOString();

  const [ann, posts, events] = await Promise.all([
    adminClient.from("announcements").select("title,summary,created_at").eq("is_active", true).gte("created_at", sinceIso).order("created_at", { ascending: false }).limit(6),
    adminClient.from("posts").select("id,content,created_at").eq("is_published", true).gte("created_at", sinceIso).order("created_at", { ascending: false }).limit(6),
    adminClient.from("holidays_events").select("title,event_date,event_type").gte("event_date", new Date().toISOString().slice(0, 10)).lte("event_date", new Date(Date.now() + 7 * 86400000).toISOString().slice(0, 10)).order("event_date"),
  ]);

  const annList = (ann.data ?? []).map((a: any) => `<li><strong>${a.title}</strong>${a.summary ? ` — ${a.summary}` : ""}</li>`).join("");
  const postList = (posts.data ?? []).map((p: any) => `<li>${(p.content ?? "").slice(0, 140)}${(p.content ?? "").length > 140 ? "..." : ""}</li>`).join("");
  const eventList = (events.data ?? []).map((e: any) => `<li><strong>${e.title}</strong> — ${new Date(e.event_date).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" })}</li>`).join("");

  const body = [
    annList ? `<h3 style="margin:16px 0 8px;">New announcements</h3><ul>${annList}</ul>` : "",
    postList ? `<h3 style="margin:16px 0 8px;">From the feed</h3><ul>${postList}</ul>` : "",
    eventList ? `<h3 style="margin:16px 0 8px;">Coming up</h3><ul>${eventList}</ul>` : "",
  ].filter(Boolean).join("");

  if (!body) return { queued: 0 };

  const bodyPlain = [
    (ann.data ?? []).map((a: any) => `- ${a.title}`).join("\n"),
    (posts.data ?? []).map((p: any) => `- ${(p.content ?? "").slice(0, 140)}`).join("\n"),
    (events.data ?? []).map((e: any) => `- ${e.title} (${new Date(e.event_date).toLocaleDateString("en-GB")})`).join("\n"),
  ].filter(Boolean).join("\n\n");

  const { data: staff } = await adminClient
    .from("staff_members")
    .select("id,full_name,email,auth_user_id")
    .eq("is_active", true)
    .not("email", "is", null);
  if (!staff || staff.length === 0) return { queued: 0 };

  const appUrl = (settings as any).app_base_url || appBaseUrl();
  let queued = 0;
  for (const s of staff) {
    if (!s.email) continue;
    let unsubToken = "";
    if (s.auth_user_id) {
      const prefs = await ensurePrefs(adminClient, s.auth_user_id);
      if (prefs && prefs.email_weekly_digest === false) continue;
      unsubToken = prefs?.unsubscribe_token ?? "";
    }
    const vars = buildVars({
      first_name: firstName(s.full_name),
      digest_body: body,
      digest_body_plain: bodyPlain,
    }, settings, unsubToken, appUrl);
    const ok = await queueFromTemplate(
      adminClient,
      "weekly_digest",
      { email: s.email, name: s.full_name, user_id: s.auth_user_id, unsubscribe_token: unsubToken },
      vars,
      "weekly_digest",
      { digest_week: new Date().toISOString().slice(0, 10) },
    );
    if (ok) queued++;
  }
  return { queued };
}

async function broadcast(
  adminClient: ReturnType<typeof createClient>,
  args: { subject: string; heading: string; body_html: string; audience: "all" | "department"; department_id?: string },
) {
  const settings = await getSettings(adminClient);
  if (!settings || settings.default_enabled === false) throw new Error("Email sending disabled");

  let q = adminClient
    .from("staff_members")
    .select("id,full_name,email,auth_user_id,department_id")
    .eq("is_active", true)
    .not("email", "is", null);
  if (args.audience === "department" && args.department_id) {
    q = q.eq("department_id", args.department_id);
  }
  const { data: staff } = await q;
  if (!staff || staff.length === 0) return { queued: 0 };

  const appUrl = (settings as any).app_base_url || appBaseUrl();
  let queued = 0;
  for (const s of staff) {
    if (!s.email) continue;
    let unsubToken = "";
    if (s.auth_user_id) {
      const prefs = await ensurePrefs(adminClient, s.auth_user_id);
      if (prefs && prefs.email_broadcasts === false) continue;
      unsubToken = prefs?.unsubscribe_token ?? "";
    }
    const bodyPlain = args.body_html.replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
    const vars = buildVars({
      first_name: firstName(s.full_name),
      subject: args.subject,
      heading: args.heading,
      body: args.body_html,
      body_plain: bodyPlain,
    }, settings, unsubToken, appUrl);
    const ok = await queueFromTemplate(
      adminClient,
      "admin_broadcast",
      { email: s.email, name: s.full_name, user_id: s.auth_user_id, unsubscribe_token: unsubToken },
      vars,
      "admin_broadcast",
      { broadcast_sent_at: new Date().toISOString() },
    );
    if (ok) queued++;
  }
  return { queued };
}

async function queueAnnouncement(adminClient: ReturnType<typeof createClient>, announcementId: string) {
  const { data: a } = await adminClient
    .from("announcements")
    .select("*")
    .eq("id", announcementId)
    .maybeSingle();
  if (!a) throw new Error("Announcement not found");
  if (!a.email_on_publish) throw new Error("Announcement not flagged for email");

  const settings = await getSettings(adminClient);
  if (!settings || settings.default_enabled === false) throw new Error("Email sending disabled");

  const template = await getTemplate(adminClient, "announcement_published");
  if (!template || template.is_active === false) throw new Error("announcement_published template missing or inactive");

  const audience = a.email_audience || "all";
  let recipientsQuery = adminClient
    .from("staff_members")
    .select("id,full_name,email,auth_user_id,department_id")
    .eq("is_active", true)
    .not("email", "is", null);

  if (audience === "department" && a.email_department_id) {
    recipientsQuery = recipientsQuery.eq("department_id", a.email_department_id);
  } else if (audience === "mentioned") {
    const { data: mentions } = await adminClient
      .from("announcement_mentions")
      .select("staff_id")
      .eq("announcement_id", announcementId);
    const ids = (mentions ?? []).map((m) => m.staff_id).filter(Boolean);
    if (ids.length === 0) return { queued: 0 };
    recipientsQuery = recipientsQuery.in("id", ids);
  }

  const { data: recipients } = await recipientsQuery;
  if (!recipients || recipients.length === 0) return { queued: 0 };

  const rows: any[] = [];
  const appUrl = appBaseUrl();
  for (const r of recipients) {
    if (r.auth_user_id) {
      const prefs = await ensurePrefs(adminClient, r.auth_user_id);
      if (prefs && prefs.email_announcements === false) continue;
    }
    const tokenRes = r.auth_user_id
      ? await adminClient
          .from("notification_preferences")
          .select("unsubscribe_token")
          .eq("user_id", r.auth_user_id)
          .maybeSingle()
      : { data: null };
    const unsubToken = (tokenRes.data as any)?.unsubscribe_token ?? "";
    const vars: Record<string, string> = {
      first_name: firstName(r.full_name),
      announcement_title: a.title ?? "",
      announcement_body: (a.content ?? "").replace(/\n/g, "<br>"),
      announcement_body_plain: a.content ?? "",
      announcement_url: appUrl ? `${appUrl}/feed` : "",
      brand_color: settings.brand_color || "#0f6e42",
      footer_html: render(settings.footer_html || "", {
        unsubscribe_url: appUrl && unsubToken ? `${appUrl}/unsubscribe?token=${unsubToken}` : "",
      }),
      unsubscribe_url: appUrl && unsubToken ? `${appUrl}/unsubscribe?token=${unsubToken}` : "",
    };
    rows.push({
      to_email: r.email,
      to_name: r.full_name ?? "",
      subject: render(template.subject, vars),
      html_body: render(template.html_body, vars),
      text_body: render(template.text_body || "", vars),
      template_slug: template.slug,
      trigger: "announcement_published",
      payload: { announcement_id: announcementId },
      reference_id: { announcement_id: announcementId },
      user_id: r.auth_user_id ?? null,
      status: "pending",
    });
  }

  if (rows.length) {
    await adminClient.from("email_queue").insert(rows);
    await adminClient.from("announcements").update({ email_sent_at: new Date().toISOString() }).eq("id", announcementId);
  }
  return { queued: rows.length };
}

async function runQueue(adminClient: ReturnType<typeof createClient>, limit = 25) {
  const apiKey = Deno.env.get("SENDGRID_API_KEY");
  if (!apiKey) throw new Error("SENDGRID_API_KEY not configured");

  const settings = await getSettings(adminClient);
  if (!settings) throw new Error("email_settings not configured");

  const { data: jobs } = await adminClient
    .from("email_queue")
    .select("*")
    .in("status", ["pending"])
    .lte("scheduled_at", new Date().toISOString())
    .order("created_at", { ascending: true })
    .limit(limit);

  let sent = 0;
  let failed = 0;

  for (const job of jobs ?? []) {
    await adminClient
      .from("email_queue")
      .update({ status: "sending", attempts: (job.attempts ?? 0) + 1, updated_at: new Date().toISOString() })
      .eq("id", job.id);
    try {
      const messageId = await sendViaSendGrid({
        apiKey,
        fromName: settings.from_name,
        fromEmail: settings.from_email,
        replyTo: settings.reply_to || undefined,
        to: job.to_email,
        toName: job.to_name,
        subject: job.subject,
        html: job.html_body,
        text: job.text_body,
      });
      await adminClient
        .from("email_queue")
        .update({ status: "sent", sent_at: new Date().toISOString(), updated_at: new Date().toISOString() })
        .eq("id", job.id);
      await adminClient.from("email_log").insert({
        queue_id: job.id,
        to_email: job.to_email,
        subject: job.subject,
        template_slug: job.template_slug,
        trigger: job.trigger,
        status: "sent",
        provider_message_id: messageId,
      });
      sent++;
    } catch (err) {
      const message = (err as Error).message ?? "Unknown error";
      const nextStatus = (job.attempts ?? 0) + 1 >= 3 ? "failed" : "pending";
      await adminClient
        .from("email_queue")
        .update({ status: nextStatus, last_error: message, updated_at: new Date().toISOString() })
        .eq("id", job.id);
      await adminClient.from("email_log").insert({
        queue_id: job.id,
        to_email: job.to_email,
        subject: job.subject,
        template_slug: job.template_slug,
        trigger: job.trigger,
        status: nextStatus,
        error: message,
      });
      failed++;
    }
  }

  return { processed: (jobs ?? []).length, sent, failed };
}

async function testSend(adminClient: ReturnType<typeof createClient>, to: string) {
  const apiKey = Deno.env.get("SENDGRID_API_KEY");
  if (!apiKey) throw new Error("SENDGRID_API_KEY not configured");
  const settings = await getSettings(adminClient);
  if (!settings) throw new Error("email_settings not configured");
  const messageId = await sendViaSendGrid({
    apiKey,
    fromName: settings.from_name,
    fromEmail: settings.from_email,
    replyTo: settings.reply_to || undefined,
    to,
    subject: "Test email from Sycamore Info Hub",
    html:
      `<div style="font-family:system-ui,Segoe UI,sans-serif;max-width:520px;margin:0 auto;padding:24px;">` +
      `<h1 style="color:${settings.brand_color || "#0f6e42"};margin:0 0 12px;">It works!</h1>` +
      `<p>If you can read this, SendGrid is wired up and your Sycamore Info Hub can send email.</p>` +
      `</div>`,
    text: "It works! If you can read this, SendGrid is wired up.",
  });
  await adminClient.from("email_log").insert({
    to_email: to,
    subject: "Test email from Sycamore Info Hub",
    template_slug: null,
    trigger: "test",
    status: "sent",
    provider_message_id: messageId,
  });
  return { sent: true, messageId };
}

function isServiceRoleBearer(authHeader: string) {
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return token.length > 0 && svc.length > 0 && token === svc;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const url = new URL(req.url);
    const action = url.pathname.split("/").pop() ?? "";

    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const isService = isServiceRoleBearer(authHeader);
    const systemActions = new Set(["run_queue", "daily_reminders", "weekly_digest"]);

    if (!isService) {
      const { admin: isAdmin } = await requireAdmin(authHeader);
      if (!isAdmin) return json({ error: "Admin access required" }, 403);
    }

    if (action === "queue_announcement") {
      const body = await req.json().catch(() => ({}));
      if (!body.announcement_id) return json({ error: "announcement_id required" }, 400);
      return json(await queueAnnouncement(adminClient, body.announcement_id));
    }
    if (action === "run_queue") {
      return json(await runQueue(adminClient, 50));
    }
    if (action === "test_send") {
      const body = await req.json().catch(() => ({}));
      if (!body.to) return json({ error: "to required" }, 400);
      return json(await testSend(adminClient, body.to));
    }
    if (action === "daily_reminders") {
      const body = await req.json().catch(() => ({}));
      const lead = Number(body.lead_days) || 3;
      const out = await dailyReminders(adminClient, lead);
      if (systemActions.has(action)) runQueue(adminClient, 50).catch(() => {});
      return json(out);
    }
    if (action === "weekly_digest") {
      const out = await weeklyDigest(adminClient);
      runQueue(adminClient, 50).catch(() => {});
      return json(out);
    }
    if (action === "broadcast") {
      const body = await req.json().catch(() => ({}));
      if (!body.subject || !body.body_html) return json({ error: "subject and body_html required" }, 400);
      const out = await broadcast(adminClient, {
        subject: body.subject,
        heading: body.heading || body.subject,
        body_html: body.body_html,
        audience: body.audience === "department" ? "department" : "all",
        department_id: body.department_id,
      });
      runQueue(adminClient, 50).catch(() => {});
      return json(out);
    }
    if (action === "unsubscribe") {
      const token = url.searchParams.get("token") || "";
      if (!token) return json({ error: "token required" }, 400);
      const { data } = await adminClient
        .from("notification_preferences")
        .select("id")
        .eq("unsubscribe_token", token)
        .maybeSingle();
      if (!data) return json({ error: "Invalid token" }, 404);
      await adminClient
        .from("notification_preferences")
        .update({
          email_mentions: false,
          email_announcements: false,
          email_weekly_digest: false,
          email_event_reminders: false,
          email_broadcasts: false,
          updated_at: new Date().toISOString(),
        })
        .eq("id", data.id);
      return json({ ok: true });
    }
    return json({ error: "Unknown action" }, 404);
  } catch (e) {
    return json({ error: (e as Error).message ?? "Unexpected error" }, 500);
  }
});
