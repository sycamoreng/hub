import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'npm:@supabase/supabase-js@2.49.4'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Client-Info, Apikey'
}

const ADMIN_DIRECTORY = 'https://admin.googleapis.com/admin/directory/v1'
const TOKEN_URL = 'https://oauth2.googleapis.com/token'

type GoogleUser = {
  id: string
  primaryEmail: string
  suspended?: boolean
  name?: { fullName?: string; givenName?: string; familyName?: string }
  creationTime?: string
  orgUnitPath?: string
  organizations?: Array<{ department?: string; title?: string; primary?: boolean }>
  phones?: Array<{ value?: string; primary?: boolean }>
  thumbnailPhotoUrl?: string
}

interface SyncContext {
  supabase: ReturnType<typeof createClient>
  accessToken: string
  domain: string
  settings: any
  rules: Map<string, 'include' | 'exclude'>
  deptMap: Map<string, string>
  existingByEmail: Map<string, any>
  existingByGoogleId: Map<string, any>
  staffLocks: Map<string, Set<string>>
  mode: 'dry_run' | 'apply'
  triggeredBy: string
}

function jsonResponse(body: any, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

function b64url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input
  let s = btoa(String.fromCharCode(...bytes))
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

async function getGoogleAccessToken(): Promise<string> {
  const saRaw = Deno.env.get('GOOGLE_SA_JSON') ?? ''
  const subject = Deno.env.get('GOOGLE_SA_SUBJECT') ?? ''
  if (!saRaw) throw new Error('GOOGLE_SA_JSON is not configured')
  if (!subject) throw new Error('GOOGLE_SA_SUBJECT is not configured')
  const sa = JSON.parse(saRaw)

  const scopes = [
    'https://www.googleapis.com/auth/admin.directory.user.readonly',
    'https://www.googleapis.com/auth/admin.directory.orgunit.readonly'
  ].join(' ')

  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const claim = {
    iss: sa.client_email,
    sub: subject,
    scope: scopes,
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
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput)
  )
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
    throw new Error(`Google token exchange failed: ${res.status} ${text}`)
  }
  const json = await res.json()
  return json.access_token as string
}

async function fetchAllUsers(accessToken: string, domain: string): Promise<GoogleUser[]> {
  const users: GoogleUser[] = []
  let pageToken: string | undefined
  do {
    const url = new URL(`${ADMIN_DIRECTORY}/users`)
    url.searchParams.set('domain', domain)
    url.searchParams.set('maxResults', '500')
    url.searchParams.set('projection', 'full')
    if (pageToken) url.searchParams.set('pageToken', pageToken)
    const res = await fetch(url.toString(), {
      headers: { Authorization: `Bearer ${accessToken}` }
    })
    if (!res.ok) {
      const text = await res.text()
      throw new Error(`Admin SDK users.list failed: ${res.status} ${text}`)
    }
    const page = await res.json()
    for (const u of page.users ?? []) users.push(u as GoogleUser)
    pageToken = page.nextPageToken
  } while (pageToken)
  return users
}

function pickDepartmentValue(u: GoogleUser, source: string): string | null {
  if (source === 'orgUnitPath') return (u.orgUnitPath ?? '').trim() || null
  const orgs = u.organizations ?? []
  const primary = orgs.find(o => o.primary) ?? orgs[0]
  return (primary?.department ?? '').trim() || null
}

function decide(email: string, rules: Map<string, 'include' | 'exclude'>, defaultAction: string): 'include' | 'exclude' {
  const rule = rules.get(email.toLowerCase())
  if (rule) return rule
  return defaultAction === 'exclude' ? 'exclude' : 'include'
}

async function downloadAvatar(url: string, accessToken: string): Promise<{ bytes: Uint8Array; contentType: string } | null> {
  try {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } })
    if (!res.ok) return null
    const contentType = res.headers.get('content-type') ?? 'image/jpeg'
    const buf = new Uint8Array(await res.arrayBuffer())
    return { bytes: buf, contentType }
  } catch {
    return null
  }
}

