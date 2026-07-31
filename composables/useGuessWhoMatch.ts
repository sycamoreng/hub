import { useSupabase } from '~/utils/supabase'
import type { ClueItem } from '~/composables/useGuessWho'

export interface GuessWhoMatch {
  id: string
  code: string
  status: 'pending' | 'active' | 'finished' | 'cancelled'
  max_guesses: number
  max_players: number
  host_user_id: string
  winner_user_id: string | null
  clues_revealed: number
  total_clues: number
  time_limit_seconds: number | null
  deadline_at: string | null
  started_at: string | null
  finished_at: string | null
  total_rounds: number
  current_round: number
  clue_mode: 'shared' | 'solo'
}

export interface GuessWhoMatchPlayer {
  user_id: string
  status: 'joined' | 'finished' | 'left'
  guesses: Array<{ first_name: string; last_name: string; correct: boolean }>
  completed: boolean
  won: boolean
  guess_count: number
  points_awarded: number
  series_points: number
  series_wins: number
  joined_at: string
  finished_at: string | null
  full_name: string | null
  role: string | null
  eliminated: boolean
}

export interface GuessWhoMatchBoard {
  match: GuessWhoMatch
  players: GuessWhoMatchPlayer[]
  clues: (string | ClueItem)[]
  answer?: { full_name: string; role: string; department: string; avatar_url: string }
}

export function useGuessWhoMatch() {
  const supabase = useSupabase()

  async function createMatch(opts: { staffId?: string; timeLimit?: number | null; clueMode?: 'shared' | 'solo' } = {}): Promise<GuessWhoMatch> {
    const { data, error } = await supabase.rpc('guess_who_match_create', {
      p_staff_id: opts.staffId ?? null,
      p_time_limit: opts.timeLimit ?? null,
      p_clue_mode: opts.clueMode ?? 'shared'
    })
    if (error) throw error
    return data as unknown as GuessWhoMatch
  }

  async function joinByCode(code: string): Promise<GuessWhoMatch> {
    const { data, error } = await supabase.rpc('guess_who_match_join', { p_code: code.trim().toUpperCase() })
    if (error) throw error
    return data as unknown as GuessWhoMatch
  }

  async function leave(matchId: string): Promise<void> {
    const { error } = await supabase.rpc('guess_who_match_leave', { p_match_id: matchId })
    if (error) throw error
  }

  async function start(matchId: string): Promise<GuessWhoMatch> {
    const { data, error } = await supabase.rpc('guess_who_match_start', { p_match_id: matchId })
    if (error) throw error
    return data as unknown as GuessWhoMatch
  }

  async function submitGuess(matchId: string, firstName: string, lastName: string): Promise<GuessWhoMatchBoard> {
    const { data, error } = await supabase.rpc('guess_who_match_submit', {
      p_match_id: matchId,
      p_first_name: firstName,
      p_last_name: lastName
    })
    if (error) throw error
    return data as unknown as GuessWhoMatchBoard
  }

  async function loadBoard(matchId: string): Promise<GuessWhoMatchBoard> {
    const { data, error } = await supabase.rpc('guess_who_match_board', { p_match_id: matchId })
    if (error) throw error
    return data as unknown as GuessWhoMatchBoard
  }

  async function setRounds(matchId: string, totalRounds: number): Promise<void> {
    const { error } = await supabase.rpc('guess_who_match_set_rounds', { p_match_id: matchId, p_total_rounds: totalRounds })
    if (error) throw error
  }

  async function nextRound(matchId: string): Promise<{ current_round: number; total_rounds: number; deadline_at: string | null }> {
    const { data, error } = await supabase.rpc('guess_who_match_next_round', { p_match_id: matchId })
    if (error) throw error
    return data as any
  }

  async function toggleEliminated(matchId: string, userId: string): Promise<{ user_id: string; eliminated: boolean }> {
    const { data, error } = await supabase.rpc('guess_who_match_toggle_eliminated', { p_match_id: matchId, p_user_id: userId })
    if (error) throw error
    return data as any
  }

  async function restart(matchId: string): Promise<void> {
    const { error } = await supabase.rpc('guess_who_match_restart', { p_match_id: matchId })
    if (error) throw error
  }

  async function getHint(matchId: string, level = 2): Promise<string> {
    const { data, error } = await supabase.rpc('guess_who_match_hint', { p_match_id: matchId, p_level: level })
    if (error) throw error
    return (data as any)?.hint ?? ''
  }

  function subscribe(matchId: string, onChange: () => void) {
    const channel = supabase
      .channel(`guess-who-match-${matchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'guess_who_matches', filter: `id=eq.${matchId}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'guess_who_match_participants', filter: `match_id=eq.${matchId}` }, onChange)
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }

  return { createMatch, joinByCode, leave, start, submitGuess, loadBoard, setRounds, nextRound, subscribe, toggleEliminated, restart, getHint }
}
