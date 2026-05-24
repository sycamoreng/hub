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

    // Check if today's puzzle already exists
    const today = new Date().toISOString().split("T")[0];
    const { data: existing } = await supabase
      .from("guess_who_puzzles")
      .select("id")
      .eq("puzzle_date", today)
      .maybeSingle();

    if (existing) {
      return new Response(
        JSON.stringify({ message: "Puzzle already exists for today", date: today }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get all active staff with relevant info
    const { data: staff } = await supabase
      .from("staff_members")
      .select(
        "id, full_name, role, bio, joined_date, gender, department_id, team_id, level"
      )
      .eq("is_active", true)
      .eq("directory_visible", true);

    if (!staff || staff.length === 0) {
      return new Response(
        JSON.stringify({ error: "No eligible staff found" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get recently used staff (last 30 days) to avoid repeats
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const { data: recentPuzzles } = await supabase
      .from("guess_who_puzzles")
      .select("staff_id")
      .gte("puzzle_date", thirtyDaysAgo.toISOString().split("T")[0]);

    const recentIds = new Set((recentPuzzles || []).map((p: any) => p.staff_id));
    const eligible = staff.filter((s: any) => !recentIds.has(s.id));
    const pool = eligible.length > 0 ? eligible : staff;

    // Pick a random staff member
    const chosen = pool[Math.floor(Math.random() * pool.length)];

    // Get department name
    let departmentName = "";
    if (chosen.department_id) {
      const { data: dept } = await supabase
        .from("departments")
        .select("name")
        .eq("id", chosen.department_id)
        .maybeSingle();
      departmentName = dept?.name || "";
    }

    // Get team name
    let teamName = "";
    if (chosen.team_id) {
      const { data: team } = await supabase
        .from("teams")
        .select("name")
        .eq("id", chosen.team_id)
        .maybeSingle();
      teamName = team?.name || "";
    }

    // Check if they have an avatar
    const { data: authStaff } = await supabase
      .from("staff_members")
      .select("auth_user_id")
      .eq("id", chosen.id)
      .maybeSingle();

    let hasAvatar = false;
    if (authStaff?.auth_user_id) {
      const { data: profile } = await supabase
        .from("user_profiles")
        .select("avatar_url")
        .eq("user_id", authStaff.auth_user_id)
        .maybeSingle();
      hasAvatar = !!(profile?.avatar_url && profile.avatar_url.trim() !== "");
    }

    // Calculate tenure
    let tenureHint = "";
    if (chosen.joined_date) {
      const joined = new Date(chosen.joined_date);
      const now = new Date();
      const years = Math.floor(
        (now.getTime() - joined.getTime()) / (365.25 * 24 * 60 * 60 * 1000)
      );
      if (years < 1) tenureHint = "less than a year";
      else if (years === 1) tenureHint = "about a year";
      else tenureHint = `about ${years} years`;
    }

    // Build context for AI
    const context = [
      `Full name: ${chosen.full_name}`,
      chosen.role ? `Role/title: ${chosen.role}` : "",
      departmentName ? `Department: ${departmentName}` : "",
      teamName ? `Team: ${teamName}` : "",
      chosen.gender ? `Gender: ${chosen.gender}` : "",
      chosen.level ? `Level: ${chosen.level}` : "",
      tenureHint ? `Has been with the company for ${tenureHint}` : "",
      chosen.bio ? `Bio: ${chosen.bio}` : "",
    ]
      .filter(Boolean)
      .join("\n");

    // Generate clues - try Anthropic first, then Gemini, fall back to deterministic
    let clues: string[];
    let aiUsed = false;

    const cluePrompt = `You are generating clues for a "Guess Who" game at a company called Sycamore. Staff will try to guess which colleague is being described based on your clues.

Here is information about the mystery person:
${context}

Generate exactly 5 clues, ordered from most vague to most specific. The clues should be fun, creative, and descriptive without directly revealing the person's name. Use wordplay, metaphors, or creative descriptions where possible.

Rules:
- NEVER include the person's first name, last name, or any part of their name in any clue
- NEVER include their email address
- Clue 1 should be very vague (could apply to many people)
- Clue 2 should narrow it down slightly
- Clue 3 should give a moderate hint
- Clue 4 should be quite specific
- Clue 5 should make it fairly clear if you know the person

Return ONLY a JSON array of 5 strings, no other text. Example format:
["clue 1", "clue 2", "clue 3", "clue 4", "clue 5"]`;

    function parseCluesFromText(rawText: string): string[] | null {
      const cleaned = rawText.replace(/```(?:json)?\s*/g, "").replace(/```/g, "").trim();
      const jsonMatch = cleaned.match(/\[[\s\S]*\]/);
      try {
        const parsed = JSON.parse(jsonMatch ? jsonMatch[0] : cleaned);
        if (Array.isArray(parsed) && parsed.length === 5) return parsed;
      } catch { /* ignore */ }
      return null;
    }

    // Try Anthropic
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (anthropicKey) {
      try {
        const aiResponse = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": anthropicKey,
            "anthropic-version": "2023-06-01",
          },
          body: JSON.stringify({
            model: "claude-3-5-sonnet-20241022",
            max_tokens: 1024,
            messages: [{ role: "user", content: cluePrompt }],
          }),
        });

        if (aiResponse.ok) {
          const aiData = await aiResponse.json();
          const rawText = aiData.content?.[0]?.text || "[]";
          const parsed = parseCluesFromText(rawText);
          if (parsed) { clues = parsed; aiUsed = true; }
        } else {
          console.error("Anthropic API error:", aiResponse.status);
        }
      } catch (aiErr: any) {
        console.error("Anthropic exception:", aiErr?.message);
      }
    }

    // Try Gemini as fallback
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (geminiKey && !aiUsed) {
      try {
        const geminiResponse = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiKey}`,
          {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              contents: [{ parts: [{ text: cluePrompt }] }],
              generationConfig: { temperature: 0.8, maxOutputTokens: 4096 },
            }),
          }
        );

        if (geminiResponse.ok) {
          const geminiData = await geminiResponse.json();
          const parts = geminiData.candidates?.[0]?.content?.parts || [];
          const rawText = parts
            .filter((p: any) => p.text)
            .map((p: any) => p.text)
            .join("");
          const parsed = parseCluesFromText(rawText);
          if (parsed) { clues = parsed; aiUsed = true; }
        } else {
          console.error("Gemini API error:", geminiResponse.status);
        }
      } catch (gemErr: any) {
        console.error("Gemini exception:", gemErr?.message);
      }
    }

    if (!aiUsed) {
      const isFemale = chosen.gender === "Female";
      const isMale = chosen.gender === "Male";
      const pronoun = isFemale ? "She" : isMale ? "He" : "This person";
      const verb = (isFemale || isMale) ? "has" : "has";
      const verbBe = (isFemale || isMale) ? "is" : "is";
      clues = [
        "This person is a proud member of the Sycamore family.",
        departmentName
          ? `${pronoun} ${verbBe} part of the ${departmentName} team.`
          : "This person brings energy and dedication to work every day.",
        chosen.role
          ? `Their role: ${chosen.role}.`
          : teamName
          ? `${pronoun} works with the ${teamName} team.`
          : "This person is well-known across the organisation.",
        tenureHint
          ? `${pronoun} ${verb} been with Sycamore for ${tenureHint}.`
          : chosen.level
          ? `${pronoun} ${verbBe} at the ${chosen.level} level.`
          : `${pronoun} ${verbBe} someone many colleagues interact with regularly.`,
        chosen.level && tenureHint
          ? `At the ${chosen.level} level, with ${tenureHint} at Sycamore${departmentName ? ` in ${departmentName}` : ""}.`
          : `${pronoun} works${departmentName ? ` in ${departmentName}` : ""}${chosen.role ? ` as ${chosen.role}` : ""}.`,
      ];
    }

    // Insert the puzzle
    const { error: insertError } = await supabase
      .from("guess_who_puzzles")
      .insert({
        puzzle_date: today,
        staff_id: chosen.id,
        clues: clues,
        has_avatar: hasAvatar,
      });

    if (insertError) {
      return new Response(
        JSON.stringify({ error: "Failed to insert puzzle", details: insertError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({
        message: "Puzzle generated successfully",
        date: today,
        has_avatar: hasAvatar,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: err.message || "Unknown error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