async function uploadAvatar(supabase: any, googleId: string, bytes: Uint8Array, contentType: string): Promise<string | null> {
  const ext = contentType.includes('png') ? 'png' : 'jpg'
  const path = `google/${googleId}.${ext}`
  const { error } = await supabase.storage.from('avatars').upload(path, bytes, {
    contentType,
    upsert: true
  })
  if (error) return null
  const { data } = supabase.storage.from('avatars').getPublicUrl(path)
  return data?.publicUrl ?? null
}

async function loadContext(supabase: any, mode: 'dry_run' | 'apply', triggeredBy: string): Promise<SyncContext> {
  const [{ data: settings }, { data: rules }, { data: deptRows }, { data: staff }, { data: locks }] = await Promise.all([
    supabase.from('google_sync_settings').select('*').eq('id', 'default').maybeSingle(),
    supabase.from('google_sync_rules').select('*'),
    supabase.from('google_department_map').select('*'),
    supabase.from('staff_members').select('*'),
    supabase.from('staff_member_locks').select('*')
  ])

  const domain = Deno.env.get('GOOGLE_WORKSPACE_DOMAIN') ?? settings?.domain ?? ''
  if (!domain) throw new Error('GOOGLE_WORKSPACE_DOMAIN is not configured')

  const ruleMap = new Map<string, 'include' | 'exclude'>()
  for (const r of rules ?? []) ruleMap.set((r.email as string).toLowerCase(), r.action as any)

  const deptMap = new Map<string, string>()
  for (const r of deptRows ?? []) {
    if (r.department_id) deptMap.set((r.google_value as string).toLowerCase(), r.department_id as string)
  }

  const existingByEmail = new Map<string, any>()
  const existingByGoogleId = new Map<string, any>()
  for (const s of staff ?? []) {
    if (s.email) existingByEmail.set((s.email as string).toLowerCase(), s)
    if (s.google_user_id) existingByGoogleId.set(s.google_user_id as string, s)
  }

  const staffLocks = new Map<string, Set<string>>()
  for (const l of locks ?? []) {
    const set = staffLocks.get(l.staff_member_id) ?? new Set<string>()
    set.add(l.field)
    staffLocks.set(l.staff_member_id, set)
  }

  const accessToken = await getGoogleAccessToken()

  return { supabase, accessToken, domain, settings, rules: ruleMap, deptMap, existingByEmail, existingByGoogleId, staffLocks, mode, triggeredBy }
}

interface DiffEntry {
  email: string
  google_user_id: string
  action: 'add' | 'update' | 'skip' | 'exclude' | 'deactivate' | 'reactivate'
  changes?: Record<string, { from: any; to: any }>
  reason?: string
}

