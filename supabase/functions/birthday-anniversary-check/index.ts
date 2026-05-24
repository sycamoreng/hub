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

interface StaffContext {
  full_name: string;
  role?: string;
  department?: string;
  gender?: string;
  years?: number;
}

async function generateAIMessage(
  type: "birthday" | "anniversary",
  person: StaffContext
): Promise<string | null> {
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  const geminiKey = Deno.env.get("GEMINI_API_KEY");

  if (!anthropicKey && !geminiKey) return null;

  const firstName = person.full_name.split(/\s+/)[0] || person.full_name;
  const pronoun = person.gender === "Female" ? "her" : person.gender === "Male" ? "his" : "their";
  const possessive = person.gender === "Female" ? "She" : person.gender === "Male" ? "He" : "They";

  const context = [
    `Name: ${person.full_name}`,
    person.role ? `Role: ${person.role}` : null,
    person.department ? `Department: ${person.department}` : null,
    person.gender ? `Gender: ${person.gender}` : null,
    type === "anniversary" && person.years ? `Years at company: ${person.years}` : null,
  ].filter(Boolean).join("\n");

  const prompt = type === "birthday"
    ? `Write a warm, fun birthday message for a colleague at a company called Sycamore. The message should come from "Sycamore Bot" (a friendly company bot) wishing the person happy birthday on behalf of the whole team.

Person details:
${context}

Rules:
- Keep it 2-3 sentences max
- Be warm, celebratory, and personalized to their role/department if possible
- Use ${pronoun}/${possessive} pronouns appropriately
- End with an invitation for colleagues to drop reactions/comments
- Do NOT use hashtags
- Do NOT start with "Hey everyone" or similar generic openings
- Start directly addressing the celebration (e.g. "Happy Birthday, ${firstName}!")
- Be creative and varied in tone - avoid generic corporate language
- You can reference their role/department in a fun way

Return ONLY the message text, no quotes or extra formatting.`
    : `Write a warm work anniversary message for a colleague at a company called Sycamore. The message should come from "Sycamore Bot" (a friendly company bot) celebrating the person's milestone on behalf of the whole team.

Person details:
${context}

Rules:
- Keep it 2-3 sentences max
- Be warm, celebratory, and reference their ${person.years} year${person.years === 1 ? "" : "s"} at the company
- Personalize to their role/department if possible
- Use ${pronoun}/${possessive} pronouns appropriately
- End with an invitation for colleagues to drop reactions/comments
- Do NOT use hashtags
- Do NOT start with "Hey everyone" or similar generic openings
- Start directly addressing the milestone (e.g. "Cheers to ${firstName}!")
- Be creative and varied in tone - avoid generic corporate language
- You can make playful references to their tenure or expertise

Return ONLY the message text, no quotes or extra formatting.`;

  function cleanResponse(text: string): string {
    return text.replace(/```[\s\S]*?```/g, "").replace(/^["']|["']$/g, "").trim();
  }

  // Try Anthropic first
  if (anthropicKey) {
    try {
      const res = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": anthropicKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: "claude-3-5-sonnet-20241022",
          max_tokens: 256,
          messages: [{ role: "user", content: prompt }],
        }),
      });
      if (res.ok) {
        const data = await res.json();
        const text = data.content?.[0]?.text;
        if (text) return cleanResponse(text);
      }
    } catch { /* fall through to Gemini */ }
  }

  // Try Gemini
  if (geminiKey) {
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { temperature: 0.9, maxOutputTokens: 4096 },
          }),
        }
      );
      if (res.ok) {
        const data = await res.json();
        const parts = data.candidates?.[0]?.content?.parts || [];
        const text = parts.filter((p: any) => p.text).map((p: any) => p.text).join("");
        if (text) return cleanResponse(text);
      }
    } catch { /* fall through */ }
  }

  return null;
}

