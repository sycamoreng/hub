import { useSupabase } from '~/utils/supabase'

export interface GuessEntry {
  first_name: string
  last_name: string
  correct: boolean
}

export interface GuessWhoState {
  status: 'active' | 'no_puzzle'
  puzzle_date: string
  clues: string[]
  has_avatar: boolean
  guesses: GuessEntry[]
  used_photo_hint: boolean
  completed: boolean
  won: boolean
  points_awarded: number
  max_guesses: number
  answer?: {
    full_name: string
    role: string
    department: string
    avatar_url: string
  }
}

export function useGuessWho() {
  const supabase = useSupabase()
  const state = ref<GuessWhoState | null>(null)
  const loading = ref(true)
  const submitting = ref(false)
  const photoUrl = ref('')
  const photoLoading = ref(false)
  const error = ref('')

  async function load() {
    loading.value = true
    error.value = ''
    try {
      const { data, error: err } = await supabase.rpc('guess_who_start_or_get')
      if (err) throw err
      if (data?.status === 'no_puzzle') {
        state.value = null
      } else {
        state.value = data as GuessWhoState
      }
    } catch (e: any) {
      error.value = e.message || 'Failed to load puzzle'
    } finally {
      loading.value = false
    }
  }

  async function submitGuess(firstName: string, lastName: string) {
    if (submitting.value) return
    submitting.value = true
    error.value = ''
    try {
      const { data, error: err } = await supabase.rpc('guess_who_submit', {
        p_first_name: firstName,
        p_last_name: lastName
      })
      if (err) throw err
      if (data?.error) {
        error.value = data.error
      } else {
        state.value = data as GuessWhoState
      }
    } catch (e: any) {
      error.value = e.message || 'Failed to submit guess'
    } finally {
      submitting.value = false
    }
  }

  async function usePhotoHint() {
    if (photoLoading.value) return
    photoLoading.value = true
    error.value = ''
    try {
      const { data, error: err } = await supabase.rpc('guess_who_use_photo_hint')
      if (err) throw err
      if (data?.error === 'no_photo') {
        error.value = data.message || 'No photo available'
      } else if (data?.error) {
        error.value = data.error
      } else {
        photoUrl.value = data.photo_url || ''
        if (state.value) state.value.used_photo_hint = true
      }
    } catch (e: any) {
      error.value = e.message || 'Failed to get photo hint'
    } finally {
      photoLoading.value = false
    }
  }

  const revealedClues = computed(() => {
    if (!state.value) return []
    const guessCount = state.value.guesses.length
    // Reveal clues progressively: first clue always shown, then one more per guess
    const count = Math.min(state.value.clues.length, guessCount + 1)
    return state.value.clues.slice(0, count)
  })

  const guessesRemaining = computed(() => {
    if (!state.value) return 0
    return state.value.max_guesses - state.value.guesses.length
  })

  return {
    state: readonly(state),
    loading: readonly(loading),
    submitting: readonly(submitting),
    photoUrl: readonly(photoUrl),
    photoLoading: readonly(photoLoading),
    error,
    revealedClues,
    guessesRemaining,
    load,
    submitGuess,
    usePhotoHint
  }
}
