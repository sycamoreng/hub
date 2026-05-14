/*
  # Add Marketing & Communications tools

  ## Summary
  - For tools shared with the Technology team that Marketing also uses,
    append `Marketing & Communications` to `allowed_departments`.
  - Insert new Marketing-only tools (creative suite, social, analytics
    extras) restricted to `Marketing & Communications`.
  - Duplicates from the user's input list are merged into a single row.

  ## Safety
  - Uses `array_append` with `NOT contains` guard to avoid duplicate
    department entries.
  - New rows inserted only if a tool with the same name does not already
    exist (case-insensitive).
*/

-- 1) Append Marketing & Communications to tools that already exist and that
--    Marketing also uses.
UPDATE public.quick_tools
SET allowed_departments = (
      SELECT ARRAY(SELECT DISTINCT unnest(allowed_departments || ARRAY['Marketing & Communications']::text[]))
    ),
    updated_at = now()
WHERE lower(name) IN (
  'figma','envato','freepik','wordpress','mixpanel','appsflyer','netcore',
  'chatgpt','gemini','coda','google analytics','microsoft clarity',
  'firebase','metabase','zoom','sprout','bulk sms africa'
);

-- 2) Insert new Marketing-only tools (deduped, no clearbit logos).
WITH seed(name, url, sort_order) AS (
  VALUES
    ('Adobe Photoshop','https://www.adobe.com/products/photoshop.html',2000),
    ('Adobe Illustrator','https://www.adobe.com/products/illustrator.html',2010),
    ('Adobe Premiere Pro','https://www.adobe.com/products/premiere.html',2020),
    ('Adobe After Effects','https://www.adobe.com/products/aftereffects.html',2030),
    ('Adobe InDesign','https://www.adobe.com/products/indesign.html',2040),
    ('Adobe Lightroom','https://www.adobe.com/products/photoshop-lightroom.html',2050),
    ('Adobe Media Encoder','https://www.adobe.com/products/media-encoder.html',2060),
    ('Adobe Dimension','https://www.adobe.com/products/dimension.html',2070),
    ('Adobe Audition','https://www.adobe.com/products/audition.html',2080),
    ('Adobe Podcast','https://podcast.adobe.com',2090),
    ('Adobe Firefly','https://firefly.adobe.com',2100),
    ('Affinity Designer','https://affinity.serif.com/designer',2110),
    ('CorelDRAW','https://www.coreldraw.com',2120),
    ('Blender','https://www.blender.org',2130),
    ('Spline','https://spline.design',2140),
    ('Cinema 4D','https://www.maxon.net/en/cinema-4d',2150),
    ('DaVinci Resolve','https://www.blackmagicdesign.com/products/davinciresolve',2160),
    ('Blackmagic Suite','https://www.blackmagicdesign.com',2170),
    ('CapCut','https://www.capcut.com',2180),
    ('Descript','https://www.descript.com',2190),
    ('HandBrake','https://handbrake.fr',2200),
    ('Capture One','https://www.captureone.com',2210),
    ('Daz 3D','https://www.daz3d.com',2220),
    ('CLO 3D','https://www.clo3d.com',2230),
    ('Teleprompter','https://teleprompter.com',2240),
    ('Radio Silence','https://radiosilenceapp.com',2250),
    ('Pinterest','https://www.pinterest.com',2260),
    ('Motion Array','https://motionarray.com',2270),
    ('PNGTree','https://pngtree.com',2280),
    ('DistroKid','https://distrokid.com',2290),
    ('Instagram','https://www.instagram.com',2300),
    ('Twitter','https://twitter.com',2310),
    ('LinkedIn','https://www.linkedin.com',2320),
    ('Facebook','https://www.facebook.com',2330),
    ('YouTube','https://www.youtube.com',2340),
    ('TikTok','https://www.tiktok.com',2350),
    ('Answer the Public','https://answerthepublic.com',2360),
    ('Metricool','https://metricool.com',2370)
)
INSERT INTO public.quick_tools (name, url, logo_url, allowed_departments, sort_order, is_active)
SELECT s.name,
       s.url,
       'https://www.google.com/s2/favicons?domain='
         || regexp_replace(regexp_replace(s.url, '^https?://', ''), '/.*$', '')
         || '&sz=128',
       ARRAY['Marketing & Communications']::text[],
       s.sort_order,
       true
FROM seed s
WHERE NOT EXISTS (
  SELECT 1 FROM public.quick_tools q WHERE lower(q.name) = lower(s.name)
);
