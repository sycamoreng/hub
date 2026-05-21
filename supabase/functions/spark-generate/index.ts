import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, X-Client-Info, Apikey",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) {
      return new Response(
        JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Determine how many days of sparks to generate (fill the next 3 days)
    const today = new Date();
    const daysToGenerate = 3;
    const datesToFill: string[] = [];

    for (let i = 0; i < daysToGenerate; i++) {
      const d = new Date(today);
      d.setDate(d.getDate() + i);
      datesToFill.push(d.toISOString().split("T")[0]);
    }

    // Check which dates already have sparks
    const { data: existingSparks } = await supabase
      .from("daily_sparks")
      .select("active_on")
      .in("active_on", datesToFill);

    const existingDates = new Set((existingSparks || []).map((s: any) => s.active_on));
    const missingDates = datesToFill.filter((d) => !existingDates.has(d));

    if (missingDates.length === 0) {
      return new Response(
        JSON.stringify({ message: "All upcoming days already have sparks", dates: datesToFill }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get recent sparks to avoid repetition
    const { data: recentSparks } = await supabase
      .from("daily_sparks")
      .select("question")
      .order("active_on", { ascending: false })
      .limit(30);

    const recentQuestions = (recentSparks || []).map((s: any) => s.question).join("\n- ");

    // Get company context for relevant questions
    const { data: companyInfo } = await supabase
      .from("company_info")
      .select("name, industry, description")
      .limit(1)
      .maybeSingle();

    const companyContext = companyInfo
      ? `The company is called ${companyInfo.name || "Sycamore"}. ${companyInfo.description || ""}`
      : "The company is called Sycamore, a fintech/technology company in Nigeria.";

    // Generate sparks via AI
    const aiResponse = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": anthropicKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-20250514",
        max_tokens: 2048,
        messages: [
          {
            role: "user",
            content: `You are generating trivia questions for a "Daily Spark" engagement feature at a workplace. Staff answer one question per day to earn points and stay engaged.

${companyContext}

Generate exactly ${missingDates.length} trivia questions. Each question should be fun, educational, and have exactly 4 multiple-choice options with one correct answer.

Mix the following categories:
- General knowledge and fun facts
- Tech/science trivia
- Pop culture and entertainment
- History and geography
- Business and finance literacy
- Brain teasers and logic puzzles
- Nigerian culture and African knowledge (occasional)

Rules:
- Questions should be interesting and spark curiosity
- Difficulty should be moderate (not too easy, not obscure)
- Avoid controversial, political, or sensitive topics
- Each question must have exactly 4 options
- Mark the correct answer index (0-based)

${recentQuestions ? `Avoid these recent questions:\n- ${recentQuestions}` : ""}

Return ONLY a JSON array with this format, no other text:
[
  {
    "question": "What is the question?",
    "options": ["Option A", "Option B", "Option C", "Option D"],
    "correct_index": 0
  }
]`,
          },
        ],
      }),
    });

    if (!aiResponse.ok) {
      const errText = await aiResponse.text();
      return new Response(
        JSON.stringify({ error: "AI generation failed", details: errText }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const aiData = await aiResponse.json();
    const rawText = aiData.content?.[0]?.text || "[]";

    let sparks: { question: string; options: string[]; correct_index: number }[];
    try {
      const jsonMatch = rawText.match(/\[[\s\S]*\]/);
      sparks = JSON.parse(jsonMatch ? jsonMatch[0] : rawText);
      if (!Array.isArray(sparks) || sparks.length === 0) {
        throw new Error("No valid sparks generated");
      }
    } catch {
      return new Response(
        JSON.stringify({ error: "Failed to parse AI response", raw: rawText.slice(0, 200) }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Insert sparks for missing dates
    const inserted: string[] = [];
    for (let i = 0; i < missingDates.length && i < sparks.length; i++) {
      const spark = sparks[i];
      if (!spark.question || !Array.isArray(spark.options) || spark.options.length !== 4) {
        continue;
      }

      const { error } = await supabase.from("daily_sparks").insert({
        active_on: missingDates[i],
        kind: "trivia",
        question: spark.question,
        options: spark.options,
        correct_index: spark.correct_index,
        points_award: 5,
        is_active: true,
      });

      if (!error) {
        inserted.push(missingDates[i]);
      }
    }

    return new Response(
      JSON.stringify({
        message: `Generated ${inserted.length} new sparks`,
        dates: inserted,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: (e as Error).message ?? "Unexpected error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
