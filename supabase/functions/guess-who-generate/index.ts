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

    // Generate clues using Anthropic
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) {
      return new Response(
        JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const aiResponse = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": anthropicKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-3-5-sonnet-20240620",
        max_tokens: 1024,
        messages: [
          {
            role: "user",
            content: `You are generating clues for a "Guess Who" game at a company called Sycamore. Staff will try to guess which colleague is being described based on your clues.

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
["clue 1", "clue 2", "clue 3", "clue 4", "clue 5"]`,
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

    // Parse the JSON array from the response
    let clues: string[];
    try {
      const jsonMatch = rawText.match(/\[[\s\S]*\]/);
      clues = JSON.parse(jsonMatch ? jsonMatch[0] : rawText);
      if (!Array.isArray(clues) || clues.length !== 5) {
        throw new Error("Expected exactly 5 clues");
      }
    } catch {
      clues = [
        "This person works at Sycamore.",
        departmentName ? `They are part of the ${departmentName} department.` : "They are a valued team member.",
        chosen.role ? `Their role involves ${chosen.role.toLowerCase()}.` : "They contribute to the company every day.",
        tenureHint ? `They have been here for ${tenureHint}.` : "They are well-known in the office.",
        chosen.gender === "Female" ? "She is someone you might see around the office." : "He is someone you might see around the office.",
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
