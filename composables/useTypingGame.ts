import { useSupabase } from '~/utils/supabase'

export type TypingMode = 'timed_30s' | 'timed_60s' | 'timed_120s' | 'sprint'
export const TYPING_MODES: { id: TypingMode; label: string; durationMs: number }[] = [
  { id: 'timed_30s', label: '30 seconds', durationMs: 30_000 },
  { id: 'timed_60s', label: '60 seconds', durationMs: 60_000 },
  { id: 'timed_120s', label: '2 minutes', durationMs: 120_000 },
  { id: 'sprint', label: 'Sprint (single phrase)', durationMs: 0 }
]

export interface TypingCategory {
  id: string
  slug: string
  name: string
  description: string
  sort_order: number
  is_active: boolean
}

export interface TypingPrompt {
  id: string
  category_id: string | null
  text: string
  length_tier: 'short' | 'medium' | 'long'
  is_active: boolean
}

export interface TypingRun {
  id: string
  user_id: string
  category_id: string | null
  mode: TypingMode
  wpm: number
  accuracy: number
  characters_typed: number
  words_typed: number
  errors: number
  duration_ms: number
  finished_at: string
}

export interface TypingMatch {
  id: string
  host_user_id: string
  code: string
  category_id: string | null
  prompt_id: string | null
  prompt_text: string
  mode: TypingMode
  duration_ms: number
  status: 'pending' | 'active' | 'finished' | 'cancelled'
  started_at: string | null
  finished_at: string | null
  created_at: string
}

export interface TypingMatchParticipant {
  id: string
  match_id: string
  user_id: string
  status: 'invited' | 'joined' | 'finished' | 'declined'
  wpm: number
  accuracy: number
  characters_typed: number
  words_typed: number
  errors: number
  duration_ms: number
  rank: number | null
  joined_at: string | null
  finished_at: string | null
  profile?: { auth_user_id: string; full_name: string; role: string } | null
}

