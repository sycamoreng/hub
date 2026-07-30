<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { useWordleMatch } from '~/composables/useWordleMatch'

const supabase = useSupabase()
const toast = useToast()
const route = useRoute()
const router = useRouter()
const { createMatch, joinByCode, lookupByCode } = useWordleMatch()

interface GameState {
  puzzle_date: string
  letter_count: number
  max_guesses: number
  guesses: string[]
  results: string[][]
  completed: boolean
  won: boolean
  target: string | null
  points_awarded?: number
}

const state = ref<GameState | null>(null)
const currentGuess = ref('')
const submitting = ref(false)
const loading = ref(true)
const shakeRow = ref<number | null>(null)
const revealRow = ref<number | null>(null)
const flashBanner = ref<string>('')

const activeMatchId = ref<string>('')
const joinCode = ref('')
const creatingMatch = ref(false)
const joiningMatch = ref(false)
const selectedTimeLimit = ref<number | null>(90)

async function hostMatch() {
  creatingMatch.value = true
  try {
    const m = await createMatch({ maxPlayers: 30, timeLimit: selectedTimeLimit.value })
    activeMatchId.value = m.id
    await router.replace({ query: { ...route.query, match: m.code } })
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not create room')
  } finally {
    creatingMatch.value = false
  }
}

async function joinRoomByCode() {
  const code = joinCode.value.trim().toUpperCase()
  if (!code) return
  joiningMatch.value = true
  try {
    const m = await joinByCode(code)
    activeMatchId.value = m.id
    joinCode.value = ''
    await router.replace({ query: { ...route.query, match: m.code } })
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not join')
  } finally {
    joiningMatch.value = false
  }
}

async function leaveMatch() {
  activeMatchId.value = ''
  const q = { ...route.query }
  delete q.match
  await router.replace({ query: q })
}

async function tryEnterFromQuery() {
  const code = (route.query.match as string | undefined)?.toUpperCase()
  if (!code) return
  try {
    const m = await lookupByCode(code)
    if (!m) return
    if (m.status === 'pending') {
      const joined = await joinByCode(code)
      activeMatchId.value = joined.id
    } else {
      activeMatchId.value = m.id
    }
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not open room')
  }
}

async function startOrGet() {
  loading.value = true
  try {
    const { data, error } = await supabase.rpc('wordle_start_or_get')
    if (error) throw error
    state.value = data as GameState
  } catch (e: any) {
    toast.error(e.message ?? 'Could not start game')
  } finally {
    loading.value = false
  }
}
onMounted(async () => {
  await startOrGet()
  await tryEnterFromQuery()
})

const rows = computed(() => {
  if (!state.value) return [] as Array<{ letters: string[]; results: string[]; active: boolean }>
  const out: Array<{ letters: string[]; results: string[]; active: boolean }> = []
  const { letter_count, max_guesses, guesses, results, completed } = state.value
  for (let i = 0; i < max_guesses; i++) {
    const g = guesses[i] ?? ''
    const r = (results[i] as string[]) ?? []
    const isCurrent = !completed && i === guesses.length
    const letters = isCurrent
      ? padRight(currentGuess.value, letter_count)
      : padRight(g, letter_count)
    out.push({ letters, results: r, active: isCurrent })
  }
  return out
})

function padRight(s: string, len: number) {
  const arr = s.toUpperCase().split('').slice(0, len)
  while (arr.length < len) arr.push('')
  return arr
}

const keyboardLayout = [
  ['q','w','e','r','t','y','u','i','o','p'],
  ['a','s','d','f','g','h','j','k','l'],
  ['ENTER','z','x','c','v','b','n','m','BACK']
]

const keyState = computed<Record<string, string>>(() => {
  const out: Record<string, string> = {}
  if (!state.value) return out
  const rank: Record<string, number> = { miss: 1, near: 2, hit: 3 }
  for (let i = 0; i < state.value.guesses.length; i++) {
    const g = state.value.guesses[i]
    const r = state.value.results[i]
    if (!g || !r) continue
    for (let j = 0; j < g.length; j++) {
      const ch = g[j]
      const cur = out[ch]
      const next = r[j]
      if (!cur || (rank[next] ?? 0) > (rank[cur] ?? 0)) out[ch] = next
    }
  }
  return out
})

function tileClass(status: string, filled: boolean, active: boolean) {
  if (status === 'hit') return 'bg-emerald-500 border-emerald-500 text-white'
  if (status === 'near') return 'bg-amber-400 border-amber-400 text-white'
  if (status === 'miss') return 'bg-slate-400 border-slate-400 text-white'
  if (filled) return 'bg-white border-slate-400 text-slate-900 scale-[1.03]'
  if (active) return 'bg-white border-slate-200 text-slate-900'
  return 'bg-slate-50 border-slate-200 text-slate-900'
}

function keyClass(k: string) {
  const s = keyState.value[k]
  if (s === 'hit') return 'bg-emerald-500 text-white'
  if (s === 'near') return 'bg-amber-400 text-white'
  if (s === 'miss') return 'bg-slate-400 text-white'
  return 'bg-white text-slate-900 border border-slate-300 hover:bg-slate-100'
}