async function runSync(ctx: SyncContext) {
  const users = await fetchAllUsers(ctx.accessToken, ctx.domain)
  const deptSource = ctx.settings?.department_source || 'organizations'

  const counters = { added: 0, updated: 0, skipped: 0, excluded: 0, deactivated: 0, reactivated: 0 }
  const diff: DiffEntry[] = []
  const errors: { email?: string; message: string }[] = []
  const seenStaffIds = new Set<string>()

  for (const u of users) {
    try {
      const email = (u.primaryEmail ?? '').toLowerCase()
      if (!email) continue

      if (decide(email, ctx.rules, ctx.settings?.default_action || 'include') === 'exclude') {
        counters.excluded += 1
        diff.push({ email, google_user_id: u.id, action: 'exclude', reason: 'allow-list' })
        continue
      }

      const existing = ctx.existingByGoogleId.get(u.id) ?? ctx.existingByEmail.get(email)
      if (existing) seenStaffIds.add(existing.id)
      const locks = existing ? (ctx.staffLocks.get(existing.id) ?? new Set<string>()) : new Set<string>()

      const fullName = (u.name?.fullName ?? [u.name?.givenName, u.name?.familyName].filter(Boolean).join(' ') ?? '').trim() || email
      const primaryPhone = (u.phones ?? []).find(p => p.primary)?.value ?? (u.phones ?? [])[0]?.value ?? null
      const deptKey = pickDepartmentValue(u, deptSource)
      const deptId = deptKey ? (ctx.deptMap.get(deptKey.toLowerCase()) ?? null) : null
      const isActive = !u.suspended
      const joinedDate = u.creationTime ? u.creationTime.slice(0, 10) : null

      const desired: Record<string, any> = {
        google_user_id: u.id,
        full_name: fullName,
        email,
        phone: primaryPhone,
        department_id: deptId,
        joined_date: joinedDate,
        is_active: isActive
      }

      if (!existing) {
        diff.push({
          email,
          google_user_id: u.id,
          action: 'add',
          changes: Object.fromEntries(Object.entries(desired).map(([k, v]) => [k, { from: null, to: v }]))
        })
        counters.added += 1
        if (ctx.mode === 'apply') {
          const insertPayload: Record<string, any> = { role: '' }
          for (const [k, v] of Object.entries(desired)) {
            if (v !== null && v !== undefined) insertPayload[k] = v
          }
          const { data: inserted, error } = await ctx.supabase
            .from('staff_members')
            .insert(insertPayload)
            .select('id')
            .maybeSingle()
          if (error) throw error
          if (inserted?.id && u.thumbnailPhotoUrl) {
            await maybeUploadAvatarForStaff(ctx, inserted.id, u)
          }
        }
        continue
      }

      const changes: Record<string, { from: any; to: any }> = {}
      for (const [field, value] of Object.entries(desired)) {
        if (field === 'google_user_id') {
          if (existing.google_user_id !== value) changes[field] = { from: existing.google_user_id, to: value }
          continue
        }
        if (locks.has(field)) continue
        const current = existing[field] ?? null
        const next = value ?? null
        if (current !== next) changes[field] = { from: current, to: next }
      }

      if (Object.keys(changes).length === 0) {
        counters.skipped += 1
        diff.push({ email, google_user_id: u.id, action: 'skip' })
      } else {
        const wasActive = existing.is_active !== false
        if ('is_active' in changes) {
          if (isActive && !wasActive) counters.reactivated += 1
          if (!isActive && wasActive) counters.deactivated += 1
        }
        counters.updated += 1
        diff.push({ email, google_user_id: u.id, action: 'update', changes })
        if (ctx.mode === 'apply') {
          const patch: Record<string, any> = {}
          for (const k of Object.keys(changes)) {
            const v = desired[k]
            if (v !== null && v !== undefined) patch[k] = v
          }
          if (Object.keys(patch).length > 0) {
            const { error } = await ctx.supabase.from('staff_members').update(patch).eq('id', existing.id)
            if (error) throw error
          }
        }
      }

      if (ctx.mode === 'apply' && u.thumbnailPhotoUrl) {
        await maybeUploadAvatarForStaff(ctx, existing.id, u)
      }
    } catch (e: any) {
      errors.push({ email: u.primaryEmail, message: e?.message ?? String(e) })
    }
  }

  return { counters, diff, errors, seenStaffIds }
}

