import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, X-Client-Info, Apikey",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function generateRiddle(word: string): Promise<string | null> {
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
  const geminiKey = Deno.env.get("GEMINI_API_KEY");

  const prompt = `Write a single cryptic riddle for the English word "${word}" in EXACTLY ONE short sentence (max 20 words). The riddle should hint at what the word means or evokes, WITHOUT ever using the word itself, any close variant of it, or a direct synonym. Make it clever, poetic, and vague, so a smart person could plausibly guess after some thought. Do not preface with "Riddle:", quotes, or any commentary. Return only the riddle sentence.`;

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
          max_tokens: 200,
          messages: [{ role: "user", content: prompt }],
        }),
      });
      if (res.ok) {
        const data = await res.json();
        const text = (data.content?.[0]?.text || "").trim();
        if (text) return text.replace(/^["']|["']$/g, "").trim();
      }
    } catch (err: any) {
      console.error("Anthropic riddle error:", err?.message);
    }
  }

  if (geminiKey) {
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { temperature: 0.9, maxOutputTokens: 200 },
          }),
        },
      );
      if (res.ok) {
        const data = await res.json();
        const parts = data.candidates?.[0]?.content?.parts || [];
        const text = parts
          .filter((p: any) => p.text)
          .map((p: any) => p.text)
          .join("")
          .trim();
        if (text) return text.replace(/^["']|["']$/g, "").trim();
      }
    } catch (err: any) {
      console.error("Gemini riddle error:", err?.message);
    }
  }

  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return jsonResponse({ error: "unauthorized" }, 401);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData?.user) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }
    const uid = userData.user.id;

    const body = await req.json().catch(() => ({}));
    const matchId = body?.match_id;
    if (!matchId || typeof matchId !== "string") {
      return jsonResponse({ error: "match_id required" }, 400);
    }

    const { data: match, error: matchErr } = await admin
      .from("wordle_matches")
      .select("id, status, target_word, hint_riddle")
      .eq("id", matchId)
      .maybeSingle();
    if (matchErr || !match) {
      return jsonResponse({ error: "room not found" }, 404);
    }
    if (match.status !== "active") {
      return jsonResponse({ error: "not active" }, 400);
    }

    const { data: participant } = await admin
      .from("wordle_match_participants")
      .select("status, eliminated")
      .eq("match_id", matchId)
      .eq("user_id", uid)
      .maybeSingle();
    if (!participant || participant.status === "left" || participant.eliminated) {
      return jsonResponse({ error: "not participating" }, 403);
    }

    if (match.hint_riddle && match.hint_riddle.trim().length > 0) {
      return jsonResponse({ hint: match.hint_riddle, level: 1, cached: true });
    }

    const riddle = await generateRiddle(match.target_word);
    if (!riddle) {
      const fallback = `A word of ${match.target_word.length} letters — hidden in plain sight.`;
      await admin
        .from("wordle_matches")
        .update({ hint_riddle: fallback })
        .eq("id", matchId)
        .is("hint_riddle", null);
      return jsonResponse({ hint: fallback, level: 1, cached: false, fallback: true });
    }

    await admin
      .from("wordle_matches")
      .update({ hint_riddle: riddle })
      .eq("id", matchId)
      .is("hint_riddle", null);

    const { data: fresh } = await admin
      .from("wordle_matches")
      .select("hint_riddle")
      .eq("id", matchId)
      .maybeSingle();

    return jsonResponse({
      hint: fresh?.hint_riddle || riddle,
      level: 1,
      cached: false,
    });
  } catch (err: any) {
    console.error("wordle-hint-riddle exception:", err?.message);
    return jsonResponse({ error: err?.message || "unknown error" }, 500);
  }
});
