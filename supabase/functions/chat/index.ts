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

async function generateEmbedding(text: string): Promise<number[]> {
  const model = new Supabase.ai.Session("gte-small");
  const output = await model.run(text, { mean_pool: true, normalize: true });
  return Array.from(output as Float32Array);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

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

    // Service role client for vector search (bypasses RLS)
    const serviceClient = createClient(supabaseUrl, serviceRoleKey);

    // --- RAG: Semantic search for relevant knowledge base chunks ---
    let ragContext = "";
    try {
      const queryEmbedding = await generateEmbedding(message);
      const { data: matchedChunks } = await serviceClient.rpc("match_kb_chunks", {
        query_embedding: JSON.stringify(queryEmbedding),
        match_count: 8,
        min_similarity: 0.3,
      });

      if (matchedChunks && matchedChunks.length > 0) {
        const ragParts = matchedChunks.map(
          (c: { title: string; content: string; similarity: number }) =>
            `[${c.title}] (relevance: ${(c.similarity * 100).toFixed(0)}%)\n${c.content}`
        );
        ragContext = ragParts.join("\n\n---\n\n");
      }
    } catch {
      // RAG search failed, continue without it
    }

    // --- Structured knowledge from live tables (compact summary) ---
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

    // --- Conversation history ---
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

    // --- Build system prompt ---
    const systemParts = [
      settings.system_prompt || "You are an internal assistant for Sycamore staff.",
      `Tone: ${settings.response_tone || "friendly and professional"}.`,
      settings.allowed_topics ? `You are allowed to discuss: ${settings.allowed_topics}.` : "",
      settings.blocked_topics ? `Refuse to discuss: ${settings.blocked_topics}. Politely redirect to relevant topics.` : "",
      "",
      "You have two sources of knowledge:",
      "",
      "1. RELEVANT DOCUMENTS (retrieved by semantic search, most relevant to this query):",
      ragContext || "(No matching documents found for this query)",
      "",
      "2. LIVE COMPANY DATA (structured information from the system):",
      JSON.stringify(kb),
      "",
      "Use both sources to answer. Prioritize document knowledge when it's relevant. If the answer is not in either source, say so.",
    ].filter((s) => s !== undefined).join("\n");

    // --- Store user message ---
    await supabase.from("chat_messages").insert({
      user_id: user.id,
      role: "user",
      content: message,
    });

    // --- Call Claude ---
    const anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: 800,
        system: systemParts,
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
