import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, X-Client-Info, Apikey",
};

const GENRES = [
  "Chill Vibes",
  "High Energy",
  "Throwback Thursday",
  "Feel-Good Anthems",
  "Deep Focus",
  "Friday Party Mix",
  "Afrobeats & Afropop",
  "R&B & Soul",
  "Workout Motivation",
  "Love Songs",
  "Indie & Alternative",
  "Hip-Hop Essentials",
  "90s Classics",
  "2000s Hits",
  "Acoustic Unplugged",
  "Latin Heat",
  "Electronic & Dance",
  "Gospel & Worship",
  "Jazz & Blues",
  "Pop Hits",
  "Amapiano",
  "Reggae & Dancehall",
  "Country Roads",
  "Relaxing Piano",
  "80s Retro",
  "Movie Soundtracks",
  "Afro-Fusion",
  "UK Drill & Grime",
  "Rock Anthems",
  "Naija Oldies",
  "3 Step & Sgija",
  "Afro-House",
  "Deep House",
  "EDM Bangers",
  "Alte & New Wave",
  "Drill & Trap",
  "Baile Funk & Global Bass",
  "Lo-fi & Study Beats",
  "Afro-Soul",
  "Kompa & Zouk",
  "Gqom",
  "Soulection & Future Beats",
  "Dancehall & Bashment",
  "Neo-Soul",
  "Highlife Classics",
];

function getNextMonday(): string {
  const now = new Date();
  const day = now.getUTCDay();
  const daysUntilMonday = day === 0 ? 1 : 8 - day;
  const next = new Date(now);
  next.setUTCDate(now.getUTCDate() + daysUntilMonday);
  return next.toISOString().slice(0, 10);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

    const nextMonday = getNextMonday();

    // Check if next week's playlist already exists
    const { data: existing } = await supabase
      .from("playlist_weeks")
      .select("id")
      .eq("week_start", nextMonday)
      .eq("is_staff_playlist", false)
      .maybeSingle();

    if (existing) {
      return new Response(
        JSON.stringify({ message: "Playlist already exists for " + nextMonday }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get recent themes to avoid repetition
    const { data: recentWeeks } = await supabase
      .from("playlist_weeks")
      .select("theme")
      .eq("is_staff_playlist", false)
      .order("week_start", { ascending: false })
      .limit(8);

    const recentThemes = new Set(
      (recentWeeks ?? []).map((w: any) => w.theme?.toLowerCase()).filter(Boolean)
    );

    // Pick a genre that wasn't used recently
    const available = GENRES.filter(
      (g) => !recentThemes.has(g.toLowerCase())
    );
    const pool = available.length > 0 ? available : GENRES;
    const chosen = pool[Math.floor(Math.random() * pool.length)];

    // Create the new playlist week
    const { data: created, error } = await supabase
      .from("playlist_weeks")
      .insert({
        week_start: nextMonday,
        theme: chosen,
        is_staff_playlist: false,
      })
      .select("id, week_start, theme")
      .maybeSingle();

    if (error) throw error;

    return new Response(
      JSON.stringify({
        message: "Created playlist for " + nextMonday,
        theme: chosen,
        id: created?.id,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: (e as Error).message ?? "Unexpected error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
