import { useSupabase } from '~/utils/supabase'

export interface CrosswordPuzzle {
  grid: (string | null)[][]
  clues_across: CrosswordClue[]
  clues_down: CrosswordClue[]
}

export interface CrosswordClue {
  number: number
  clue: string
  answer: string
  row: number
  col: number
  length: number
}

export interface CrosswordMatch {
  id: string
  code: string
  status: 'pending' | 'active' | 'finished' | 'cancelled'
  max_players: number
  host_user_id: string
  winner_user_id: string | null
  time_limit_seconds: number | null
  deadline_at: string | null
  started_at: string | null
  finished_at: string | null
  total_rounds: number
  current_round: number
}

export interface CrosswordMatchPlayer {
  user_id: string
  status: 'joined' | 'playing' | 'finished' | 'left'
  cells_filled: number
  total_cells: number
  completed: boolean
  won: boolean
  time_seconds: number
  points_awarded: number
  series_points: number
  series_wins: number
  joined_at: string
  finished_at: string | null
  full_name: string | null
  role: string | null
}

export interface CrosswordMatchBoard {
  match: CrosswordMatch
  puzzle: CrosswordPuzzle
  players: CrosswordMatchPlayer[]
}

export function useCrossword() {
  const supabase = useSupabase()

  async function loadDaily(): Promise<{ puzzle_id: string; puzzle_date: string; puzzle: CrosswordPuzzle; attempt: { id: string; grid_state: any; completed: boolean; time_seconds: number } }> {
    const { data, error } = await supabase.rpc('crossword_daily_puzzle')
    if (error) throw error
    const d = data as any
    return {
      puzzle_id: d.puzzle_id,
      puzzle_date: d.puzzle_date,
      puzzle: { grid: d.grid, clues_across: d.clues_across, clues_down: d.clues_down },
      attempt: d.attempt
    }
  }

  async function checkDaily(grid: (string | null)[][], timeSeconds: number): Promise<{ correct: boolean; completed: boolean; time_seconds: number }> {
    const { data, error } = await supabase.rpc('crossword_daily_check', { p_grid: grid, p_time_seconds: timeSeconds })
    if (error) throw error
    return data as any
  }

  async function createMatch(opts: { timeLimit?: number | null } = {}): Promise<CrosswordMatch> {
    const { data, error } = await supabase.rpc('crossword_match_create', { p_time_limit: opts.timeLimit ?? null })
    if (error) throw error
    return data as unknown as CrosswordMatch
  }

  async function joinByCode(code: string): Promise<CrosswordMatch> {
    const { data, error } = await supabase.rpc('crossword_match_join', { p_code: code.trim().toUpperCase() })
    if (error) throw error
    return data as unknown as CrosswordMatch
  }

  async function leave(matchId: string): Promise<void> {
    const { error } = await supabase.rpc('crossword_match_leave', { p_match_id: matchId })
    if (error) throw error
  }

  async function start(matchId: string): Promise<any> {
    const { data, error } = await supabase.rpc('crossword_match_start', { p_match_id: matchId })
    if (error) throw error
    return data
  }

  async function submit(matchId: string, grid: (string | null)[][], timeSeconds: number): Promise<CrosswordMatchBoard | { correct: false }> {
    const { data, error } = await supabase.rpc('crossword_match_submit', { p_match_id: matchId, p_grid: grid, p_time_seconds: timeSeconds })
    if (error) throw error
    return data as any
  }

  async function loadBoard(matchId: string): Promise<CrosswordMatchBoard> {
    const { data, error } = await supabase.rpc('crossword_match_board', { p_match_id: matchId })
    if (error) throw error
    return data as unknown as CrosswordMatchBoard
  }

  function subscribe(matchId: string, onChange: () => void) {
    const channel = supabase
      .channel(`crossword-match-${matchId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'crossword_matches', filter: `id=eq.${matchId}` }, onChange)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'crossword_match_participants', filter: `match_id=eq.${matchId}` }, onChange)
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }

  async function setRounds(matchId: string, totalRounds: number): Promise<void> {
    const { error } = await supabase.rpc('crossword_match_set_rounds', { p_match_id: matchId, p_total_rounds: totalRounds })
    if (error) throw error
  }

  async function nextRound(matchId: string): Promise<{ current_round: number; total_rounds: number; deadline_at: string | null }> {
    const { data, error } = await supabase.rpc('crossword_match_next_round', { p_match_id: matchId })
    if (error) throw error
    return data as any
  }

  return { loadDaily, checkDaily, createMatch, joinByCode, leave, start, submit, loadBoard, setRounds, nextRound, subscribe }
}