async function maybeUploadAvatarForStaff(ctx: SyncContext, staffId: string, u: GoogleUser) {
  if (!u.thumbnailPhotoUrl) return
  const { data: staff } = await ctx.supabase.from('staff_members').select('auth_user_id').eq('id', staffId).maybeSingle()
  const authUserId = staff?.auth_user_id
  if (!authUserId) return
  const { data: lock } = await ctx.supabase
    .from('user_profile_locks')
    .select('user_id')
    .eq('user_id', authUserId)
    .eq('field', 'avatar_url')
    .maybeSingle()
  if (lock) return
  const dl = await downloadAvatar(u.thumbnailPhotoUrl, ctx.accessToken)
  if (!dl) return
  const url = await uploadAvatar(ctx.supabase, u.id, dl.bytes, dl.contentType)
  if (!url) return
  await ctx.supabase.from('user_profiles').upsert(
    { user_id: authUserId, avatar_url: url, avatar_source: 'google' },
    { onConflict: 'user_id' }
  )
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 200, headers: corsHeaders })

  try {
    const url = new URL(req.url)
    const action = url.searchParams.get('action') || (req.method === 'POST' ? (await req.clone().json().catch(() => ({}))).action : 'status')
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

    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const bearer = authHeader.replace(/^Bearer\s+/i, '')
    const isServiceCall = !!serviceKey && bearer === serviceKey

    let email = 'cron@system'
    let isSuper = false
    if (isServiceCall) {
      isSuper = true
    } else {
      const { data: userData } = await anon.auth.getUser()
      email = userData?.user?.email?.toLowerCase() ?? ''
      if (!email) return jsonResponse({ error: 'not authenticated' }, 401)
      const { data: admin } = await service.from('admin_users').select('email, role').eq('email', email).maybeSingle()
      if (!admin) return jsonResponse({ error: 'not authorized' }, 403)
      isSuper = admin.role === 'super_admin'
      if (!isSuper) return jsonResponse({ error: 'only super admins can access Google sync' }, 403)
    }

    if (action === 'status') {
      const { data: settings } = await service.from('google_sync_settings').select('*').eq('id', 'default').maybeSingle()
      const { data: runs } = await service.from('google_sync_runs').select('*').order('started_at', { ascending: false }).limit(10)
      return jsonResponse({ settings, runs })
    }

    if (action === 'fetch_users') {
      const token = await getGoogleAccessToken()
      const domain = Deno.env.get('GOOGLE_WORKSPACE_DOMAIN') ?? ''
      if (!domain) return jsonResponse({ error: 'GOOGLE_WORKSPACE_DOMAIN missing' }, 400)
      const users = await fetchAllUsers(token, domain)
      const slim = users.map(u => ({
        id: u.id,
        email: u.primaryEmail,
        name: u.name?.fullName ?? '',
        suspended: !!u.suspended,
        orgUnitPath: u.orgUnitPath ?? '',
        department: (u.organizations ?? []).find(o => o.primary)?.department ?? (u.organizations ?? [])[0]?.department ?? ''
      }))
      return jsonResponse({ users: slim })
    }

    if (action === 'dry_run' || action === 'apply') {
      if (action === 'apply' && !isSuper) return jsonResponse({ error: 'only super admins can apply' }, 403)
      const { data: run, error: runErr } = await service
        .from('google_sync_runs')
        .insert({ mode: action, triggered_by: email })
        .select('*')
        .maybeSingle()
      if (runErr) throw runErr

      try {
        const ctx = await loadContext(service, action, email)
        const { counters, diff, errors } = await runSync(ctx)

        await service
          .from('google_sync_runs')
          .update({
            finished_at: new Date().toISOString(),
            added: counters.added,
            updated: counters.updated,
            skipped: counters.skipped,
            excluded: counters.excluded,
            deactivated: counters.deactivated,
            reactivated: counters.reactivated,
            errors,
            diff
          })
          .eq('id', run!.id)

        if (action === 'apply') {
          await service
            .from('google_sync_settings')
            .update({
              last_synced_at: new Date().toISOString(),
              last_sync_status: errors.length ? 'partial' : 'ok',
              last_sync_error: errors.length ? errors.slice(0, 3).map(e => e.message).join('; ') : null
            })
            .eq('id', 'default')
        }

        return jsonResponse({ run_id: run!.id, counters, diff, errors })
      } catch (e: any) {
        await service
          .from('google_sync_runs')
          .update({ finished_at: new Date().toISOString(), errors: [{ message: e?.message ?? String(e) }] })
          .eq('id', run!.id)
        if (action === 'apply') {
          await service.from('google_sync_settings').update({
            last_synced_at: new Date().toISOString(),
            last_sync_status: 'error',
            last_sync_error: e?.message ?? String(e)
          }).eq('id', 'default')
        }
        return jsonResponse({ error: e?.message ?? String(e) }, 500)
      }
    }

    return jsonResponse({ error: 'unknown action' }, 400)
  } catch (e: any) {
    return jsonResponse({ error: e?.message ?? String(e) }, 500)
  }
})
