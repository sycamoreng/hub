import { useSupabase } from '~/utils/supabase'

export interface DinoMatch {
  id: string
  code: string
  status: 'pending' | 'active' | 'finished' | 'cancelled'
  max_players: number
  host_user_id: string
  time_limit_seconds: number | null
  deadline_at: string | null
  started_at: string | null
  finished_at: string | null
  total_rounds: number
  current_round: number
}

export interface DinoMatchPlayer {
  user_id: string
  status: 'joined' | 'playing' | 'crashed' | 'left'
  score: number
  duration_ms: number
  points_awarded: number
  series_points: number
  series_wins: number
  joined_at: string
  finished_at: string | null
  full_name: string | null
  role: string | null
}

export interface DinoMatchBoard {
  match: DinoMatch
  players: DinoMatchPlayer[]
}

export function useDinoMatch() {
  const supabase = useSupabase()

  async function createMatch(opts: { timeLimit?: number | null } = {}): Promise<DinoMatch> {
    const { data, error } = await supabase.rpc('dino_match_create', {
      p_time_limit: opts.timeLimit ?? null
    })
    if (error) throw error
    return (data as any).match ?? data
  }

  async function joinByCode(code: string): Promise<DinoMatch> {
    const { data, error } = await supabase.rpc('dino_match_join', { p_code: code.trim().toUpperCase() })
    if (error) throw error
    return data as unknown as DinoMatch
  }

  async function leave(matchId: string): Promise<void> {
    const { error } = await supabase.rpc('dino_match_leave', { p_match_id: matchId })
    if (error) throw error
  }

  async function start(matchId: string): Promise<any> {
    const { data, error } = await supabase.rpc('dino_match_start', { p_match_id: matchId })
    if (error) throw error
    return data
  }

  async function crash(matchId: string, score: number, durationMs: number): Promise<DinoMatchBoard> {
    const { data, error } = await supabase.rpc('dino_match_crash', {
      p_match_id: matchId,
      p_score: Math.floor(score),
      p_duration_ms: Math.round(durationMs)
    })
    if (error) throw error
    return data as unknown as DinoMatchBoard
  }

  async function loadBoard(matchId: string): Promise<DinoMatchBoard> {
    const { data, error } = await supabase.rpc('dino_match_board', { p_match_id: matchId })
    if (error) throw error
    return data as unknown as DinoMatchBoard
  }

  function subscribe(matchId: string, onChange: () => void) {
    const channel = supabase
      .channel(`dino-match-${matchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'dino_matches', filter: `id=eq.${matchId}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'dino_match_participants', filter: `match_id=eq.${matchId}` }, onChange)
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }

  async function setRounds(matchId: string, totalRounds: number): Promise<void> {
    const { error } = await supabase.rpc('dino_match_set_rounds', { p_match_id: matchId, p_total_rounds: totalRounds })
    if (error) throw error
  }

  async function nextRound(matchId: string): Promise<{ current_round: number; total_rounds: number; deadline_at: string | null }> {
    const { data, error } = await supabase.rpc('dino_match_next_round', { p_match_id: matchId })
    if (error) throw error
    return data as any
  }

  return { createMatch, joinByCode, leave, start, crash, loadBoard, setRounds, nextRound, subscribe }
}