function pressLetter(ch: string) {
  if (!state.value || state.value.completed || submitting.value) return
  if (currentGuess.value.length >= state.value.letter_count) return
  currentGuess.value += ch.toLowerCase()
}

function backspace() {
  if (!state.value || state.value.completed || submitting.value) return
  currentGuess.value = currentGuess.value.slice(0, -1)
}

async function submit() {
  if (!state.value || state.value.completed || submitting.value) return
  const g = currentGuess.value.trim().toLowerCase()
  if (g.length !== state.value.letter_count) {
    toast.error(`Must be ${state.value.letter_count} letters`)
    triggerShake(state.value.guesses.length)
    return
  }
  submitting.value = true
  const rowIdx = state.value.guesses.length
  try {
    const { data, error } = await supabase.rpc('wordle_submit_guess', { p_guess: g })
    if (error) throw error
    const next = data as GameState
    state.value = next
    currentGuess.value = ''
    triggerReveal(rowIdx)
    await nextTick()
    if (next.won) {
      setTimeout(() => {
        flashBanner.value = `Nice! +${next.points_awarded} points`
        setTimeout(() => { flashBanner.value = '' }, 3000)
      }, 900)
    } else if (next.completed) {
      setTimeout(() => {
        flashBanner.value = `The word was ${next.target?.toUpperCase()}`
        setTimeout(() => { flashBanner.value = '' }, 3500)
      }, 900)
    }
  } catch (e: any) {
    triggerShake(rowIdx)
    const msg = (e.message ?? '').toLowerCase()
    if (msg.includes('not a valid word')) toast.error('Not in word list. Try a real word.')
    else toast.error(e.message ?? 'Invalid guess')
  } finally {
    submitting.value = false
  }
}

function triggerShake(idx: number) {
  shakeRow.value = idx
  setTimeout(() => { if (shakeRow.value === idx) shakeRow.value = null }, 450)
}
function triggerReveal(idx: number) {
  revealRow.value = idx
  setTimeout(() => { if (revealRow.value === idx) revealRow.value = null }, 1200)
}

function handleKey(e: KeyboardEvent) {
  if (activeMatchId.value) return
  const tag = (e.target as HTMLElement)?.tagName
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return
  if (!state.value || state.value.completed || submitting.value) return
  if (e.key === 'Enter') { e.preventDefault(); submit() }
  else if (e.key === 'Backspace') { e.preventDefault(); backspace() }
  else if (/^[a-zA-Z]$/.test(e.key)) { e.preventDefault(); pressLetter(e.key) }
}

onMounted(() => { window.addEventListener('keydown', handleKey) })
onBeforeUnmount(() => { window.removeEventListener('keydown', handleKey) })

function shareSummary() {
  if (!state.value || !state.value.completed) return
  const lines = state.value.results.map(r => r.map(s => s === 'hit' ? '\uD83D\uDFE9' : s === 'near' ? '\uD83D\uDFE8' : '\u2B1B').join('')).join('\n')
  const header = `Sycamore Wordle \u2014 ${state.value.puzzle_date}\n${state.value.won ? state.value.guesses.length : 'X'}/${state.value.max_guesses}`
  const text = `${header}\n\n${lines}`
  navigator.clipboard.writeText(text).then(() => toast.success('Copied result to clipboard'))
}
</script>

