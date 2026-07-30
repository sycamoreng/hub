import { useSupabase } from '~/utils/supabase'

export interface CodeBreakerGame {
  id: string
  puzzle_date: string
  guesses: string[][]
  feedback: string[][]
  completed: boolean
  won: boolean
  guess_count: number
  secret_code?: string[]
}

export interface CodeBreakerMatch {
  id: string
  code: string
  status: 'pending' | 'active' | 'finished' | 'cancelled'
  max_guesses: number
  max_players: number
  host_user_id: string
  winner_user_id: string | null
  time_limit_seconds: number | null
  deadline_at: string | null
  started_at: string | null
  finished_at: string | null
  secret_code?: string[]
  total_rounds: number
  current_round: number
}

export interface CodeBreakerMatchPlayer {
  user_id: string
  status: 'joined' | 'finished' | 'left'
  guesses: string[][]
  feedback: string[][]
  guess_count: number
  completed: boolean
  won: boolean
  points_awarded: number
  series_points: number
  series_wins: number
  joined_at: string
  finished_at: string | null
  full_name: string | null
  role: string | null
}

export interface CodeBreakerMatchBoard {
  match: CodeBreakerMatch
  players: CodeBreakerMatchPlayer[]
}

export const COLORS = ['red', 'blue', 'green', 'yellow', 'purple', 'orange'] as const
export type PegColor = typeof COLORS[number]

export function useCodeBreaker() {
  const supabase = useSupabase()

  async function startDaily(): Promise<CodeBreakerGame> {
    const { data, error } = await supabase.rpc('codebreaker_daily_start')
    if (error) throw error
    return data as unknown as CodeBreakerGame
  }

  async function dailyGuess(guess: string[]): Promise<CodeBreakerGame> {
    const { data, error } = await supabase.rpc('codebreaker_daily_guess', { p_guess: guess })
    if (error) throw error
    return data as unknown as CodeBreakerGame
  }

  async function createMatch(opts: { timeLimit?: number | null } = {}): Promise<CodeBreakerMatch> {
    const { data, error } = await supabase.rpc('codebreaker_match_create', { p_time_limit: opts.timeLimit ?? null })
    if (error) throw error
    return data as unknown as CodeBreakerMatch
  }

  async function joinByCode(code: string): Promise<CodeBreakerMatch> {
    const { data, error } = await supabase.rpc('codebreaker_match_join', { p_code: code.trim().toUpperCase() })
    if (error) throw error
    return data as unknown as CodeBreakerMatch
  }

  async function leave(matchId: string): Promise<void> {
    const { error } = await supabase.rpc('codebreaker_match_leave', { p_match_id: matchId })
    if (error) throw error
  }

  async function start(matchId: string): Promise<any> {
    const { data, error } = await supabase.rpc('codebreaker_match_start', { p_match_id: matchId })
    if (error) throw error
    return data
  }

  async function matchGuess(matchId: string, guess: string[]): Promise<CodeBreakerMatchBoard> {
    const { data, error } = await supabase.rpc('codebreaker_match_guess', { p_match_id: matchId, p_guess: guess })
    if (error) throw error
    return data as unknown as CodeBreakerMatchBoard
  }

  async function loadBoard(matchId: string): Promise<CodeBreakerMatchBoard> {
    const { data, error } = await supabase.rpc('codebreaker_match_board', { p_match_id: matchId })
    if (error) throw error
    return data as unknown as CodeBreakerMatchBoard
  }

  function subscribe(matchId: string, onChange: () => void) {
    const channel = supabase
      .channel(`codebreaker-match-${matchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'codebreaker_matches', filter: `id=eq.${matchId}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'codebreaker_match_participants', filter: `match_id=eq.${matchId}` }, onChange)
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }

  async function setRounds(matchId: string, totalRounds: number): Promise<void> {
    const { error } = await supabase.rpc('codebreaker_match_set_rounds', { p_match_id: matchId, p_total_rounds: totalRounds })
    if (error) throw error
  }

  async function nextRound(matchId: string): Promise<{ current_round: number; total_rounds: number; deadline_at: string | null }> {
    const { data, error } = await supabase.rpc('codebreaker_match_next_round', { p_match_id: matchId })
    if (error) throw error
    return data as any
  }

  return { startDaily, dailyGuess, createMatch, joinByCode, leave, start, matchGuess, loadBoard, setRounds, nextRound, subscribe, COLORS }
}
