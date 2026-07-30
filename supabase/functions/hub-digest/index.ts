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
  return template.replace(
    /\{\{\s*([\w.]+)\s*\}\}/g,
    (_m, key) => vars[key] ?? ""
  );
}

function firstName(name?: string | null) {
  if (!name) return "there";
  return name.trim().split(/\s+/)[0] || "there";
}

function formatDate(d: string | Date) {
  return new Date(d).toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

function formatDateShort(d: string | Date) {
  return new Date(d).toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
  });
}

interface SectionConfig {
  key: string;
  label: string;
  enabled: boolean;
  max_items: number;
}

interface DigestStats {
  announcements_count: number;
  posts_count: number;
  birthdays_count: number;
  anniversaries_count: number;
  new_joiners_count: number;
  kudos_count: number;
  badges_count: number;
  events_count: number;
}

async function compileDigest(
  db: ReturnType<typeof createClient>,
  periodStart: Date,
  periodEnd: Date,
  sections: SectionConfig[]
) {
  const sinceIso = periodStart.toISOString();
  const untilIso = periodEnd.toISOString();
  const todayStr = new Date().toISOString().slice(0, 10);
  const nextWeekStr = new Date(Date.now() + 7 * 86400000)
    .toISOString()
    .slice(0, 10);

  const enabledKeys = new Set(
    sections.filter((s) => s.enabled).map((s) => s.key)
  );
  const getMax = (key: string) =>
    sections.find((s) => s.key === key)?.max_items ?? 5;

  const htmlSections: string[] = [];
  const plainSections: string[] = [];
  const stats: DigestStats = {
    announcements_count: 0,
    posts_count: 0,
    birthdays_count: 0,
    anniversaries_count: 0,
    new_joiners_count: 0,
    kudos_count: 0,
    badges_count: 0,
    events_count: 0,
  };

  // --- ANNOUNCEMENTS ---
  if (enabledKeys.has("announcements")) {
    const { data: ann } = await db
      .from("announcements")
      .select("title,summary,created_at")
      .eq("is_active", true)
      .gte("created_at", sinceIso)
      .lte("created_at", untilIso)
      .order("created_at", { ascending: false })
      .limit(getMax("announcements"));
    if (ann && ann.length > 0) {
      stats.announcements_count = ann.length;
      const cards = ann
        .map(
          (a: any) =>
            `<tr><td style="padding:8px 0;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="background:#ffffff;border:1px solid #e2e8f0;border-radius:10px;padding:14px 16px;"><div style="font-weight:700;color:#0b1a2c;font-size:13px;margin-bottom:3px;">${a.title}</div>${a.summary ? `<div style="color:#64748b;font-size:12px;line-height:1.5;">${a.summary}</div>` : ""}</td></tr></table></td></tr>`
        )
        .join("");
      htmlSections.push(
        card("&#128227;", "What you need to know", `The team shared ${ann.length} important update${ann.length > 1 ? "s" : ""} this period.`, `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${cards}</table>`)
      );
      plainSections.push(
        `WHAT YOU NEED TO KNOW\n${ann.map((a: any) => `- ${a.title}`).join("\n")}`
      );
    }
  }

  // --- FEED HIGHLIGHTS (most reacted posts) ---
  if (enabledKeys.has("feed_highlights")) {
    const { data: posts } = await db
      .from("posts")
      .select("id,content,created_at")
      .eq("is_published", true)
      .gte("created_at", sinceIso)
      .lte("created_at", untilIso)
      .order("created_at", { ascending: false })
      .limit(50);

    if (posts && posts.length > 0) {
      stats.posts_count = posts.length;
      const postIds = posts.map((p: any) => p.id);
      const { data: reactions } = await db
        .from("reactions")
        .select("target_id")
        .eq("target_type", "post")
        .in("target_id", postIds);

      const reactionCounts = new Map<string, number>();
      for (const r of reactions ?? []) {
        reactionCounts.set(
          r.target_id,
          (reactionCounts.get(r.target_id) || 0) + 1
        );
      }

      const sortedPosts = posts
        .map((p: any) => ({ ...p, reactions: reactionCounts.get(p.id) || 0 }))
        .sort((a: any, b: any) => b.reactions - a.reactions)
        .slice(0, getMax("feed_highlights"));

      const items = sortedPosts
        .map((p: any) => {
          const snippet = (p.content ?? "").slice(0, 100) + ((p.content ?? "").length > 100 ? "..." : "");
          const hearts = p.reactions > 0 ? ` <span style="color:#3087b9;font-weight:600;font-size:11px;">${p.reactions} &#10084;</span>` : "";
          return `<tr><td style="padding:6px 0;border-bottom:1px solid #f1f5f9;"><div style="color:#334155;font-size:12px;line-height:1.5;">"${snippet}"${hearts}</div></td></tr>`;
        })
        .join("");
      const narrative = posts.length === 1
        ? "One conversation stood out on the feed this period."
        : `${posts.length} conversations happened on the feed. Here are the ones that got people talking.`;
      htmlSections.push(
        card("&#128172;", "Conversations that sparked", narrative, `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${items}</table>`)
      );
      plainSections.push(
        `FEED HIGHLIGHTS\n${sortedPosts.map((p: any) => `- ${(p.content ?? "").slice(0, 100)}`).join("\n")}`
      );
    }
  }

  // --- BIRTHDAYS THIS PERIOD ---
  if (enabledKeys.has("birthdays")) {
    const { data: bdayStaff } = await db
      .from("staff_private_data")
      .select("id, date_of_birth");

    const { data: allStaff } = await db
      .from("staff_members")
      .select("id, full_name, role, department_id")
      .eq("is_active", true)
      .eq("directory_visible", true);

    const staffMap = new Map<string, any>();
    for (const s of allStaff ?? []) staffMap.set(s.id, s);

    const periodBirthdays: any[] = [];
    for (const sp of bdayStaff ?? []) {
      if (!sp.date_of_birth) continue;
      const dob = new Date(sp.date_of_birth);
      const m = dob.getMonth() + 1;
      const d = dob.getDate();
      const bdayThisYear = new Date(periodStart.getFullYear(), m - 1, d);
      if (bdayThisYear >= periodStart && bdayThisYear <= periodEnd) {
        const staff = staffMap.get(sp.id);
        if (staff) periodBirthdays.push({ ...staff, birthday: bdayThisYear });
      }
    }

    if (periodBirthdays.length > 0) {
      stats.birthdays_count = periodBirthdays.length;
      const names = periodBirthdays.slice(0, getMax("birthdays"))
        .map((s: any) => `<tr><td style="padding:5px 0;"><span style="font-weight:600;color:#0b1a2c;">${s.full_name}</span> <span style="color:#64748b;font-size:11px;">${s.role || ""} &middot; ${formatDateShort(s.birthday)}</span></td></tr>`)
        .join("");
      const narrative = periodBirthdays.length === 1
        ? `We celebrated 1 birthday this period. Cake was had (hopefully).`
        : `We celebrated ${periodBirthdays.length} birthdays this period! That's a lot of cake.`;
      htmlSections.push(
        card("&#127874;", "Birthday celebrations", narrative, `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${names}</table>`)
      );
      plainSections.push(
        `BIRTHDAYS\n${periodBirthdays.map((s: any) => `- ${s.full_name}`).join("\n")}`
      );
    }
  }

  // --- ANNIVERSARIES THIS PERIOD ---
  if (enabledKeys.has("anniversaries")) {
    const { data: allStaff } = await db
      .from("staff_members")
      .select("id, full_name, role, joined_date")
      .eq("is_active", true)
      .eq("directory_visible", true)
      .not("joined_date", "is", null);

    const periodAnnis: any[] = [];
    for (const s of allStaff ?? []) {
      if (!s.joined_date) continue;
      const jd = new Date(s.joined_date);
      const m = jd.getMonth() + 1;
      const d = jd.getDate();
      const anniThisYear = new Date(periodStart.getFullYear(), m - 1, d);
      if (anniThisYear >= periodStart && anniThisYear <= periodEnd) {
        const years = periodStart.getFullYear() - jd.getFullYear();
        if (years > 0) {
          periodAnnis.push({ ...s, years, anniversary_date: anniThisYear });
        }
      }
    }

    if (periodAnnis.length > 0) {
      stats.anniversaries_count = periodAnnis.length;
      const sorted = periodAnnis.sort((a, b) => b.years - a.years);
      const names = sorted.slice(0, getMax("anniversaries"))
        .map((s: any) => `<tr><td style="padding:5px 0;"><span style="font-weight:600;color:#0b1a2c;">${s.full_name}</span> <span style="color:#3087b9;font-weight:700;font-size:11px;">${s.years} yr${s.years > 1 ? "s" : ""}</span> <span style="color:#94a3b8;font-size:11px;">&middot; ${s.role || ""}</span></td></tr>`)
        .join("");
      const totalYears = sorted.reduce((sum: number, s: any) => sum + s.years, 0);
      const narrative = `${periodAnnis.length} Sytizen${periodAnnis.length > 1 ? "s" : ""} hit a Sycamore milestone &mdash; that's ${totalYears} combined years of building together.`;
      htmlSections.push(
        card("&#127942;", "Milestones reached", narrative, `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${names}</table>`)
      );
      plainSections.push(
        `WORK ANNIVERSARIES\n${sorted.map((s: any) => `- ${s.full_name} (${s.years} years)`).join("\n")}`
      );
    }
  }

  // --- UPCOMING BIRTHDAYS & ANNIVERSARIES ---
  let celebrationData: { birthdays: any[]; anniversaries: any[] } | null = null;
  if (enabledKeys.has("upcoming_birthdays") || enabledKeys.has("upcoming_anniversaries")) {
    const { data } = await db.rpc("get_upcoming_celebrations");
    celebrationData = data as { birthdays: any[]; anniversaries: any[] } | null;
  }

  const upcomingItems: string[] = [];
  const upcomingPlain: string[] = [];

  if (enabledKeys.has("upcoming_birthdays") && celebrationData) {
    const upcoming = (celebrationData.birthdays ?? [])
      .filter((c: any) => c.days_until > 0 && c.days_until <= 7)
      .slice(0, getMax("upcoming_birthdays"));
    for (const c of upcoming) {
      upcomingItems.push(`<tr><td style="padding:4px 0;"><span style="font-size:14px;">&#127874;</span> <span style="font-weight:600;color:#0b1a2c;font-size:12px;">${c.full_name}</span> <span style="color:#64748b;font-size:11px;">birthday in ${c.days_until}d</span></td></tr>`);
      upcomingPlain.push(`- ${c.full_name} (birthday in ${c.days_until} days)`);
    }
  }

  if (enabledKeys.has("upcoming_anniversaries") && celebrationData) {
    const upcoming = (celebrationData.anniversaries ?? [])
      .filter((c: any) => c.days_until > 0 && c.days_until <= 7)
      .slice(0, getMax("upcoming_anniversaries"));
    for (const c of upcoming) {
      upcomingItems.push(`<tr><td style="padding:4px 0;"><span style="font-size:14px;">&#127942;</span> <span style="font-weight:600;color:#0b1a2c;font-size:12px;">${c.full_name}</span> <span style="color:#64748b;font-size:11px;">${c.years}yr anniversary in ${c.days_until}d</span></td></tr>`);
      upcomingPlain.push(`- ${c.full_name} (${c.years}yr anniversary in ${c.days_until} days)`);
    }
  }

  if (upcomingItems.length > 0) {
    htmlSections.push(
      card("&#128064;", "Coming up next week", "Mark your calendars &mdash; these celebrations are around the corner.", `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${upcomingItems.join("")}</table>`)
    );
    plainSections.push(`COMING UP NEXT WEEK\n${upcomingPlain.join("\n")}`);
  }

  // --- LEADERBOARD ---
  if (enabledKeys.has("leaderboard")) {
    const { data: points } = await db
      .from("points_events")
      .select("user_id, points")
      .gte("created_at", sinceIso)
      .lte("created_at", untilIso);

    if (points && points.length > 0) {
      const totals = new Map<string, number>();
      for (const p of points) {
        totals.set(p.user_id, (totals.get(p.user_id) || 0) + p.points);
      }
      const sorted = [...totals.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, getMax("leaderboard"));

      const userIds = sorted.map((s) => s[0]);
      const { data: staffData } = await db
        .from("staff_members")
        .select("auth_user_id, full_name")
        .in("auth_user_id", userIds);

      const nameMap = new Map<string, string>();
      for (const s of staffData ?? []) nameMap.set(s.auth_user_id, s.full_name);

      const medals = ["&#129351;", "&#129352;", "&#129353;"];
      const rows = sorted
        .map(([uid, pts], i) => {
          const medal = i < 3 ? medals[i] : `<span style="color:#94a3b8;font-size:11px;">${i + 1}.</span>`;
          const name = nameMap.get(uid) || "a Sytizen";
          const barWidth = Math.max(20, Math.round((pts / sorted[0][1]) * 100));
          return `<tr><td style="padding:6px 0;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="width:24px;vertical-align:middle;font-size:16px;">${medal}</td><td style="vertical-align:middle;"><div style="font-weight:600;color:#0b1a2c;font-size:12px;">${name}</div><div style="margin-top:3px;background:#eaf4fb;border-radius:99px;height:6px;width:100%;"><div style="background:linear-gradient(90deg,#3087b9,#74b9e3);height:6px;border-radius:99px;width:${barWidth}%;"></div></div></td><td style="width:50px;text-align:right;vertical-align:middle;font-weight:700;color:#3087b9;font-size:12px;">${pts} pts</td></tr></table></td></tr>`;
        })
        .join("");
      htmlSections.push(
        card("&#9889;", "Who's leading the pack", "The most active Hub contributors this period. Points earned through posts, reactions, kudos, and more.", `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${rows}</table>`)
      );
      plainSections.push(
        `LEADERBOARD\n${sorted.map(([uid, pts], i) => `${i + 1}. ${nameMap.get(uid) || "?"} - ${pts} pts`).join("\n")}`
      );
    }
  }

  // --- NEW JOINERS ---
  if (enabledKeys.has("new_joiners")) {
    const { data: joiners } = await db
      .from("staff_members")
      .select("full_name, role, joined_date")
      .eq("is_active", true)
      .gte("joined_date", periodStart.toISOString().slice(0, 10))
      .lte("joined_date", periodEnd.toISOString().slice(0, 10))
      .order("joined_date", { ascending: false })
      .limit(getMax("new_joiners"));

    if (joiners && joiners.length > 0) {
      stats.new_joiners_count = joiners.length;
      const names = joiners
        .map(
          (j: any) =>
            `<tr><td style="padding:5px 0;"><span style="font-weight:600;color:#0b1a2c;">${j.full_name}</span> <span style="color:#64748b;font-size:11px;">${j.role || "New Sytizen"}</span></td></tr>`
        )
        .join("");
      const narrative = joiners.length === 1
        ? "A new face joined the Sycamore family this period. Say hi when you see them!"
        : `${joiners.length} new faces joined the Sycamore family. Make them feel at home!`;
      htmlSections.push(
        card("&#128075;", "New to the team", narrative, `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${names}</table>`)
      );
      plainSections.push(
        `NEW JOINERS\n${joiners.map((j: any) => `- ${j.full_name} (${j.role || "New"})`).join("\n")}`
      );
    }
  }

  // --- KUDOS & RECOGNITION ---
  if (enabledKeys.has("kudos")) {
    const { data: kudos } = await db
      .from("kudos")
      .select("from_user_id, to_user_id, message, value_code, created_at")
      .gte("created_at", sinceIso)
      .lte("created_at", untilIso)
      .eq("is_public", true)
      .order("created_at", { ascending: false })
      .limit(getMax("kudos"));

    if (kudos && kudos.length > 0) {
      stats.kudos_count = kudos.length;
      const allUserIds = [
        ...new Set(kudos.flatMap((k: any) => [k.from_user_id, k.to_user_id])),
      ];
      const { data: staffData } = await db
        .from("staff_members")
        .select("auth_user_id, full_name")
        .in("auth_user_id", allUserIds);
      const nameMap = new Map<string, string>();
      for (const s of staffData ?? []) nameMap.set(s.auth_user_id, s.full_name);

      const items = kudos
        .map((k: any) => {
          const from = nameMap.get(k.from_user_id) || "Someone";
          const to = nameMap.get(k.to_user_id) || "a fellow Sytizen";
          const msg = k.message ? `<div style="color:#64748b;font-size:11px;font-style:italic;margin-top:2px;">"${(k.message as string).slice(0, 80)}${k.message.length > 80 ? "..." : ""}"</div>` : "";
          return `<tr><td style="padding:8px 0;border-bottom:1px solid #f1f5f9;"><div style="font-size:12px;color:#334155;"><span style="font-weight:600;">${from}</span> &#8594; <span style="font-weight:600;">${to}</span></div>${msg}</td></tr>`;
        })
        .join("");
      htmlSections.push(
        card("&#128155;", "People lifting people up", `${kudos.length} shoutout${kudos.length > 1 ? "s were" : " was"} given this period. Recognition matters.`, `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${items}</table>`)
      );
      plainSections.push(
        `KUDOS\n${kudos.map((k: any) => `- ${nameMap.get(k.from_user_id) || "?"} -> ${nameMap.get(k.to_user_id) || "?"}`).join("\n")}`
      );
    }
  }

  // --- BADGES EARNED ---
  if (enabledKeys.has("badges")) {
    const { data: newBadges } = await db
      .from("user_badges")
      .select("user_id, badge_id, awarded_at")
      .gte("awarded_at", sinceIso)
      .lte("awarded_at", untilIso)
      .order("awarded_at", { ascending: false })
      .limit(getMax("badges") * 2);

    if (newBadges && newBadges.length > 0) {
      stats.badges_count = newBadges.length;
      const badgeIds = [...new Set(newBadges.map((b: any) => b.badge_id))];
      const userIds = [...new Set(newBadges.map((b: any) => b.user_id))];

      const [badgeData, staffData] = await Promise.all([
        db.from("badges").select("id, name, emoji").in("id", badgeIds),
        db.from("staff_members").select("auth_user_id, full_name").in("auth_user_id", userIds),
      ]);

      const badgeMap = new Map<string, any>();
      for (const b of badgeData.data ?? []) badgeMap.set(b.id, b);
      const nameMap = new Map<string, string>();
      for (const s of staffData.data ?? []) nameMap.set(s.auth_user_id, s.full_name);

      const items = newBadges
        .slice(0, getMax("badges"))
        .map((ub: any) => {
          const badge = badgeMap.get(ub.badge_id);
          const name = nameMap.get(ub.user_id) || "a Sytizen";
          return `<tr><td style="padding:5px 0;"><span style="font-size:16px;">${badge?.emoji || "&#127941;"}</span> <span style="font-weight:600;color:#0b1a2c;font-size:12px;">${name}</span> <span style="color:#64748b;font-size:11px;">unlocked</span> <span style="font-weight:600;color:#3087b9;font-size:12px;">${badge?.name || "a badge"}</span></td></tr>`;
        })
        .join("");
      htmlSections.push(
        card("&#127775;", "Achievement unlocked", `${newBadges.length} badge${newBadges.length > 1 ? "s were" : " was"} earned this period. Who's next?`, `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${items}</table>`)
      );
      plainSections.push(
        `BADGES EARNED\n${newBadges.slice(0, getMax("badges")).map((ub: any) => `- ${nameMap.get(ub.user_id) || "?"}: ${badgeMap.get(ub.badge_id)?.name || "badge"}`).join("\n")}`
      );
    }
  }

  // --- UPCOMING EVENTS ---
  if (enabledKeys.has("events")) {
    const { data: events } = await db
      .from("holidays_events")
      .select("title, event_date, event_type")
      .gte("event_date", todayStr)
      .lte("event_date", nextWeekStr)
      .eq("is_active", true)
      .order("event_date")
      .limit(getMax("events"));

    if (events && events.length > 0) {
      stats.events_count = events.length;
      const items = events
        .map(
          (e: any) =>
            `<tr><td style="padding:6px 0;border-bottom:1px solid #f1f5f9;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="width:40px;vertical-align:middle;"><div style="background:#eaf4fb;width:32px;height:32px;border-radius:8px;text-align:center;line-height:32px;font-size:14px;">&#128197;</div></td><td style="vertical-align:middle;"><div style="font-weight:600;color:#0b1a2c;font-size:12px;">${e.title}</div><div style="color:#64748b;font-size:11px;">${formatDateShort(e.event_date)}</div></td></tr></table></td></tr>`
        )
        .join("");
      htmlSections.push(
        card("&#128198;", "On the calendar", "Heads up &mdash; these events are coming this week.", `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${items}</table>`)
      );
      plainSections.push(
        `UPCOMING EVENTS\n${events.map((e: any) => `- ${e.title} (${formatDateShort(e.event_date)})`).join("\n")}`
      );
    }
  }

  // --- PLAYLIST ---
  if (enabledKeys.has("playlist")) {
    const { data: playlist } = await db
      .from("playlist_weeks")
      .select("id, theme, week_start")
      .eq("is_staff_playlist", false)
      .order("week_start", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (playlist) {
      const { data: topSongs } = await db
        .from("playlist_songs")
        .select("title, artist, votes")
        .eq("playlist_id", playlist.id)
        .order("votes", { ascending: false })
        .limit(getMax("playlist"));

      if (topSongs && topSongs.length > 0) {
        const items = topSongs
          .map(
            (s: any, i: number) =>
              `<tr><td style="padding:6px 0;${i < topSongs.length - 1 ? "border-bottom:1px solid #f1f5f9;" : ""}"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="width:28px;vertical-align:middle;font-size:14px;">&#127925;</td><td style="vertical-align:middle;"><div style="font-weight:600;color:#0b1a2c;font-size:12px;">${s.title}</div><div style="color:#64748b;font-size:11px;">${s.artist}</div></td><td style="width:44px;text-align:right;vertical-align:middle;color:#3087b9;font-size:11px;font-weight:600;">${s.votes} votes</td></tr></table></td></tr>`
          )
          .join("");
        const themeLabel = playlist.theme ? `This week's vibe: "${playlist.theme}"` : "Here's what the team's been listening to.";
        htmlSections.push(
          card("&#127911;", "Now playing", themeLabel, `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${items}</table>`)
        );
        plainSections.push(
          `PLAYLIST\n${topSongs.map((s: any) => `- ${s.title} by ${s.artist}`).join("\n")}`
        );
      }
    }
  }

  // --- DEPARTURES ---
  if (enabledKeys.has("exits")) {
    const { data: exits } = await db
      .from("staff_members")
      .select("full_name, role")
      .eq("is_active", false)
      .eq("directory_visible", false)
      .gte("updated_at", sinceIso)
      .lte("updated_at", untilIso)
      .limit(getMax("exits"));

    if (exits && exits.length > 0) {
      const names = exits
        .map(
          (e: any) =>
            `<tr><td style="padding:5px 0;"><span style="font-weight:600;color:#0b1a2c;">${e.full_name}</span> <span style="color:#64748b;font-size:11px;">${e.role || ""}</span></td></tr>`
        )
        .join("");
      htmlSections.push(
        card("&#128075;", "Moving on", "We wish them well on their next chapter.", `<table role="presentation" width="100%" cellpadding="0" cellspacing="0">${names}</table>`)
      );
      plainSections.push(
        `DEPARTURES\n${exits.map((e: any) => `- ${e.full_name}`).join("\n")}`
      );
    }
  }

  return {
    html: htmlSections.join(""),
    plain: plainSections.join("\n\n"),
    stats,
    isEmpty: htmlSections.length === 0,
  };
}

function card(emoji: string, title: string, narrative: string, content: string) {
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:20px;">
  <tr><td style="background:#ffffff;border:1px solid #e2e8f0;border-radius:14px;overflow:hidden;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
      <tr><td style="padding:18px 20px 12px;">
        <div style="font-size:20px;display:inline-block;margin-right:8px;vertical-align:middle;">${emoji}</div>
        <span style="font-weight:800;color:#0b1a2c;font-size:15px;vertical-align:middle;">${title}</span>
        <div style="color:#64748b;font-size:12px;line-height:1.5;margin-top:6px;">${narrative}</div>
      </td></tr>
      <tr><td style="padding:4px 20px 18px;">
        ${content}
      </td></tr>
    </table>
  </td></tr>
</table>`;
}

async function getEmailSettings(db: ReturnType<typeof createClient>) {
  const { data } = await db
    .from("email_settings")
    .select("*")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  return data;
}

async function getTemplate(
  db: ReturnType<typeof createClient>,
  slug: string
) {
  const { data } = await db
    .from("email_templates")
    .select("*")
    .eq("slug", slug)
    .maybeSingle();
  return data;
}

async function ensurePrefs(
  db: ReturnType<typeof createClient>,
  userId: string
) {
  const { data } = await db
    .from("notification_preferences")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();
  if (data) return data;
  const { data: created } = await db
    .from("notification_preferences")
    .insert({ user_id: userId })
    .select("*")
    .maybeSingle();
  return created;
}

async function sendDigest(
  db: ReturnType<typeof createClient>,
  digestType: "weekly" | "monthly"
) {
  const { data: config } = await db
    .from("digest_config")
    .select("*")
    .eq("frequency", digestType)
    .maybeSingle();

  if (!config || !config.is_active) {
    return { queued: 0, reason: "Digest is not active" };
  }

  const settings = await getEmailSettings(db);
  if (!settings || (settings as any).default_enabled === false) {
    return { queued: 0, reason: "Email sending is disabled" };
  }

  const sections: SectionConfig[] = config.sections || [];

  // Calculate period
  const periodEnd = new Date();
  periodEnd.setHours(23, 59, 59, 999);
  const periodStart = new Date();
  if (digestType === "weekly") {
    periodStart.setDate(periodStart.getDate() - 7);
  } else {
    periodStart.setMonth(periodStart.getMonth() - 1);
  }
  periodStart.setHours(0, 0, 0, 0);

  const digest = await compileDigest(db, periodStart, periodEnd, sections);

  if (digest.isEmpty) {
    return { queued: 0, reason: "No content to include in digest" };
  }

  // Build the full email body with intro
  const periodLabel = `${formatDate(periodStart)} - ${formatDate(periodEnd)}`;
  const introText =
    config.custom_intro ||
    (digestType === "weekly"
      ? "Here's what went down on the Hub this week. The highlights, the milestones, and the moments worth celebrating."
      : "A whole month at Sycamore, distilled into one read. Here's everything that mattered on the Hub.");

  const digestBody = `<div style="background:#f8fafc;border-radius:12px;padding:20px;">
    <div style="color:#475569;font-size:13px;line-height:1.6;margin-bottom:16px;">${introText}</div>
    <div style="display:inline-block;background:#eaf4fb;color:#3087b9;font-size:10px;font-weight:700;letter-spacing:0.1em;text-transform:uppercase;padding:4px 10px;border-radius:99px;margin-bottom:20px;">${periodLabel}</div>
    ${digest.html}
  </div>`;

  const template = await getTemplate(db, "weekly_digest");
  if (!template || template.is_active === false) {
    return { queued: 0, reason: "weekly_digest email template is inactive" };
  }

  const { data: staff } = await db
    .from("staff_members")
    .select("id,full_name,email,auth_user_id")
    .eq("is_active", true)
    .not("email", "is", null);

  if (!staff || staff.length === 0) {
    return { queued: 0, reason: "No active staff with email" };
  }

  const appUrl =
    (settings as any).app_base_url ||
    Deno.env.get("APP_BASE_URL") ||
    "";

  let queued = 0;
  const rows: any[] = [];

  for (const s of staff) {
    if (!s.email) continue;
    let unsubToken = "";
    if (s.auth_user_id) {
      const prefs = await ensurePrefs(db, s.auth_user_id);
      if (prefs && (prefs as any).email_weekly_digest === false) continue;
      unsubToken = (prefs as any)?.unsubscribe_token ?? "";
    }

    const unsubUrl =
      appUrl && unsubToken
        ? `${appUrl.replace(/\/$/, "")}/unsubscribe?token=${unsubToken}`
        : "";

    const vars: Record<string, string> = {
      first_name: firstName(s.full_name),
      digest_body: digestBody,
      digest_body_plain: digest.plain,
      brand_color: (settings as any).brand_color || "#0f6e42",
      unsubscribe_url: unsubUrl,
      footer_html: render((settings as any).footer_html || "", {
        unsubscribe_url: unsubUrl,
      }),
    };

    const subject = render(template.subject, vars);
    const html = render(template.html_body, vars);
    const text = render(template.text_body || "", vars);

    rows.push({
      to_email: s.email,
      to_name: s.full_name ?? "",
      subject,
      html_body: html,
      text_body: text,
      template_slug: template.slug,
      trigger: `${digestType}_digest`,
      payload: vars,
      reference_id: {
        digest_type: digestType,
        period: periodLabel,
      },
      user_id: s.auth_user_id ?? null,
      status: "pending",
    });
  }

  if (rows.length > 0) {
    // Insert in batches of 50
    for (let i = 0; i < rows.length; i += 50) {
      await db.from("email_queue").insert(rows.slice(i, i + 50));
    }
    queued = rows.length;
  }

  // Record in digest history
  await db.from("digest_history").insert({
    digest_type: digestType,
    period_start: periodStart.toISOString().slice(0, 10),
    period_end: periodEnd.toISOString().slice(0, 10),
    stats: digest.stats,
    recipients_count: queued,
  });

  // Update last_sent_at
  await db
    .from("digest_config")
    .update({ last_sent_at: new Date().toISOString(), updated_at: new Date().toISOString() })
    .eq("id", config.id);

  return { queued, stats: digest.stats };
}

async function previewDigest(
  db: ReturnType<typeof createClient>,
  digestType: "weekly" | "monthly"
) {
  const { data: config } = await db
    .from("digest_config")
    .select("*")
    .eq("frequency", digestType)
    .maybeSingle();

  const sections: SectionConfig[] = config?.sections || [];

  const periodEnd = new Date();
  periodEnd.setHours(23, 59, 59, 999);
  const periodStart = new Date();
  if (digestType === "weekly") {
    periodStart.setDate(periodStart.getDate() - 7);
  } else {
    periodStart.setMonth(periodStart.getMonth() - 1);
  }
  periodStart.setHours(0, 0, 0, 0);

  const digest = await compileDigest(db, periodStart, periodEnd, sections);
  const periodLabel = `${formatDate(periodStart)} - ${formatDate(periodEnd)}`;
  const introText =
    config?.custom_intro ||
    (digestType === "weekly"
      ? "Here's what went down on the Hub this week. The highlights, the milestones, and the moments worth celebrating."
      : "A whole month at Sycamore, distilled into one read. Here's everything that mattered on the Hub.");

  const styledHtml = `<div style="font-family:'Satoshi','Inter',system-ui,sans-serif;background:#f8fafc;border-radius:12px;padding:20px;">
    <div style="color:#475569;font-size:13px;line-height:1.6;margin-bottom:16px;">${introText}</div>
    <div style="display:inline-block;background:#eaf4fb;color:#3087b9;font-size:10px;font-weight:700;letter-spacing:0.1em;text-transform:uppercase;padding:4px 10px;border-radius:99px;margin-bottom:20px;">${periodLabel}</div>
    ${digest.html}
  </div>`;

  return {
    period: periodLabel,
    intro: introText,
    html: styledHtml,
    plain: digest.plain,
    stats: digest.stats,
    isEmpty: digest.isEmpty,
  };
}

function isServiceRoleBearer(authHeader: string) {
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return token.length > 0 && svc.length > 0 && token === svc;
}

async function requireAdmin(authHeader: string) {
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } }
  );
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return false;
  const email = (userData.user.email ?? "").toLowerCase();
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );
  const { data } = await admin
    .from("admin_users")
    .select("email")
    .eq("email", email)
    .maybeSingle();
  return !!data;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const url = new URL(req.url);
    const action = url.pathname.split("/").pop() ?? "";

    const db = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const isService = isServiceRoleBearer(authHeader);

    // Cron/service-triggered send
    if (action === "send" || action === "hub-digest") {
      if (!isService) {
        const isAdmin = await requireAdmin(authHeader);
        if (!isAdmin) return json({ error: "Admin access required" }, 403);
      }
      const body = await req.json().catch(() => ({}));
      const digestType =
        body.type === "monthly" ? "monthly" : "weekly";
      const result = await sendDigest(db, digestType);

      // Trigger queue processing
      const emailUrl = `${Deno.env.get("SUPABASE_URL")}/functions/v1/email/run_queue`;
      fetch(emailUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({}),
      }).catch(() => {});

      return json(result);
    }

    // Preview endpoint (admin only)
    if (action === "preview") {
      const isAdmin = await requireAdmin(authHeader);
      if (!isAdmin) return json({ error: "Admin access required" }, 403);
      const body = await req.json().catch(() => ({}));
      const digestType =
        body.type === "monthly" ? "monthly" : "weekly";
      const result = await previewDigest(db, digestType);
      return json(result);
    }

    return json({ error: "Unknown action. Use /send or /preview" }, 404);
  } catch (e) {
    return json({ error: (e as Error).message ?? "Unexpected error" }, 500);
  }
});