async function broadcastToGoogleChat(
  webhookUrl: string,
  type: "birthday" | "anniversary",
  personName: string,
  message: string,
  years?: number
) {
  const emoji = type === "birthday" ? "\u{1F382}" : "\u{1F389}";
  const title = type === "birthday"
    ? `${emoji} Happy Birthday, ${personName}!`
    : `${emoji} ${personName} - ${years} Year${years === 1 ? "" : "s"} at Sycamore!`;

  const card = {
    cardsV2: [{
      cardId: `celebration-${Date.now()}`,
      card: {
        header: { title, imageUrl: "https://zefhzobaostawwramtfv.supabase.co/storage/v1/object/public/public-assets/logo-icon.png" },
        sections: [{
          widgets: [{ textParagraph: { text: message } }],
        }],
      },
    }],
  };

  try {
    const res = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(card),
    });
    return res.ok;
  } catch {
    return false;
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
      .select("id, full_name, email, joined_date, auth_user_id, role, department_id, gender")
      .eq("is_active", true)
      .not("joined_date", "is", null);

    const anniversaryPeople: { id: string; full_name: string; email: string; years: number; auth_user_id: string | null; role: string; department_id: string | null; gender: string | null }[] = [];
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
              role: row.role || "",
              department_id: row.department_id,
              gender: row.gender,
            });
          }
        }
      }
    }

    // Get birthday staff details
    let birthdayPeople: { id: string; full_name: string; email: string; auth_user_id: string | null; role: string; department_id: string | null; gender: string | null }[] = [];
    if (birthdayIds.length > 0) {
      const { data } = await supabase
        .from("staff_members")
        .select("id, full_name, email, auth_user_id, role, department_id, gender")
        .in("id", birthdayIds)
        .eq("is_active", true);
      birthdayPeople = (data ?? []).map((r: any) => ({
        id: r.id,
        full_name: r.full_name,
        email: r.email,
        auth_user_id: r.auth_user_id,
        role: r.role || "",
        department_id: r.department_id,
        gender: r.gender,
      }));
    }

    // Fetch departments for context
    const deptIds = [
      ...birthdayPeople.map(p => p.department_id),
      ...anniversaryPeople.map(p => p.department_id),
    ].filter(Boolean) as string[];

    let departmentMap: Record<string, string> = {};
    if (deptIds.length > 0) {
      const { data: depts } = await supabase
        .from("departments")
        .select("id, name")
        .in("id", [...new Set(deptIds)]);
      if (depts) {
        for (const d of depts) departmentMap[d.id] = d.name;
      }
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

    // Get celebration chat space config
    const { data: chatConfig } = await supabase
      .from("company_info")
      .select("info_value")
      .eq("info_key", "celebration_chat_space_id")
      .maybeSingle();

    let chatWebhookUrl: string | null = null;
    const chatSpaceId = (chatConfig as any)?.info_value;
    if (chatSpaceId) {
      const { data: space } = await supabase
        .from("google_chat_spaces")
        .select("webhook_url")
        .eq("id", chatSpaceId)
        .eq("is_active", true)
        .maybeSingle();
      chatWebhookUrl = (space as any)?.webhook_url || null;
    }

    const results = { birthdays: 0, anniversaries: 0, notifications: 0, posts: 0, chat_broadcasts: 0 };

    // --- Send birthday notifications and create posts ---
    for (const person of birthdayPeople) {
      const firstName = person.full_name.split(/\s+/)[0] || person.full_name;
      const department = person.department_id ? departmentMap[person.department_id] : undefined;

      // Generate AI message
      const aiMessage = await generateAIMessage("birthday", {
        full_name: person.full_name,
        role: person.role,
        department,
        gender: person.gender || undefined,
      });

      const postContent = aiMessage ||
        `Happy Birthday, ${person.full_name}! Wishing you an amazing day and a wonderful year ahead. Drop a comment or reaction to celebrate with ${firstName}!`;

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

      // Create bot-authored birthday post in the feed
      const { error: postErr } = await supabase.from("posts").insert({
        author_id: null,
        content: postContent,
        post_kind: "birthday",
        post_type: "celebration",
        template_data: { name: person.full_name, staff_id: person.id, auto: true, bot: true },
        is_published: true,
      });
      if (!postErr) results.posts++;

      // Broadcast to Google Chat
      if (chatWebhookUrl) {
        const sent = await broadcastToGoogleChat(chatWebhookUrl, "birthday", person.full_name, postContent);
        if (sent) results.chat_broadcasts++;
      }

      // Create in-app notifications for everyone
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

    // --- Send anniversary notifications and create posts ---
    for (const person of anniversaryPeople) {
      const firstName = person.full_name.split(/\s+/)[0] || person.full_name;
      const yearLabel = person.years === 1 ? "1 year" : `${person.years} years`;
      const department = person.department_id ? departmentMap[person.department_id] : undefined;

      // Generate AI message
      const aiMessage = await generateAIMessage("anniversary", {
        full_name: person.full_name,
        role: person.role,
        department,
        gender: person.gender || undefined,
        years: person.years,
      });

      const postContent = aiMessage ||
        `Congratulations to ${person.full_name} on ${yearLabel} at Sycamore! Thank you for your dedication and contributions. Drop a comment or reaction to celebrate with ${firstName}!`;

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

      // Create bot-authored anniversary post in the feed
      const { error: postErr } = await supabase.from("posts").insert({
        author_id: null,
        content: postContent,
        post_kind: "anniversary",
        post_type: "celebration",
        template_data: { name: person.full_name, years: person.years, staff_id: person.id, auto: true, bot: true },
        is_published: true,
      });
      if (!postErr) results.posts++;

      // Broadcast to Google Chat
      if (chatWebhookUrl) {
        const sent = await broadcastToGoogleChat(chatWebhookUrl, "anniversary", person.full_name, postContent, person.years);
        if (sent) results.chat_broadcasts++;
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
      posts_created: results.posts,
      chat_broadcasts: results.chat_broadcasts,
    });
  } catch (e) {
    return json({ error: (e as Error).message ?? "Unexpected error" }, 500);
  }
});
