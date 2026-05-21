import { useSupabase } from '~/utils/supabase'

export interface KudosValue {
  id: string
  code: string
  label: string
  emoji: string
  color: string
  sort_order: number
  is_active: boolean
}

export interface Badge {
  id: string
  code: string
  name: string
  description: string
  emoji: string
  color: string
  threshold: number
  metric: string
  is_active: boolean
  points_award?: number
}

export interface LeaderRow {
  user_id: string
  points: number
  name: string
  staff_id: string | null
  avatar: string | null
  role: string | null
}

const KIND_DEDUPE = new Set([
  'post_created',
  'comment_posted',
  'reaction_received',
  'kudos_given',
  'kudos_received',
  'onboarding_step_completed',
  'attendance_clock_in',
  'spark_correct',
  'spark_participated',
  'profile_completed'
])

export function colorClasses(c: string): { bg: string; text: string; border: string; ring: string } {
  const map: Record<string, { bg: string; text: string; border: string; ring: string }> = {
    emerald: { bg: 'bg-emerald-50', text: 'text-emerald-700', border: 'border-emerald-200', ring: 'ring-emerald-200' },
    amber: { bg: 'bg-amber-50', text: 'text-amber-700', border: 'border-amber-200', ring: 'ring-amber-200' },
    sky: { bg: 'bg-sky-50', text: 'text-sky-700', border: 'border-sky-200', ring: 'ring-sky-200' },
    rose: { bg: 'bg-rose-50', text: 'text-rose-700', border: 'border-rose-200', ring: 'ring-rose-200' },
    teal: { bg: 'bg-teal-50', text: 'text-teal-700', border: 'border-teal-200', ring: 'ring-teal-200' },
    leaf: { bg: 'bg-leaf-50', text: 'text-leaf-700', border: 'border-leaf-200', ring: 'ring-leaf-200' },
    sycamore: { bg: 'bg-sycamore-50', text: 'text-sycamore-700', border: 'border-sycamore-200', ring: 'ring-sycamore-200' },
    slate: { bg: 'bg-slate-50', text: 'text-slate-700', border: 'border-slate-200', ring: 'ring-slate-200' }
  }
  return map[c] ?? map.slate
}

