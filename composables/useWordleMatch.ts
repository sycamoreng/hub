import { useSupabase } from '~/utils/supabase'

export interface WordleMatch {
  id: string
  code: string
  status: 'pending' | 'active' | 'finished' | 'cancelled'
  letter_count: number
  max_guesses: number
  max_players: number
  host_user_id: string
  winner_user_id: string | null
  started_at: string | null
  finished_at: string | null
  target: string | null
  time_limit_seconds: number | null
  deadline_at: string | null
  total_rounds: number
  current_round: number
}

export interface WordleMatchPlayer {
  user_id: string
  status: 'joined' | 'finished' | 'left'
  guess_count: number
  completed: boolean
  won: boolean
  rank: number | null
  joined_at: string
  finished_at: string | null
  results: string[][]
  guesses: string[]
  full_name: string | null
  role: string | null
  points_awarded: number
  series_points: number
  series_wins: number
}

export interface WordleMatchBoard {
  match: WordleMatch
  players: WordleMatchPlayer[]
}

export function useWordleMatch() {
  const supabase = useSupabase()

  async function createMatch(opts: { letterCount?: number; maxGuesses?: number; maxPlayers?: number; timeLimit?: number | null } = {}): Promise<WordleMatch> {
    const { data, error } = await supabase.rpc('wordle_match_create', {
      p_letter_count: opts.letterCount ?? null,
      p_max_guesses: opts.maxGuesses ?? null,
      p_max_players: opts.maxPlayers ?? 6,
      p_time_limit: opts.timeLimit ?? null
    })
    if (error) throw error
    return data as unknown as WordleMatch
  }

  async function joinByCode(code: string): Promise<WordleMatch> {
    const { data, error } = await supabase.rpc('wordle_match_join', { p_code: code.trim().toUpperCase() })
    if (error) throw error
    return data as unknown as WordleMatch
  }

  async function lookupByCode(code: string): Promise<WordleMatch | null> {
    const { data, error } = await supabase.rpc('wordle_match_lookup_by_code', { p_code: code.trim().toUpperCase() })
    if (error) return null
    return data as unknown as WordleMatch
  }

  async function leave(matchId: string): Promise<void> {
    const { error } = await supabase.rpc('wordle_match_leave', { p_match_id: matchId })
    if (error) throw error
  }

  async function start(matchId: string): Promise<WordleMatch> {
    const { data, error } = await supabase.rpc('wordle_match_start', { p_match_id: matchId })
    if (error) throw error
    return data as unknown as WordleMatch
  }

  async function submitGuess(matchId: string, guess: string) {
    const { data, error } = await supabase.rpc('wordle_match_submit_guess', {
      p_match_id: matchId,
      p_guess: guess
    })
    if (error) throw error
    return data as {
      match_id: string
      letter_count: number
      max_guesses: number
      guesses: string[]
      results: string[][]
      completed: boolean
      won: boolean
      points_awarded: number
      first_solver: boolean
      target: string | null
    }
  }

  async function loadBoard(matchId: string): Promise<WordleMatchBoard> {
    const { data, error } = await supabase.rpc('wordle_match_board', { p_match_id: matchId })
    if (error) throw error
    return data as unknown as WordleMatchBoard
  }

  async function setRounds(matchId: string, totalRounds: number): Promise<void> {
    const { error } = await supabase.rpc('wordle_match_set_rounds', { p_match_id: matchId, p_total_rounds: totalRounds })
    if (error) throw error
  }

  async function nextRound(matchId: string): Promise<{ current_round: number; total_rounds: number; deadline_at: string | null }> {
    const { data, error } = await supabase.rpc('wordle_match_next_round', { p_match_id: matchId })
    if (error) throw error
    return data as any
  }

  function subscribe(matchId: string, onChange: () => void) {
    const channel = supabase
      .channel(`wordle-match-${matchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'wordle_matches', filter: `id=eq.${matchId}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'wordle_match_participants', filter: `match_id=eq.${matchId}` }, onChange)
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }

  return { createMatch, joinByCode, lookupByCode, leave, start, submitGuess, loadBoard, setRounds, nextRound, subscribe }
}
