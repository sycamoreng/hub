import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers":
    "Content-Type, Authorization, X-Client-Info, Apikey",
};

interface SongMetadata {
  title: string;
  artist: string;
  album?: string;
  thumbnail_url?: string;
  platform: "spotify" | "apple" | "youtube" | "unknown";
  url: string;
}

function errorResponse(message: string, status = 400) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function extractSpotify(url: string): Promise<SongMetadata | null> {
  try {
    // Spotify oEmbed only gives the track title, not the artist.
    // Fetch the page HTML to get og:description which has "Song · Artist" format.
    const pageRes = await fetch(url, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; bot)" },
      redirect: "follow",
    });

    let title = "";
    let artist = "";
    let thumbnail_url: string | undefined;

    if (pageRes.ok) {
      const html = await pageRes.text();
      // og:title is typically just the song name
      const ogTitle = html.match(/<meta\s+property="og:title"\s+content="([^"]+)"/i);
      // og:description format: "Song · Artist · Album" or "Artist · Song · Album"
      const ogDesc = html.match(/<meta\s+property="og:description"\s+content="([^"]+)"/i);
      const ogImage = html.match(/<meta\s+property="og:image"\s+content="([^"]+)"/i);

      title = ogTitle?.[1] || "";
      thumbnail_url = ogImage?.[1] || undefined;

      // The description often has format like: "Artist Name · Album · Song" or contains the artist
      const descText = ogDesc?.[1] || "";
      // Spotify meta description patterns:
      // "Song · Artist · Album · 2024" or "Listen to Song on Spotify. Artist · Album · 2024"
      if (descText) {
        // Try "Listen to X on Spotify. Artist · ..." pattern
        const listenMatch = descText.match(/Listen to .+? on Spotify\.\s*(.+)/i);
        const content = listenMatch ? listenMatch[1] : descText;
        // Split by middle-dot separator
        const parts = content.split(/\s*[\u00B7\u2027]\s*/);
        if (parts.length >= 1) {
          // First segment after "Listen to...on Spotify." is typically the artist
          artist = parts[0].trim();
        }
      }

      // Fallback: try twitter:audio:artist_name meta
      if (!artist) {
        const artistMeta = html.match(/<meta\s+(?:name|property)="(?:music:musician|twitter:audio:artist_name)"\s+content="([^"]+)"/i);
        if (artistMeta) artist = artistMeta[1];
      }
    }

    // Fallback to oEmbed if page fetch didn't yield artist
    if (!artist || !title) {
      const oembedUrl = `https://open.spotify.com/oembed?url=${encodeURIComponent(url)}`;
      const oRes = await fetch(oembedUrl);
      if (oRes.ok) {
        const data = await oRes.json();
        if (!title) title = data.title || "";
        if (!thumbnail_url) thumbnail_url = data.thumbnail_url || undefined;
        // Parse the iframe HTML for artist if still missing
        if (!artist && data.html) {
          // The embed title attribute often has "Song - Artist"
          const iframeTitleMatch = (data.html as string).match(/title="([^"]+)"/);
          if (iframeTitleMatch) {
            const iframeTitle = iframeTitleMatch[1];
            // Format is often "Spotify - Song" or "Song by Artist" etc.
            if (iframeTitle.includes(" by ")) {
              artist = iframeTitle.split(" by ").slice(1).join(" by ").trim();
            }
          }
        }
      }
    }

    if (!title && !artist) return null;

    return {
      title: title || "Unknown Title",
      artist: artist || "Unknown Artist",
      thumbnail_url,
      platform: "spotify",
      url,
    };
  } catch {
    return null;
  }
}