<template>
  <div :class="[activeMatchId ? 'max-w-4xl' : 'max-w-xl', 'mx-auto pb-8']">
    <header class="text-center mb-6">
      <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-50 border border-emerald-200 text-[11px] font-semibold uppercase tracking-[0.2em] text-emerald-700">
        <span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>
        {{ activeMatchId ? 'Room Match' : 'Daily Word' }}
      </div>
      <h1 class="mt-3 text-2xl sm:text-4xl font-bold text-slate-900 tracking-tight">Sycamore Wordle</h1>
      <p class="mt-1 text-xs sm:text-sm text-slate-500">
        <span v-if="activeMatchId">Race up to five teammates on a fresh word.</span>
        <span v-else>One puzzle a day. Fewer guesses, more points.</span>
      </p>
    </header>

    <WordleMatchRoom v-if="activeMatchId" :match-id="activeMatchId" @leave="leaveMatch" />

    <template v-else>
    <section class="mb-5 rounded-2xl border border-slate-200 bg-white p-4 sm:p-5 space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="text-sm font-bold text-slate-900">Race a teammate</h2>
          <p class="text-xs text-slate-500">Host a room with a fresh word (up to 30 players), or join with a code.</p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <input v-model="joinCode" placeholder="Code" maxlength="8" class="w-28 px-3 py-2 rounded-lg border border-slate-300 uppercase tracking-widest font-mono text-sm focus:outline-none focus:ring-2 focus:ring-emerald-500" />
          <button type="button" class="text-sm px-4 py-2 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-50 disabled:opacity-40" :disabled="joiningMatch || !joinCode.trim()" @click="joinRoomByCode">
            {{ joiningMatch ? 'Joining...' : 'Join room' }}
          </button>
          <button type="button" class="text-sm px-4 py-2 rounded-full bg-emerald-600 text-white font-semibold hover:bg-emerald-700 disabled:opacity-40" :disabled="creatingMatch" @click="hostMatch">
            {{ creatingMatch ? 'Creating...' : 'Host new room' }}
          </button>
        </div>
      </div>
      <div class="flex flex-wrap items-center gap-2 pt-2 border-t border-slate-100">
        <span class="text-xs font-semibold text-slate-500">Timer:</span>
        <button
          v-for="opt in [{ label: 'None', value: null }, { label: '30s', value: 30 }, { label: '60s', value: 60 }, { label: '90s', value: 90 }, { label: '3m', value: 180 }]"
          :key="String(opt.value)"
          type="button"
          class="px-2.5 py-1 text-xs font-semibold rounded-lg border transition-all"
          :class="selectedTimeLimit === opt.value ? 'bg-emerald-600 text-white border-emerald-600' : 'bg-white text-slate-600 border-slate-200 hover:border-emerald-300'"
          @click="selectedTimeLimit = opt.value"
        >{{ opt.label }}</button>
        <span class="text-[11px] text-slate-400 ml-1">
          <span v-if="selectedTimeLimit">Solve fast for bonus points!</span>
          <span v-else>No time pressure.</span>
        </span>
      </div>
    </section>

    <div v-if="loading" class="text-center text-sm text-slate-400 py-10">Loading your puzzle...</div>

    <div v-else-if="state" class="space-y-5">
      <div v-if="flashBanner" class="fixed top-6 left-1/2 -translate-x-1/2 z-40 px-5 py-2.5 rounded-full bg-slate-900 text-white text-sm font-semibold shadow-lg animate-[fade_0.4s_ease-out]">
        {{ flashBanner }}
      </div>

      <div class="flex flex-col items-center gap-1.5">
        <div
          v-for="(row, rIdx) in rows"
          :key="rIdx"
          class="flex gap-1.5"
          :class="shakeRow === rIdx ? 'animate-[shake_0.4s_ease]' : ''"
        >
          <div
            v-for="(ch, i) in row.letters"
            :key="i"
            class="w-14 h-14 sm:w-16 sm:h-16 border-2 rounded-lg flex items-center justify-center text-2xl sm:text-3xl font-bold uppercase transition-all duration-300"
            :class="[tileClass(row.results[i] ?? '', Boolean(ch), row.active), revealRow === rIdx ? `animate-[flip_0.6s_ease_${i * 0.12}s_both]` : '']"
          >
            {{ ch }}
          </div>
        </div>
      </div>

      <div v-if="state.completed" class="bg-white border border-slate-200 rounded-2xl p-5 text-center space-y-3">
        <div v-if="state.won" class="text-emerald-700 font-semibold">You solved it in {{ state.guesses.length }} guess{{ state.guesses.length === 1 ? '' : 'es' }}!</div>
        <div v-else class="text-slate-700 font-semibold">Tomorrow's a new day. The word was <span class="tabular-nums uppercase font-bold">{{ state.target }}</span>.</div>
        <button type="button" @click="shareSummary" class="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800">
          Share result
        </button>
        <div class="text-xs text-slate-400">Come back tomorrow for a fresh puzzle.</div>
      </div>

      <div v-else class="space-y-2">
        <div v-for="(row, rIdx) in keyboardLayout" :key="rIdx" class="flex justify-center gap-1.5">
          <button
            v-for="k in row"
            :key="k"
            type="button"
            @click="k === 'ENTER' ? submit() : k === 'BACK' ? backspace() : pressLetter(k)"
            class="h-12 sm:h-14 rounded-lg font-semibold text-sm sm:text-base transition-all active:scale-95"
            :class="[
              k === 'ENTER' || k === 'BACK' ? 'px-3 sm:px-4 text-xs' : 'w-8 sm:w-9 uppercase',
              k === 'ENTER' || k === 'BACK' ? 'bg-slate-900 text-white hover:bg-slate-800' : keyClass(k)
            ]"
          >
            <span v-if="k === 'BACK'">&larr;</span>
            <span v-else>{{ k }}</span>
          </button>
        </div>
      </div>

      <p class="text-center text-xs text-slate-400">
        Green = right letter, right spot. Amber = right letter, wrong spot.
      </p>
    </div>
    </template>
  </div>
</template>

<style scoped>
@keyframes shake {
  0%, 100% { transform: translateX(0); }
  20% { transform: translateX(-6px); }
  40% { transform: translateX(6px); }
  60% { transform: translateX(-4px); }
  80% { transform: translateX(4px); }
}
@keyframes flip {
  0% { transform: rotateX(0); }
  45% { transform: rotateX(90deg); }
  100% { transform: rotateX(0); }
}
@keyframes fade {
  from { opacity: 0; transform: translate(-50%, -8px); }
  to { opacity: 1; transform: translate(-50%, 0); }
}
</style>