export function useTypingGame() {
  const supabase = useSupabase()

  async function loadCategories(): Promise<TypingCategory[]> {
    const { data } = await supabase
      .from('typing_categories')
      .select('*')
      .eq('is_active', true)
      .order('sort_order')
    return (data as TypingCategory[]) ?? []
  }

  async function loadPrompts(opts: { categoryId?: string; tier?: 'short' | 'medium' | 'long' } = {}): Promise<TypingPrompt[]> {
    let q = supabase.from('typing_prompts').select('*').eq('is_active', true)
    if (opts.categoryId) q = q.eq('category_id', opts.categoryId)
    if (opts.tier) q = q.eq('length_tier', opts.tier)
    const { data } = await q
    return (data as TypingPrompt[]) ?? []
  }

  async function submitRun(payload: {
    categoryId: string | null
    mode: TypingMode
    wpm: number
    accuracy: number
    charactersTyped: number
    wordsTyped: number
    errors: number
    durationMs: number
  }) {
    const { data, error } = await supabase.rpc('typing_submit_run', {
      p_category_id: payload.categoryId,
      p_mode: payload.mode,
      p_wpm: payload.wpm,
      p_accuracy: payload.accuracy,
      p_characters_typed: payload.charactersTyped,
      p_words_typed: payload.wordsTyped,
      p_errors: payload.errors,
      p_duration_ms: payload.durationMs
    })
    if (error) throw error
    return data as { run: TypingRun; points_awarded: number; is_personal_best: boolean; previous_best: number; daily_remaining: number }
  }

  async function loadMyRuns(limit = 25): Promise<TypingRun[]> {
    const { data: u } = await supabase.auth.getUser()
    if (!u.user) return []
    const { data } = await supabase
      .from('typing_runs')
      .select('*')
      .eq('user_id', u.user.id)
      .order('finished_at', { ascending: false })
      .limit(limit)
    return (data as TypingRun[]) ?? []
  }

  async function loadMyBest(): Promise<Record<TypingMode, number>> {
    const { data: u } = await supabase.auth.getUser()
    const result: Record<TypingMode, number> = { timed_30s: 0, timed_60s: 0, timed_120s: 0, sprint: 0 }
    if (!u.user) return result
    const { data } = await supabase
      .from('typing_runs')
      .select('mode, wpm')
      .eq('user_id', u.user.id)
    for (const r of (data as { mode: TypingMode; wpm: number }[] | null) ?? []) {
      if (r.wpm > result[r.mode]) result[r.mode] = Number(r.wpm)
    }
    return result
  }

  async function loadLeaderboard(opts: { mode?: TypingMode; categoryId?: string; limit?: number } = {}) {
    let q = supabase
      .from('typing_runs')
      .select('id, user_id, mode, wpm, accuracy, words_typed, finished_at, category:typing_categories(id, name)')
      .order('wpm', { ascending: false })
      .limit(opts.limit ?? 50)
    if (opts.mode) q = q.eq('mode', opts.mode)
    if (opts.categoryId) q = q.eq('category_id', opts.categoryId)
    const { data } = await q
    if (!data?.length) return [] as Array<any>
    const userIds = [...new Set(data.map(r => r.user_id))]
    const { data: profiles } = await supabase
      .from('staff_members')
      .select('auth_user_id, full_name, role')
      .in('auth_user_id', userIds)
    const map = new Map((profiles ?? []).map((p: any) => [p.auth_user_id, p]))
    const best = new Map<string, any>()
    for (const r of data as any[]) {
      const existing = best.get(r.user_id)
      if (!existing || existing.wpm < r.wpm) {
        best.set(r.user_id, { ...r, profile: map.get(r.user_id) ?? null })
      }
    }
    return Array.from(best.values()).sort((a, b) => b.wpm - a.wpm)
  }

  // ---------------- Multiplayer matches ----------------

  async function createMatch(opts: { categoryId: string | null; promptId: string | null; mode: TypingMode }) {
    const { data, error } = await supabase.rpc('typing_match_create', {
      p_category_id: opts.categoryId,
      p_prompt_id: opts.promptId,
      p_mode: opts.mode
    })
    if (error) throw error
    return data as TypingMatch
  }

  async function inviteToMatch(matchId: string, userId: string) {
    const { data, error } = await supabase.rpc('typing_match_invite', {
      p_match_id: matchId,
      p_target_user_id: userId
    })
    if (error) throw error
    return data
  }

  async function joinMatch(code: string) {
    const { data, error } = await supabase.rpc('typing_match_join', { p_code: code.trim().toUpperCase() })
    if (error) throw error
    return data as TypingMatch
  }

  async function declineMatch(matchId: string) {
    const { error } = await supabase.rpc('typing_match_decline', { p_match_id: matchId })
    if (error) throw error
  }

  async function startMatch(matchId: string) {
    const { data, error } = await supabase.rpc('typing_match_start', { p_match_id: matchId })
    if (error) throw error
    return data as TypingMatch
  }

  async function submitMatchRun(matchId: string, payload: {
    wpm: number; accuracy: number; charactersTyped: number; wordsTyped: number; errors: number; durationMs: number
  }) {
    const { data, error } = await supabase.rpc('typing_match_submit', {
      p_match_id: matchId,
      p_wpm: payload.wpm,
      p_accuracy: payload.accuracy,
      p_characters_typed: payload.charactersTyped,
      p_words_typed: payload.wordsTyped,
      p_errors: payload.errors,
      p_duration_ms: payload.durationMs
    })
    if (error) throw error
    return data as any
  }

  async function finalizeMatch(matchId: string) {
    const { data, error } = await supabase.rpc('typing_match_finalize', { p_match_id: matchId })
    if (error) throw error
    return data as TypingMatch
  }

  async function loadMatchByCode(code: string): Promise<TypingMatch | null> {
    const { data } = await supabase
      .from('typing_matches')
      .select('*')
      .eq('code', code.trim().toUpperCase())
      .maybeSingle()
    return (data as TypingMatch) ?? null
  }

  async function loadMatchById(id: string): Promise<TypingMatch | null> {
    const { data } = await supabase.from('typing_matches').select('*').eq('id', id).maybeSingle()
    return (data as TypingMatch) ?? null
  }

  async function loadMatchParticipants(matchId: string): Promise<TypingMatchParticipant[]> {
    const { data } = await supabase
      .from('typing_match_participants')
      .select('*')
      .eq('match_id', matchId)
      .order('joined_at', { ascending: true, nullsFirst: false })
    if (!data?.length) return []
    const userIds = [...new Set(data.map((p: any) => p.user_id))]
    const { data: profiles } = await supabase
      .from('staff_members')
      .select('auth_user_id, full_name, role')
      .in('auth_user_id', userIds)
    const map = new Map((profiles ?? []).map((p: any) => [p.auth_user_id, p]))
    return (data as any[]).map(p => ({ ...p, profile: map.get(p.user_id) ?? null }))
  }

  function subscribeMatch(matchId: string, onChange: () => void) {
    const channel = supabase
      .channel(`typing-match-${matchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'typing_matches', filter: `id=eq.${matchId}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'typing_match_participants', filter: `match_id=eq.${matchId}` }, onChange)
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }

  async function searchInvitees(term: string, limit = 8) {
    let q = supabase
      .from('staff_members')
      .select('auth_user_id, full_name, role')
      .not('auth_user_id', 'is', null)
      .order('full_name')
      .limit(limit)
    if (term.trim()) q = q.ilike('full_name', `%${term.trim()}%`)
    const { data } = await q
    return (data as Array<{ auth_user_id: string; full_name: string; role: string }>) ?? []
  }

  return {
    loadCategories, loadPrompts, submitRun, loadMyRuns, loadMyBest, loadLeaderboard,
    createMatch, inviteToMatch, joinMatch, declineMatch, startMatch,
    submitMatchRun, finalizeMatch, loadMatchByCode, loadMatchById,
    loadMatchParticipants, subscribeMatch, searchInvitees
  }
}
