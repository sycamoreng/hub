import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, X-Client-Info, Apikey",
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
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<[^>]+>/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

async function sendViaSendGrid(args: {
  apiKey: string;
  fromName: string;
  fromEmail: string;
  to: string;
  toName?: string;
  subject: string;
  html: string;
}) {
  const body = {
    personalizations: [{ to: [{ email: args.to, name: args.toName || undefined }] }],
    from: { email: args.fromEmail, name: args.fromName },
    subject: args.subject,
    content: [
      { type: "text/plain", value: stripHtml(args.html) },
      { type: "text/html", value: args.html },
    ],
  };

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
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

    const today = new Date();
    const month = today.getMonth() + 1;
    const day = today.getDate();
    const year = today.getFullYear();

    // --- BIRTHDAYS ---
    const { data: birthdayStaff } = await supabase
      .from("staff_private_data")
      .select("id, date_of_birth")
      .not("date_of_birth", "is", null);

    const birthdayIds: string[] = [];
    if (birthdayStaff) {
      for (const row of birthdayStaff) {
        const dob = new Date(row.date_of_birth);
        if (dob.getMonth() + 1 === month && dob.getDate() === day) {
          birthdayIds.push(row.id);
        }
      }
    }

    // --- WORK ANNIVERSARIES ---
    const { data: anniversaryStaff } = await supabase
      .from("staff_members")
      .select("id, full_name, email, joined_date, auth_user_id")
      .eq("is_active", true)
      .not("joined_date", "is", null);

    const anniversaryPeople: { id: string; full_name: string; email: string; years: number; auth_user_id: string | null }[] = [];
    if (anniversaryStaff) {
      for (const row of anniversaryStaff) {
        const joined = new Date(row.joined_date);
        if (joined.getMonth() + 1 === month && joined.getDate() === day) {
          const years = year - joined.getFullYear();
          if (years > 0) {
            anniversaryPeople.push({
              id: row.id,
              full_name: row.full_name,
              email: row.email,
              years,
              auth_user_id: row.auth_user_id,
            });
          }
        }
      }
    }

    // Get birthday staff details
    let birthdayPeople: { id: string; full_name: string; email: string; auth_user_id: string | null }[] = [];
    if (birthdayIds.length > 0) {
      const { data } = await supabase
        .from("staff_members")
        .select("id, full_name, email, auth_user_id")
        .in("id", birthdayIds)
        .eq("is_active", true);
      birthdayPeople = data ?? [];
    }

    // Get email settings and templates
    const { data: emailSettings } = await supabase
      .from("email_settings")
      .select("*")
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();

    const sendGridKey = Deno.env.get("SENDGRID_API_KEY");
    const fromEmail = (emailSettings as any)?.from_email ?? "no-reply@sycamore.ng";
    const fromName = (emailSettings as any)?.from_name ?? "Sycamore";

    const { data: birthdayTemplate } = await supabase
      .from("email_templates")
      .select("*")
      .eq("slug", "staff_birthday")
      .maybeSingle();

    const { data: anniversaryTemplate } = await supabase
      .from("email_templates")
      .select("*")
      .eq("slug", "staff_work_anniversary")
      .maybeSingle();

    // Get all active staff for sending company-wide notifications
    const { data: allActiveStaff } = await supabase
      .from("staff_members")
      .select("id, full_name, auth_user_id")
      .eq("is_active", true);

    const results = { birthdays: 0, anniversaries: 0, notifications: 0 };

    // --- Send birthday notifications ---
    for (const person of birthdayPeople) {
      const firstName = person.full_name.split(/\s+/)[0] || person.full_name;

      // Send personal email to the birthday person
      if (sendGridKey && birthdayTemplate && birthdayTemplate.is_active) {
        try {
          const vars: Record<string, string> = {
            first_name: firstName,
            full_name: person.full_name,
          };
          await sendViaSendGrid({
            apiKey: sendGridKey,
            fromName,
            fromEmail,
            to: person.email,
            toName: person.full_name,
            subject: render(birthdayTemplate.subject, vars),
            html: render(birthdayTemplate.html_body, vars),
          });
        } catch {
          // non-fatal
        }
      }

      // Create in-app notifications for everyone (so they know it's someone's birthday)
      if (allActiveStaff) {
        const notifications = allActiveStaff
          .filter((s) => s.auth_user_id && s.id !== person.id)
          .map((s) => ({
            recipient_id: s.auth_user_id!,
            actor_id: person.auth_user_id || null,
            type: "birthday",
            title: `It's ${firstName}'s birthday today!`,
            body: `Wish ${person.full_name} a happy birthday.`,
            link: `/profile/${person.id}`,
          }));

        if (notifications.length > 0) {
          const { error } = await supabase.from("notifications").insert(notifications);
          if (!error) results.notifications += notifications.length;
        }
      }

      results.birthdays++;
    }

    // --- Send anniversary notifications ---
    for (const person of anniversaryPeople) {
      const firstName = person.full_name.split(/\s+/)[0] || person.full_name;
      const yearLabel = person.years === 1 ? "1 year" : `${person.years} years`;

      // Send personal email
      if (sendGridKey && anniversaryTemplate && anniversaryTemplate.is_active) {
        try {
          const vars: Record<string, string> = {
            first_name: firstName,
            full_name: person.full_name,
            years: String(person.years),
            year_label: yearLabel,
          };
          await sendViaSendGrid({
            apiKey: sendGridKey,
            fromName,
            fromEmail,
            to: person.email,
            toName: person.full_name,
            subject: render(anniversaryTemplate.subject, vars),
            html: render(anniversaryTemplate.html_body, vars),
          });
        } catch {
          // non-fatal
        }
      }

      // In-app notifications
      if (allActiveStaff) {
        const notifications = allActiveStaff
          .filter((s) => s.auth_user_id && s.id !== person.id)
          .map((s) => ({
            recipient_id: s.auth_user_id!,
            actor_id: person.auth_user_id || null,
            type: "anniversary",
            title: `${firstName} marks ${yearLabel} at Sycamore!`,
            body: `Congratulate ${person.full_name} on their work anniversary.`,
            link: `/profile/${person.id}`,
          }));

        if (notifications.length > 0) {
          const { error } = await supabase.from("notifications").insert(notifications);
          if (!error) results.notifications += notifications.length;
        }
      }

      results.anniversaries++;
    }

    return json({
      date: today.toISOString().slice(0, 10),
      birthdays: results.birthdays,
      anniversaries: results.anniversaries,
      notifications_sent: results.notifications,
    });
  } catch (e) {
    return json({ error: (e as Error).message ?? "Unexpected error" }, 500);
  }
});
