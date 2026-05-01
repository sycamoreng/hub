import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.49.4'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client-Info, Apikey'
}

const TOKEN_URL = 'https://oauth2.googleapis.com/token'
const CHAT_API = 'https://chat.googleapis.com/v1'

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

function b64url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input
  const s = btoa(String.fromCharCode(...bytes))
  return s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '')
  const raw = atob(b64)
  const buf = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i)
  return buf.buffer
}

async function getImpersonatedToken(subjectEmail: string, scopes: string[]): Promise<string> {
  const saRaw = Deno.env.get('GOOGLE_SA_JSON') ?? ''
  if (!saRaw) throw new Error('GOOGLE_SA_JSON is not configured')
  const sa = JSON.parse(saRaw)

  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const claim = {
    iss: sa.client_email,
    sub: subjectEmail,
    scope: scopes.join(' '),
    aud: TOKEN_URL,
    exp: now + 3600,
    iat: now
  }

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claim))}`
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signingInput))
  const jwt = `${signingInput}.${b64url(new Uint8Array(sig))}`

  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt
    })
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Token exchange failed (${subjectEmail}): ${res.status} ${text}`)
  }
  const json = await res.json()
  return json.access_token as string
}

async function findDirectMessage(viewerEmail: string, targetGoogleUserId: string): Promise<string | null> {
  const token = await getImpersonatedToken(viewerEmail, [
    'https://www.googleapis.com/auth/chat.spaces.readonly'
  ])
  const url = `${CHAT_API}/spaces:findDirectMessage?name=${encodeURIComponent(`users/${targetGoogleUserId}`)}`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } })
  if (res.status === 404) return null
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Chat findDirectMessage failed: ${res.status} ${text}`)
  }
  const json = await res.json()
  const name: string = json?.name ?? ''
  return name.replace(/^spaces\//, '') || null
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
    const viewerEmail = viewer.email.toLowerCase()

    const body = await req.json().catch(() => ({}))
    const targetStaffId: string = body.staff_id ?? ''
    if (!targetStaffId) return jsonResponse({ error: 'staff_id required' }, 400)

    const { data: cached } = await service
      .from('chat_dm_space_cache')
      .select('space_id, resolved_at')
      .eq('viewer_user_id', viewer.id)
      .eq('target_staff_id', targetStaffId)
      .maybeSingle()

    if (cached?.space_id) {
      return jsonResponse({ space_id: cached.space_id, cached: true })
    }

    const { data: target } = await service
      .from('staff_members')
      .select('id, google_user_id, email')
      .eq('id', targetStaffId)
      .maybeSingle()

    if (!target) return jsonResponse({ error: 'staff not found' }, 404)
    if (!target.google_user_id) return jsonResponse({ error: 'target has no google id' }, 422)

    const spaceId = await findDirectMessage(viewerEmail, target.google_user_id as string)
    if (!spaceId) return jsonResponse({ error: 'no dm space found' }, 404)

    await service
      .from('chat_dm_space_cache')
      .upsert(
        { viewer_user_id: viewer.id, target_staff_id: targetStaffId, space_id: spaceId, resolved_at: new Date().toISOString() },
        { onConflict: 'viewer_user_id,target_staff_id' }
      )

    return jsonResponse({ space_id: spaceId, cached: false })
  } catch (e: any) {
    return jsonResponse({ error: e?.message ?? String(e) }, 500)
  }
})