export function useGamification() {
  const supabase = useSupabase()

  async function getWeight(kind: string): Promise<number> {
    const { data } = await supabase
      .from('point_weights')
      .select('points, is_active')
      .eq('event_kind', kind)
      .maybeSingle()
    if (!data || !(data as any).is_active) return 0
    return Number((data as any).points) || 0
  }

  async function awardPoints(opts: {
    userId: string
    kind: string
    refType?: string
    refId?: string
    note?: string
    points?: number
  }): Promise<void> {
    try {
      const { userId, kind, refType = '', refId = '', note = '' } = opts
      let points = opts.points
      if (points === undefined) points = await getWeight(kind)
      if (!points) return

      if (KIND_DEDUPE.has(kind) && refId) {
        await supabase.from('points_events').upsert({
          user_id: userId,
          event_kind: kind,
          ref_type: refType,
          ref_id: refId,
          note,
          points
        }, { onConflict: 'user_id,event_kind,ref_type,ref_id', ignoreDuplicates: true })
      } else {
        await supabase.from('points_events').insert({
          user_id: userId,
          event_kind: kind,
          ref_type: refType,
          ref_id: refId,
          note,
          points
        })
      }
      await checkBadges(userId)
    } catch {
      /* non-fatal */
    }
  }

  async function getUserPoints(userId: string): Promise<number> {
    const { data } = await supabase
      .from('points_events')
      .select('points')
      .eq('user_id', userId)
    return (data ?? []).reduce((sum: number, r: any) => sum + (r.points || 0), 0)
  }

  async function getLeaderboard(scope: 'week' | 'month' | 'all' = 'month', limit = 20): Promise<LeaderRow[]> {
    let sinceIso: string | null = null
    if (scope === 'week') {
      const d = new Date()
      d.setDate(d.getDate() - 7)
      sinceIso = d.toISOString()
    } else if (scope === 'month') {
      const d = new Date()
      d.setDate(d.getDate() - 30)
      sinceIso = d.toISOString()
    }

    let q = supabase.from('points_events').select('user_id, points')
    if (sinceIso) q = q.gte('created_at', sinceIso)
    const { data: events } = await q
    const totals = new Map<string, number>()
    for (const e of events ?? []) {
      totals.set((e as any).user_id, (totals.get((e as any).user_id) ?? 0) + ((e as any).points || 0))
    }
    const userIds = Array.from(totals.keys())
    if (userIds.length === 0) return []

    const [{ data: staff }, { data: profiles }] = await Promise.all([
      supabase.from('staff_members').select('id, full_name, role, auth_user_id').in('auth_user_id', userIds),
      supabase.from('user_profiles').select('user_id, avatar_url').in('user_id', userIds)
    ])
    const staffMap = new Map((staff ?? []).map((s: any) => [s.auth_user_id, s]))
    const profMap = new Map((profiles ?? []).map((p: any) => [p.user_id, p]))

    const rows: LeaderRow[] = userIds.map(uid => {
      const s = staffMap.get(uid) as any
      const p = profMap.get(uid) as any
      return {
        user_id: uid,
        points: totals.get(uid) ?? 0,
        name: s?.full_name || 'Sycamore staff',
        staff_id: s?.id ?? null,
        avatar: p?.avatar_url ?? null,
        role: s?.role ?? null
      }
    })
    rows.sort((a, b) => b.points - a.points)
    return rows.slice(0, limit)
  }

  async function giveKudos(params: { toUserId: string; valueCode: string; message: string }) {
    const { data: sess } = await supabase.auth.getUser()
    const fromId = sess.user?.id
    if (!fromId) throw new Error('Not authenticated')
    if (fromId === params.toUserId) throw new Error('Cannot give kudos to yourself')

    const { data, error } = await supabase.from('kudos').insert({
      from_user_id: fromId,
      to_user_id: params.toUserId,
      value_code: params.valueCode,
      message: params.message
    }).select().maybeSingle()
    if (error) throw error

    const kid = (data as any)?.id as string
    await awardPoints({ userId: fromId, kind: 'kudos_given', refType: 'kudos', refId: kid })
    await awardPoints({ userId: params.toUserId, kind: 'kudos_received', refType: 'kudos', refId: kid })

    try {
      await supabase.from('notifications').insert({
        recipient_id: params.toUserId,
        actor_id: fromId,
        type: 'kudos_received',
        title: 'You got kudos!',
        body: params.message || 'A colleague recognized you.',
        link: '/recognition'
      })
    } catch { /* optional */ }
    return data
  }

  async function loadRecentKudos(limit = 20) {
    const { data } = await supabase
      .from('kudos')
      .select('*')
      .eq('is_public', true)
      .order('created_at', { ascending: false })
      .limit(limit)
    const rows = data ?? []
    const uids = Array.from(new Set(rows.flatMap((r: any) => [r.from_user_id, r.to_user_id])))
    if (!uids.length) return { rows, userMap: {} as Record<string, any> }
    const [{ data: staff }, { data: profiles }] = await Promise.all([
      supabase.from('staff_members').select('id, full_name, role, auth_user_id').in('auth_user_id', uids),
      supabase.from('user_profiles').select('user_id, avatar_url').in('user_id', uids)
    ])
    const userMap: Record<string, any> = {}
    for (const uid of uids) {
      const s = (staff ?? []).find((x: any) => x.auth_user_id === uid) as any
      const p = (profiles ?? []).find((x: any) => x.user_id === uid) as any
      userMap[uid] = {
        name: s?.full_name || 'Sycamore staff',
        role: s?.role || '',
        staff_id: s?.id ?? null,
        avatar: p?.avatar_url ?? null
      }
    }
    return { rows, userMap }
  }

  async function loadKudosValues(): Promise<KudosValue[]> {
    const { data } = await supabase
      .from('kudos_values')
      .select('*')
      .eq('is_active', true)
      .order('sort_order')
    return (data ?? []) as any
  }

  async function loadBadges(): Promise<Badge[]> {
    const { data } = await supabase
      .from('badges')
      .select('*')
      .eq('is_active', true)
      .order('sort_order')
    return (data ?? []) as any
  }

  async function loadUserBadges(userId: string) {
    const { data } = await supabase
      .from('user_badges')
      .select('badge_id, awarded_at')
      .eq('user_id', userId)
    return data ?? []
  }

  async function computeMetric(userId: string, metric: string): Promise<number> {
    if (metric === 'points_total') {
      return await getUserPoints(userId)
    }
    if (metric === 'posts_count') {
      const { count } = await supabase.from('posts').select('id', { count: 'exact', head: true }).eq('author_id', userId)
      return count ?? 0
    }
    if (metric === 'comments_count') {
      const { count } = await supabase.from('comments').select('id', { count: 'exact', head: true }).eq('user_id', userId)
      return count ?? 0
    }
    if (metric === 'kudos_given_count') {
      const { count } = await supabase.from('kudos').select('id', { count: 'exact', head: true }).eq('from_user_id', userId)
      return count ?? 0
    }
    if (metric === 'kudos_received_count') {
      const { count } = await supabase.from('kudos').select('id', { count: 'exact', head: true }).eq('to_user_id', userId)
      return count ?? 0
    }
    if (metric === 'learning_count') {
      const { count } = await supabase.from('points_events').select('id', { count: 'exact', head: true }).eq('user_id', userId).eq('event_kind', 'onboarding_step_completed')
      return count ?? 0
    }
    if (metric === 'spark_correct_count') {
      const { count } = await supabase.from('spark_responses').select('id', { count: 'exact', head: true }).eq('user_id', userId).eq('is_correct', true)
      return count ?? 0
    }
    if (metric === 'guess_who_correct_count') {
      const { count } = await supabase.from('guess_who_attempts').select('id', { count: 'exact', head: true }).eq('user_id', userId).eq('won', true)
      return count ?? 0
    }
    if (metric === 'wordle_win_count') {
      const { count } = await supabase.from('points_events').select('id', { count: 'exact', head: true }).eq('user_id', userId).eq('event_kind', 'wordle_win')
      return count ?? 0
    }
    if (metric === 'typing_60wpm_count') {
      const { count } = await supabase.from('typing_runs').select('id', { count: 'exact', head: true }).eq('user_id', userId).gte('wpm', 60)
      return count ?? 0
    }
    return 0
  }

  async function checkBadges(userId: string): Promise<void> {
    try {
      const [badges, owned] = await Promise.all([loadBadges(), loadUserBadges(userId)])
      const ownedIds = new Set(owned.map((r: any) => r.badge_id))
      for (const b of badges) {
        if (ownedIds.has(b.id)) continue
        const value = await computeMetric(userId, b.metric)
        if (value >= b.threshold) {
          const { error: badgeErr } = await supabase
            .from('user_badges')
            .insert({ user_id: userId, badge_id: b.id })
          if (badgeErr) continue
          const award = Number(b.points_award || 0)
          if (award > 0) {
            await supabase.from('points_events').insert({
              user_id: userId,
              event_kind: 'badge_awarded',
              ref_type: 'badge',
              ref_id: b.id,
              points: award,
              note: b.name
            })
          }
          try {
            await supabase.from('notifications').insert({
              recipient_id: userId,
              type: 'badge_awarded',
              title: `New badge: ${b.name}`,
              body: b.description,
              link: '/recognition'
            })
          } catch { /* optional */ }
        }
      }
    } catch {
      /* non-fatal */
    }
  }

  async function getTodaySpark() {
    const today = new Date().toISOString().slice(0, 10)
    const { data } = await supabase
      .from('daily_sparks')
      .select('*')
      .eq('is_active', true)
      .lte('active_on', today)
      .order('active_on', { ascending: false })
      .limit(1)
      .maybeSingle()
    return data
  }

  async function getMySparkResponse(sparkId: string, userId: string) {
    const { data } = await supabase
      .from('spark_responses')
      .select('*')
      .eq('spark_id', sparkId)
      .eq('user_id', userId)
      .maybeSingle()
    return data
  }

  async function answerSpark(sparkId: string, userId: string, choiceIndex: number, correctIndex: number | null, pointsAward: number) {
    const isCorrect = correctIndex !== null && correctIndex === choiceIndex
    const { data, error } = await supabase.from('spark_responses').insert({
      spark_id: sparkId,
      user_id: userId,
      choice_index: choiceIndex,
      is_correct: isCorrect
    }).select().maybeSingle()
    if (error) throw error
    await awardPoints({
      userId,
      kind: isCorrect ? 'spark_correct' : 'spark_participated',
      refType: 'spark',
      refId: sparkId,
      points: isCorrect ? pointsAward : undefined
    })
    return data
  }

  return {
    awardPoints,
    getUserPoints,
    getLeaderboard,
    giveKudos,
    loadRecentKudos,
    loadKudosValues,
    loadBadges,
    loadUserBadges,
    computeMetric,
    checkBadges,
    getTodaySpark,
    getMySparkResponse,
    answerSpark
  }
}
