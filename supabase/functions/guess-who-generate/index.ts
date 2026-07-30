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

    const { data: staff } = await supabase
      .from("staff_members")
      .select(
        "id, full_name, role, bio, joined_date, gender, department_id, team_id, level, location_id, manager_id"
      )
      .eq("is_active", true)
      .eq("directory_visible", true);

    if (!staff || staff.length === 0) {
      return new Response(
        JSON.stringify({ error: "No eligible staff found" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const { data: recentPuzzles } = await supabase
      .from("guess_who_puzzles")
      .select("staff_id")
      .gte("puzzle_date", thirtyDaysAgo.toISOString().split("T")[0]);

    const recentIds = new Set((recentPuzzles || []).map((p: any) => p.staff_id));
    const eligible = staff.filter((s: any) => !recentIds.has(s.id));
    const pool = eligible.length > 0 ? eligible : staff;

    const chosen = pool[Math.floor(Math.random() * pool.length)];

    // Gather rich context
    let departmentName = "";
    if (chosen.department_id) {
      const { data: dept } = await supabase
        .from("departments")
        .select("name")
        .eq("id", chosen.department_id)
        .maybeSingle();
      departmentName = dept?.name || "";
    }

    let teamName = "";
    if (chosen.team_id) {
      const { data: team } = await supabase
        .from("teams")
        .select("name")
        .eq("id", chosen.team_id)
        .maybeSingle();
      teamName = team?.name || "";
    }

    let locationName = "";
    let cityName = "";
    if (chosen.location_id) {
      const { data: loc } = await supabase
        .from("locations")
        .select("name, city")
        .eq("id", chosen.location_id)
        .maybeSingle();
      locationName = loc?.name || "";
      cityName = loc?.city || "";
    }

    let managerName = "";
    if (chosen.manager_id) {
      const { data: mgr } = await supabase
        .from("staff_members")
        .select("full_name")
        .eq("id", chosen.manager_id)
        .maybeSingle();
      managerName = mgr?.full_name || "";
    }

    const { data: reports } = await supabase
      .from("staff_members")
      .select("id")
      .eq("manager_id", chosen.id)
      .eq("is_active", true);
    const directReportsCount = reports?.length ?? 0;

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

    // Calculate tenure details
    let tenureHint = "";
    let joinMonth = "";
    let joinYear = "";
    if (chosen.joined_date) {
      const joined = new Date(chosen.joined_date);
      const now = new Date();
      const months = (now.getFullYear() - joined.getFullYear()) * 12 + (now.getMonth() - joined.getMonth());
      joinMonth = joined.toLocaleString("en-US", { month: "long" });
      joinYear = String(joined.getFullYear());
      if (months < 6) tenureHint = "less than 6 months";
      else if (months < 12) tenureHint = "less than a year";
      else if (months < 18) tenureHint = "about a year";
      else tenureHint = `about ${Math.floor(months / 12)} years`;
    }

    // Count peers in same department
    let deptSize = 0;
    if (chosen.department_id) {
      const { data: peers } = await supabase
        .from("staff_members")
        .select("id")
        .eq("department_id", chosen.department_id)
        .eq("is_active", true);
      deptSize = peers?.length ?? 0;
    }

    // Build rich context for AI
    const context = [
      `Full name: ${chosen.full_name}`,
      chosen.role ? `Role/title: ${chosen.role}` : "",
      departmentName ? `Department: ${departmentName} (${deptSize} people in this department)` : "",
      teamName ? `Team: ${teamName}` : "",
      locationName ? `Office: ${locationName}${cityName ? ` in ${cityName}` : ""}` : "",
      chosen.gender ? `Gender: ${chosen.gender}` : "",
      chosen.level ? `Level/seniority: ${chosen.level}` : "",
      managerName ? `Reports to: ${managerName}` : "",
      directReportsCount > 0 ? `Manages ${directReportsCount} direct report${directReportsCount > 1 ? "s" : ""}` : "Individual contributor (no direct reports)",
      tenureHint ? `Has been with the company for ${tenureHint}` : "",
      joinMonth && joinYear ? `Joined in ${joinMonth} ${joinYear}` : "",
      chosen.bio ? `Bio/about: ${chosen.bio}` : "",
    ]
      .filter(Boolean)
      .join("\n");

    let clues: string[];
    let aiUsed = false;

    const cluePrompt = `You are generating clues for a "Guess Who" game at a company called Sycamore (a fintech in Lagos, Nigeria). Sycamore staff members are called Sytizens. Other Sytizens will try to guess which Sytizen is being described.

Here is everything we know about the mystery person:
${context}

Generate exactly 5 clues as a JSON array. Each clue should be a JSON object with "category" and "text" fields.

Categories to use (pick the most fitting for each clue):
- "vibe" (personality/energy/work-style observation)
- "location" (office, city, workspace)
- "team" (department, team, who they work with)
- "role" (what they do, their craft, responsibilities)
- "tenure" (how long they've been around, when they joined)
- "connections" (who they report to, how many people they manage, cross-team work)
- "fun_fact" (anything quirky, creative, or memorable about them)

Rules:
- NEVER include the person's first name, last name, or any part of their name
- NEVER include their email address
- Clue 1: Very vague, atmospheric, could apply to many people (use "vibe" or "fun_fact")
- Clue 2: Slightly narrowing — location or broad team hint
- Clue 3: Moderate hint — role type or connections
- Clue 4: Quite specific — exact department or reporting line
- Clue 5: Very specific — makes it clear if you know the person (combine role + tenure + team details)
- Be creative, playful, use metaphors and wordplay where possible
- Write in a warm, fun tone — like a fellow Sytizen describing someone at a team social
- IMPORTANT: The ONLY correct term for a Sycamore staff member is "Sytizen". NEVER use "Sycamorite", "Sycamorean", "Sycamorer", or any other invented variation. If you refer to staff at all, always say "Sytizen(s)".

Return ONLY a JSON array, no other text. Example:
[{"category":"vibe","text":"This person brings sunshine energy to every standup."},{"category":"location","text":"You'll find them in the city that never sleeps... on the Mainland."},{"category":"team","text":"Their crew keeps customers smiling."},{"category":"role","text":"They lead the charge on user satisfaction metrics."},{"category":"connections","text":"With 5 people looking up to them, they've been shaping CX since 2022."}]`;

    function parseCluesFromText(rawText: string): Array<{ category: string; text: string }> | null {
      const cleaned = rawText.replace(/```(?:json)?\s*/g, "").replace(/```/g, "").trim();
      const jsonMatch = cleaned.match(/\[[\s\S]*\]/);
      try {
        const parsed = JSON.parse(jsonMatch ? jsonMatch[0] : cleaned);
        if (Array.isArray(parsed) && parsed.length === 5) {
          if (typeof parsed[0] === "string") {
            return parsed.map((t: string, i: number) => ({
              category: ["vibe", "location", "team", "role", "tenure"][i] || "vibe",
              text: t,
            }));
          }
          if (parsed[0].text) return parsed;
        }
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
            model: "claude-sonnet-4-20250514",
            max_tokens: 1024,
            messages: [{ role: "user", content: cluePrompt }],
          }),
        });

        if (aiResponse.ok) {
          const aiData = await aiResponse.json();
          const rawText = aiData.content?.[0]?.text || "[]";
          const parsed = parseCluesFromText(rawText);
          if (parsed) { clues = parsed.map(c => JSON.stringify(c)); aiUsed = true; }
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
          if (parsed) { clues = parsed.map(c => JSON.stringify(c)); aiUsed = true; }
        } else {
          console.error("Gemini API error:", geminiResponse.status);
        }
      } catch (gemErr: any) {
        console.error("Gemini exception:", gemErr?.message);
      }
    }

    if (!aiUsed) {
      const pronoun = chosen.gender === "Female" ? "She" : chosen.gender === "Male" ? "He" : "This person";
      clues = [
        JSON.stringify({ category: "vibe", text: `${pronoun} is a proud member of the Sycamore family${cityName ? ` based in ${cityName}` : ""}.` }),
        JSON.stringify({ category: "location", text: locationName ? `You'll find them at the ${locationName}.` : "This person brings energy and dedication to work every day." }),
        JSON.stringify({ category: "team", text: departmentName ? `${pronoun} is part of the ${departmentName} department${deptSize > 1 ? ` (one of ${deptSize})` : ""}.` : teamName ? `${pronoun} works with the ${teamName} team.` : "This person is well-known across the organisation." }),
        JSON.stringify({ category: "connections", text: managerName ? `${pronoun} reports to ${managerName}${directReportsCount > 0 ? ` and manages ${directReportsCount} people` : ""}.` : directReportsCount > 0 ? `${pronoun} manages ${directReportsCount} direct report${directReportsCount > 1 ? "s" : ""}.` : `${pronoun} is an individual contributor.` }),
        JSON.stringify({ category: "role", text: `${pronoun}${chosen.role ? ` works as ${chosen.role}` : ""}${tenureHint ? `, having been here for ${tenureHint}` : ""}${departmentName ? ` in ${departmentName}` : ""}.` }),
      ];
    }

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
        ai_used: aiUsed,
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
