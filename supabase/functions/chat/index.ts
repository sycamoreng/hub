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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );

    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData?.user) {
      return json({ error: "Not authenticated" }, 401);
    }
    const user = userData.user;

    const body = await req.json().catch(() => ({}));
    const message = (body.message ?? "").toString().trim();
    if (!message) return json({ error: "Empty message" }, 400);
    if (message.length > 2000) return json({ error: "Message too long" }, 400);

    const { data: settings } = await supabase
      .from("chatbot_settings")
      .select("*")
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();

    if (!settings || settings.is_enabled === false) {
      return json({ error: "Chatbot is disabled by admin." }, 403);
    }

    const since = new Date();
    since.setHours(0, 0, 0, 0);
    const { count: usedToday } = await supabase
      .from("chat_messages")
      .select("*", { count: "exact", head: true })
      .eq("user_id", user.id)
      .eq("role", "user")
      .gte("created_at", since.toISOString());

    const limit = Number(settings.max_messages_per_user_per_day) || 0;
    if (limit > 0 && (usedToday ?? 0) >= limit) {
      return json({ error: `Daily limit reached (${limit} messages). Try again tomorrow.` }, 429);
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return json({
        error: "AI service is not configured. An admin needs to add ANTHROPIC_API_KEY in Supabase edge function secrets.",
      }, 503);
    }

    const [products, tech, policies, benefits, contacts, comms, departments, locations, onboarding, leadership, company] = await Promise.all([
      supabase.from("products").select("name,tagline,description,category,status,target_market").eq("is_active", true),
      supabase.from("tech_stack").select("name,category,description,used_for").eq("is_active", true),
      supabase.from("policies").select("title,category,content").eq("is_active", true),
      supabase.from("benefits_perks").select("title,description,category"),
      supabase.from("key_contacts").select("name,role,department,email,phone,category,is_emergency"),
      supabase.from("communication_tools").select("name,description,category,is_primary"),
      supabase.from("departments").select("name,description,head_name,head_title"),
      supabase.from("locations").select("name,address,city,country,is_headquarters,location_type"),
      supabase.from("onboarding_steps").select("title,description,category,is_required").eq("is_active", true),
      supabase.from("leadership").select("full_name,title,tier,bio").eq("is_active", true),
      supabase.from("company_info").select("info_key,info_value"),
    ]);

    const kb = {
      company: company.data,
      products: products.data,
      technology: tech.data,
      policies: policies.data,
      benefits: benefits.data,
      contacts: contacts.data,
      communication_tools: comms.data,
      departments: departments.data,
      locations: locations.data,
      onboarding_steps: onboarding.data,
      leadership: leadership.data,
    };

    const { data: history } = await supabase
      .from("chat_messages")
      .select("role,content")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(10);

    const recent = (history ?? []).reverse().map((m: any) => ({
      role: m.role,
      content: m.content,
    }));

    const systemPrompt = [
      settings.system_prompt || "You are an internal assistant for Sycamore staff.",
      `Tone: ${settings.response_tone || "friendly and professional"}.`,
      settings.allowed_topics ? `You are allowed to discuss: ${settings.allowed_topics}.` : "",
      settings.blocked_topics ? `Refuse to discuss: ${settings.blocked_topics}. Politely redirect to relevant topics.` : "",
      "Use ONLY the JSON knowledgebase below to answer. If the answer is not in the knowledgebase, say so.",
      "Knowledgebase:",
      JSON.stringify(kb),
    ].filter(Boolean).join("\n\n");

    await supabase.from("chat_messages").insert({
      user_id: user.id,
      role: "user",
      content: message,
    });

    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-3-5-haiku-latest",
        max_tokens: 800,
        system: systemPrompt,
        messages: [...recent, { role: "user", content: message }],
      }),
    });

    if (!anthropicRes.ok) {
      const text = await anthropicRes.text();
      return json({ error: `AI service error: ${anthropicRes.status} ${text}` }, 502);
    }

    const result = await anthropicRes.json();
    const reply = result?.content?.[0]?.text ?? "(no response)";

    await supabase.from("chat_messages").insert({
      user_id: user.id,
      role: "assistant",
      content: reply,
    });

    return json({ reply });
  } catch (e) {
    return json({ error: (e as Error).message ?? "Unexpected error" }, 500);
  }
});
