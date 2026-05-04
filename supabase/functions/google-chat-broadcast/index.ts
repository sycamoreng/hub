import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.49.4'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client-Info, Apikey'
}

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

function stripTags(s: string): string {
  return (s || '').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').trim()
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 200, headers: corsHeaders })

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const anon = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )
    const service = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { data: userData } = await anon.auth.getUser()
    const viewer = userData?.user
    if (!viewer?.email) return jsonResponse({ error: 'not authenticated' }, 401)

    const body = await req.json().catch(() => ({}))
    const announcementId: string = body.announcement_id ?? ''
    if (!announcementId) return jsonResponse({ error: 'announcement_id required' }, 400)

    const { data: ann } = await service
      .from('announcements')
      .select('id, title, summary, content, image_url, post_to_chat_space_ids, chat_sent_at')
      .eq('id', announcementId)
      .maybeSingle()
    if (!ann) return jsonResponse({ error: 'announcement not found' }, 404)

    const spaceIds: string[] = Array.isArray(ann.post_to_chat_space_ids) ? ann.post_to_chat_space_ids : []
    if (spaceIds.length === 0) return jsonResponse({ sent: 0, skipped: 'no_spaces' })

    const { data: spaces } = await service
      .from('google_chat_spaces')
      .select('id, name, webhook_url, is_active')
      .in('id', spaceIds)

    const active = (spaces ?? []).filter((s: any) => s.is_active && s.webhook_url)
    if (active.length === 0) return jsonResponse({ sent: 0, skipped: 'no_active_spaces' })

    const title = ann.title ?? 'Announcement'
    const summary = ann.summary ?? ''
    const bodyText = stripTags(ann.content ?? '')
    const textFallback = `*${title}*${summary ? `\n_${summary}_` : ''}\n\n${bodyText}`.slice(0, 3500)

    const card = {
      text: textFallback,
      cardsV2: [
        {
          cardId: `ann-${ann.id}`,
          card: {
            header: {
              title,
              subtitle: summary || 'Sycamore announcement',
              imageUrl: ann.image_url || undefined,
              imageType: ann.image_url ? 'SQUARE' : undefined
            },
            sections: [
              {
                widgets: [
                  { textParagraph: { text: bodyText.slice(0, 3500) || title } }
                ]
              }
            ]
          }
        }
      ]
    }

    const results: Array<{ space_id: string; ok: boolean; status?: number; error?: string }> = []
    for (const s of active) {
      try {
        const res = await fetch(s.webhook_url, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(card)
        })
        results.push({ space_id: s.id, ok: res.ok, status: res.status })
      } catch (e: any) {
        results.push({ space_id: s.id, ok: false, error: e?.message ?? String(e) })
      }
    }

    const sent = results.filter(r => r.ok).length
    if (sent > 0) {
      await service
        .from('announcements')
        .update({ chat_sent_at: new Date().toISOString() })
        .eq('id', ann.id)
    }

    return jsonResponse({ sent, total: active.length, results })
  } catch (e: any) {
    return jsonResponse({ error: e?.message ?? String(e) }, 500)
  }
})