async function extractYouTube(url: string): Promise<SongMetadata | null> {
  try {
    const oembedUrl = `https://www.youtube.com/oembed?url=${encodeURIComponent(url)}&format=json`;
    const res = await fetch(oembedUrl);
    if (!res.ok) return null;
    const data = await res.json();
    const fullTitle: string = data.title || "";
    // YouTube titles are often "Artist - Song" or "Song | Artist"
    let title = fullTitle;
    let artist = data.author_name || "";
    if (fullTitle.includes(" - ")) {
      const parts = fullTitle.split(" - ");
      artist = parts[0].trim();
      title = parts.slice(1).join(" - ").trim();
    } else if (fullTitle.includes(" | ")) {
      const parts = fullTitle.split(" | ");
      title = parts[0].trim();
      artist = parts.slice(1).join(" | ").trim();
    }
    // Remove common suffixes like (Official Video), [Official Audio], etc.
    title = title
      .replace(/\s*[\(\[](official\s*(music\s*)?video|official\s*audio|lyrics?\s*video|audio|visualizer|hd|4k)[\)\]]/gi, "")
      .trim();

    // Extract thumbnail from video ID
    let thumbnail_url: string | undefined;
    const videoIdMatch = url.match(
      /(?:v=|\/)([\w-]{11})(?:\?|&|$|\/)/
    );
    if (videoIdMatch) {
      thumbnail_url = `https://img.youtube.com/vi/${videoIdMatch[1]}/mqdefault.jpg`;
    }

    return {
      title: title || "Unknown Title",
      artist: artist || "Unknown Artist",
      thumbnail_url,
      platform: "youtube",
      url,
    };
  } catch {
    return null;
  }
}

async function extractAppleMusic(url: string): Promise<SongMetadata | null> {
  try {
    const oembedUrl = `https://music.apple.com/api/v1/oembed?url=${encodeURIComponent(url)}&format=json`;
    const res = await fetch(oembedUrl);
    if (!res.ok) {
      // Fallback: try fetching the page and parsing meta tags
      const pageRes = await fetch(url, {
        headers: { "User-Agent": "Mozilla/5.0 (compatible; bot)" },
        redirect: "follow",
      });
      if (!pageRes.ok) return null;
      const html = await pageRes.text();
      const titleMatch = html.match(
        /<meta\s+property="og:title"\s+content="([^"]+)"/i
      );
      const descMatch = html.match(
        /<meta\s+property="og:description"\s+content="([^"]+)"/i
      );
      const imgMatch = html.match(
        /<meta\s+property="og:image"\s+content="([^"]+)"/i
      );
      const ogTitle = titleMatch?.[1] || "";
      // Apple Music og:title is typically "Song Title - song and target text by Artist on Apple Music"
      let title = ogTitle;
      let artist = "";
      // Try parsing "Song by Artist" pattern from description
      const byMatch = (descMatch?.[1] || "").match(/^(.+?)\s+by\s+(.+?)(?:\s+on\s+Apple\s+Music)?$/i);
      if (byMatch) {
        title = byMatch[1].trim();
        artist = byMatch[2].trim();
      } else if (ogTitle.includes(" by ")) {
        const parts = ogTitle.split(" by ");
        title = parts[0].trim();
        artist = parts.slice(1).join(" by ").trim();
      }
      return {
        title: title || "Unknown Title",
        artist: artist || "Unknown Artist",
        thumbnail_url: imgMatch?.[1] || undefined,
        platform: "apple",
        url,
      };
    }
    const data = await res.json();
    return {
      title: data.title || "Unknown Title",
      artist: data.author_name || "Unknown Artist",
      thumbnail_url: data.thumbnail_url || undefined,
      platform: "apple",
      url,
    };
  } catch {
    return null;
  }
}

function detectPlatform(
  url: string
): "spotify" | "apple" | "youtube" | "unknown" {
  const lower = url.toLowerCase();
  if (lower.includes("spotify.com") || lower.includes("spotify.link"))
    return "spotify";
  if (lower.includes("music.apple.com")) return "apple";
  if (
    lower.includes("youtube.com") ||
    lower.includes("youtu.be") ||
    lower.includes("music.youtube.com")
  )
    return "youtube";
  return "unknown";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return errorResponse("Method not allowed", 405);
    }

    const body = await req.json();
    const url: string = (body.url || "").trim();

    if (!url) {
      return errorResponse("url is required");
    }

    // Basic URL validation
    try {
      new URL(url);
    } catch {
      return errorResponse("Invalid URL format");
    }

    const platform = detectPlatform(url);
    let result: SongMetadata | null = null;

    switch (platform) {
      case "spotify":
        result = await extractSpotify(url);
        break;
      case "youtube":
        result = await extractYouTube(url);
        break;
      case "apple":
        result = await extractAppleMusic(url);
        break;
      default:
        return errorResponse(
          "Unsupported platform. Please use Spotify, YouTube, or Apple Music links."
        );
    }

    if (!result) {
      return errorResponse(
        "Could not extract song details from this link. Please check the URL and try again."
      );
    }

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return errorResponse("Internal error: " + (e as Error).message, 500);
  }
});
