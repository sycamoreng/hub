<script setup lang="ts">
import { useWordleMatch, type WordleMatchBoard, type WordleMatchPlayer } from '~/composables/useWordleMatch'
import { useSupabase } from '~/utils/supabase'

const props = defineProps<{ matchId: string }>()
const emit = defineEmits<{ (e: 'leave'): void }>()

const supabase = useSupabase()
const toast = useToast()
const { loadBoard, start, submitGuess, leave, joinByCode, subscribe, setRounds, nextRound } = useWordleMatch()

const board = ref<WordleMatchBoard | null>(null)
const me = ref<{ id: string } | null>(null)
const currentGuess = ref('')
const submitting = ref(false)
const advancing = ref(false)
const flashBanner = ref('')
const shakeRow = ref<number | null>(null)
const revealRow = ref<number | null>(null)
const countdown = ref<number | null>(null)
const roundsInput = ref(1)
let unsubscribe: (() => void) | null = null
let timerInterval: ReturnType<typeof setInterval> | null = null

const timerUrgent = computed(() => countdown.value !== null && countdown.value <= 10)
const timerWarning = computed(() => countdown.value !== null && countdown.value <= 30 && countdown.value > 10)

function formatTime(secs: number): string {
  const m = Math.floor(secs / 60)
  const s = secs % 60
  return m > 0 ? `${m}:${s.toString().padStart(2, '0')}` : `${s}s`
}

function startTimer() {
  stopTimer()
  if (!match.value?.deadline_at) return
  timerInterval = setInterval(() => {
    if (!match.value?.deadline_at) { stopTimer(); return }
    const remaining = Math.max(0, Math.ceil((new Date(match.value.deadline_at).getTime() - Date.now()) / 1000))
    countdown.value = remaining
    if (remaining <= 0) { stopTimer(); refresh() }
  }, 1000)
}

function stopTimer() {
  if (timerInterval) { clearInterval(timerInterval); timerInterval = null }
}

const isHost = computed(() => board.value && me.value && board.value.match.host_user_id === me.value.id)
const match = computed(() => board.value?.match ?? null)
const myPlayer = computed<WordleMatchPlayer | null>(() =>
  board.value?.players.find(p => p.user_id === me.value?.id) ?? null
)
const isSpectator = computed(() => isHost.value && !myPlayer.value)
const activePlayers = computed(() => (board.value?.players ?? []).filter(p => p.status !== 'left'))
const joinedCount = computed(() => activePlayers.value.length)

async function refresh() {
  try {
    board.value = await loadBoard(props.matchId)
    if (board.value?.match) {
      roundsInput.value = Math.max(1, board.value.match.total_rounds ?? 1)
    }
    if (board.value?.match?.status === 'active' && board.value.match.deadline_at && !timerInterval) {
      startTimer()
    }
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not load room')
  }
}

async function saveRounds() {
  if (!match.value) return
  try {
    await setRounds(match.value.id, roundsInput.value)
    toast.success(`Best of ${roundsInput.value}`)
    await refresh()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not update rounds')
  }
}

async function advanceRound() {
  if (!match.value || advancing.value) return
  advancing.value = true
  try {
    await nextRound(match.value.id)
    await refresh()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not start next round')
  } finally {
    advancing.value = false
  }
}

onMounted(async () => {
  const { data } = await supabase.auth.getUser()
  me.value = data.user ? { id: data.user.id } : null
  await refresh()
  unsubscribe = subscribe(props.matchId, refresh)
  window.addEventListener('keydown', handleKey)
})

onBeforeUnmount(() => {
  if (unsubscribe) unsubscribe()
  window.removeEventListener('keydown', handleKey)
  stopTimer()
})

async function copy(text: string, label: string) {
  try {
    await navigator.clipboard.writeText(text)
    toast.success(`${label} copied`)
  } catch {
    toast.error('Copy failed')
  }
}

async function hostJoinAsPlayer() {
  if (!match.value) return
  try {
    await joinByCode(match.value.code)
    await refresh()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not join')
  }
}

async function hostStart() {
  if (!match.value) return
  try {
    await start(match.value.id)
    await refresh()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not start')
  }
}

async function leaveRoom() {
  if (!match.value) { emit('leave'); return }
  try {
    if (match.value.status === 'pending') await leave(match.value.id)
  } finally {
    emit('leave')
  }
}

function padRight(s: string, len: number) {
  const arr = s.toUpperCase().split('').slice(0, len)
  while (arr.length < len) arr.push('')
  return arr
}

const myRows = computed(() => {
  if (!match.value || !myPlayer.value) return [] as Array<{ letters: string[]; results: string[]; active: boolean }>
  const out: Array<{ letters: string[]; results: string[]; active: boolean }> = []
  const { letter_count, max_guesses } = match.value
  const { guesses, results, completed } = myPlayer.value
  for (let i = 0; i < max_guesses; i++) {
    const g = guesses[i] ?? ''
    const r = results[i] ?? []
    const isCurrent = !completed && i === guesses.length
    const letters = isCurrent
      ? padRight(currentGuess.value, letter_count)
      : padRight(g, letter_count)
    out.push({ letters, results: r, active: isCurrent })
  }
  return out
})

const keyboardLayout = [
  ['q','w','e','r','t','y','u','i','o','p'],
  ['a','s','d','f','g','h','j','k','l'],
  ['ENTER','z','x','c','v','b','n','m','BACK']
]

const keyState = computed<Record<string, string>>(() => {
  const out: Record<string, string> = {}
  if (!myPlayer.value) return out
  const rank: Record<string, number> = { miss: 1, near: 2, hit: 3 }
  const guesses = myPlayer.value.guesses
  const results = myPlayer.value.results
  for (let i = 0; i < guesses.length; i++) {
    const g = guesses[i]
    const r = results[i]
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

function miniTileClass(status: string) {
  if (status === 'hit') return 'bg-emerald-500'
  if (status === 'near') return 'bg-amber-400'
  if (status === 'miss') return 'bg-slate-400'
  return 'bg-slate-200'
}

function keyClass(k: string) {
  const s = keyState.value[k]
  if (s === 'hit') return 'bg-emerald-500 text-white'
  if (s === 'near') return 'bg-amber-400 text-white'
  if (s === 'miss') return 'bg-slate-400 text-white'
  return 'bg-white text-slate-900 border border-slate-300 hover:bg-slate-100'
}

function canType() {
  return !!match.value && match.value.status === 'active' && !!myPlayer.value && myPlayer.value.status === 'joined' && !myPlayer.value.completed && !submitting.value
}

function pressLetter(ch: string) {
  if (!canType() || !match.value) return
  if (currentGuess.value.length >= match.value.letter_count) return
  currentGuess.value += ch.toLowerCase()
}

function backspace() {
  if (!canType()) return
  currentGuess.value = currentGuess.value.slice(0, -1)
}

async function submit() {
  if (!canType() || !match.value || !myPlayer.value) return
  const g = currentGuess.value.trim().toLowerCase()
  if (g.length !== match.value.letter_count) {
    toast.error(`Must be ${match.value.letter_count} letters`)
    triggerShake(myPlayer.value.guess_count)
    return
  }
  submitting.value = true
  const rowIdx = myPlayer.value.guess_count
  try {
    const res = await submitGuess(match.value.id, g)
    currentGuess.value = ''
    triggerReveal(rowIdx)
    await refresh()
    if (res.won) {
      setTimeout(() => {
        flashBanner.value = res.first_solver
          ? `First to solve! +${res.points_awarded} points`
          : `Solved! +${res.points_awarded} points`
        setTimeout(() => { flashBanner.value = '' }, 3000)
      }, 900)
    } else if (res.completed) {
      setTimeout(() => {
        flashBanner.value = `Out of guesses.${res.target ? ' Word was ' + res.target.toUpperCase() : ''}`
        setTimeout(() => { flashBanner.value = '' }, 3500)
      }, 900)
    }
  } catch (e: any) {
    triggerShake(rowIdx)
    const msg = (e?.message ?? '')
    if (msg.toLowerCase().includes('not a valid word')) toast.error('Not in word list. Try a real word.')
    else if (msg.includes('time expired')) { toast.error('Time is up!'); refresh() }
    else toast.error(msg || 'Invalid guess')
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
  const tag = (e.target as HTMLElement)?.tagName
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return
  if (!canType()) return
  if (e.key === 'Enter') { e.preventDefault(); submit() }
  else if (e.key === 'Backspace') { e.preventDefault(); backspace() }
  else if (/^[a-zA-Z]$/.test(e.key)) { e.preventDefault(); pressLetter(e.key) }
}

const standings = computed(() => {
  return [...activePlayers.value].sort((a, b) => {
    const seriesA = (a.series_points ?? 0) + (a.points_awarded ?? 0)
    const seriesB = (b.series_points ?? 0) + (b.points_awarded ?? 0)
    if (seriesA !== seriesB) return seriesB - seriesA
    if (a.won && !b.won) return -1
    if (b.won && !a.won) return 1
    if (a.won && b.won) return a.guess_count - b.guess_count
    if (a.completed && !b.completed) return 1
    if (b.completed && !a.completed) return -1
    return b.guess_count - a.guess_count
  })
})

const seriesComplete = computed(() =>
  !!match.value && match.value.status === 'finished' && (match.value.current_round ?? 1) >= (match.value.total_rounds ?? 1)
)
const hasMoreRounds = computed(() =>
  !!match.value && match.value.status === 'finished' && (match.value.current_round ?? 1) < (match.value.total_rounds ?? 1)
)

function statusBadge(p: WordleMatchPlayer): { label: string; cls: string } {
  if (p.won) return { label: 'Solved', cls: 'bg-emerald-100 text-emerald-800' }
  if (p.completed) return { label: 'Out', cls: 'bg-slate-200 text-slate-700' }
  if (match.value?.status === 'active') return { label: 'Playing', cls: 'bg-sky-100 text-sky-800' }
  return { label: 'Ready', cls: 'bg-slate-100 text-slate-700' }
}
</script>

<template>
  <section v-if="board && match" class="space-y-5">
    <header class="rounded-2xl border border-emerald-200 bg-gradient-to-br from-emerald-50 to-amber-50 p-5 sm:p-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div class="text-[11px] uppercase tracking-wider text-emerald-700 font-bold">Wordle Room</div>
          <h2 class="text-xl font-bold text-slate-900">Head-to-head Wordle</h2>
          <p class="text-sm text-slate-600">
            <span v-if="match.status === 'pending'">Waiting in the lobby. {{ joinedCount }} of {{ match.max_players }} joined.</span>
            <span v-else-if="match.status === 'active'">Race in progress. First to solve wins.</span>
            <span v-else-if="match.status === 'finished' && hasMoreRounds">Round {{ match.current_round }} of {{ match.total_rounds }} complete. Next round up!</span>
            <span v-else-if="match.status === 'finished'">Series complete.</span>
            <span v-else>Room cancelled.</span>
          </p>
          <div v-if="match.total_rounds > 1" class="mt-1 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-white/70 border border-emerald-200 text-[11px] font-bold text-emerald-800">
            Round {{ Math.min(match.current_round, match.total_rounds) }} of {{ match.total_rounds }}
          </div>
        </div>
        <div class="flex flex-col items-end gap-1">
          <div class="font-mono text-2xl font-bold tracking-widest text-slate-900">{{ match.code }}</div>
          <div class="flex gap-2">
            <button type="button" class="text-xs px-3 py-1 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-50" @click="copy(match.code, 'Code')">Copy code</button>
            <button type="button" class="text-xs px-3 py-1 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-50" @click="copy(`${$route.fullPath.split('?')[0]}?match=${match.code}`, 'Link')">Copy link</button>
          </div>
        </div>
      </div>
      <!-- Timer bar -->
      <div v-if="match.status === 'active' && countdown !== null" class="mt-4">
        <div class="flex items-center justify-between text-xs mb-1">
          <span class="font-semibold" :class="timerUrgent ? 'text-red-600' : timerWarning ? 'text-amber-600' : 'text-slate-600'">Time Remaining</span>
          <span class="font-mono font-bold text-lg" :class="timerUrgent ? 'text-red-600 animate-pulse' : timerWarning ? 'text-amber-600' : 'text-slate-900'">{{ formatTime(countdown) }}</span>
        </div>
        <div class="w-full h-2 rounded-full bg-slate-200 overflow-hidden">
          <div class="h-full rounded-full transition-all duration-1000 ease-linear"
            :class="timerUrgent ? 'bg-red-500' : timerWarning ? 'bg-amber-400' : 'bg-emerald-500'"
            :style="{ width: match.time_limit_seconds ? Math.max(0, (countdown / match.time_limit_seconds) * 100) + '%' : '100%' }"
          ></div>
        </div>
      </div>
    </header>

    <div v-if="flashBanner" class="fixed top-6 left-1/2 -translate-x-1/2 z-40 px-5 py-2.5 rounded-full bg-slate-900 text-white text-sm font-semibold shadow-lg">
      {{ flashBanner }}
    </div>

    <div v-if="match.status === 'pending'" class="grid lg:grid-cols-2 gap-4">
      <article class="rounded-2xl border border-slate-200 bg-white p-5">
        <h3 class="text-sm font-bold text-slate-900 mb-3">Players ({{ joinedCount }} / {{ match.max_players }})</h3>
        <ul class="space-y-2">
          <li v-for="p in activePlayers" :key="p.user_id" class="flex items-center justify-between text-sm">
            <span class="truncate font-medium text-slate-800">
              {{ p.full_name ?? 'Team member' }}
              <span v-if="p.user_id === match.host_user_id" class="text-[11px] uppercase text-emerald-700 font-bold ml-1">Host</span>
            </span>
            <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold bg-slate-100 text-slate-700">Ready</span>
          </li>
        </ul>
      </article>

      <article class="rounded-2xl border border-slate-200 bg-white p-5">
        <h3 class="text-sm font-bold text-slate-900 mb-2">How this works</h3>
        <ul class="text-sm text-slate-600 space-y-1.5 list-disc list-inside">
          <li>Everyone races the same hidden word (not the daily one).</li>
          <li>Up to {{ match.max_players }} players per room.</li>
          <li>{{ match.letter_count }} letters, {{ match.max_guesses }} guesses each.</li>
          <li>First to solve gets the biggest points bonus.</li>
          <li v-if="match.time_limit_seconds" class="text-amber-700 font-medium">Timed: {{ match.time_limit_seconds }}s to solve. Fast solvers get bonus points!</li>
          <li v-else class="text-slate-400">No time limit.</li>
          <li v-if="match.total_rounds > 1" class="text-sky-700 font-medium">Best of {{ match.total_rounds }} rounds. Series podium at the end.</li>
        </ul>
        <div v-if="isHost" class="mt-4 flex flex-wrap items-center gap-2 border-t border-slate-100 pt-3">
          <label class="text-xs font-bold text-slate-700">Rounds</label>
          <select v-model.number="roundsInput" class="text-xs px-2 py-1 rounded border border-slate-300 bg-white">
            <option v-for="n in [1,2,3,5,7,10]" :key="n" :value="n">Best of {{ n }}</option>
          </select>
          <button type="button" class="text-xs px-3 py-1.5 rounded-full bg-slate-900 text-white hover:bg-slate-800" @click="saveRounds">Save</button>
          <span class="text-[11px] text-slate-500">Auto-continues to the next round when a round finishes.</span>
        </div>
        <p class="text-xs text-slate-500 mt-3">Share the code <span class="font-mono font-bold">{{ match.code }}</span> or the room link with teammates.</p>
      </article>

      <article class="rounded-2xl border border-slate-200 bg-white p-5 lg:col-span-2 flex flex-wrap items-center justify-between gap-3">
        <div class="text-sm text-slate-700">
          <span v-if="isHost && isSpectator">You're hosting but not playing. Join if you want to play too!</span>
          <span v-else-if="isHost">Click Start when everyone has joined.</span>
          <span v-else>Waiting for the host to start.</span>
        </div>
        <div class="flex gap-2">
          <button v-if="!isSpectator" type="button" class="text-sm px-4 py-2 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-50" @click="leaveRoom">Leave</button>
          <button v-if="isHost && isSpectator" type="button" class="text-sm px-4 py-2 rounded-full bg-blue-600 text-white font-semibold hover:bg-blue-700" @click="hostJoinAsPlayer">Join as player</button>
          <button v-if="isHost" type="button" class="text-sm px-4 py-2 rounded-full bg-emerald-600 text-white font-semibold hover:bg-emerald-700 disabled:opacity-40" :disabled="joinedCount < 1" @click="hostStart">Start race</button>
        </div>
      </article>
    </div>

    <div v-else class="grid lg:grid-cols-[1fr_320px] gap-5 items-start">
      <div class="space-y-5">
        <div v-if="myRows.length" class="flex flex-col items-center gap-1.5">
          <div
            v-for="(row, rIdx) in myRows"
            :key="rIdx"
            class="flex gap-1.5"
            :class="shakeRow === rIdx ? 'animate-[wshake_0.4s_ease]' : ''"
          >
            <div
              v-for="(ch, i) in row.letters"
              :key="i"
              class="w-12 h-12 sm:w-14 sm:h-14 border-2 rounded-lg flex items-center justify-center text-xl sm:text-2xl font-bold uppercase transition-all duration-300"
              :class="[tileClass(row.results[i] ?? '', Boolean(ch), row.active), revealRow === rIdx ? `animate-[wflip_0.6s_ease_${i * 0.12}s_both]` : '']"
            >
              {{ ch }}
            </div>
          </div>
        </div>

        <div v-if="match.status === 'active' && isSpectator" class="rounded-2xl border border-slate-200 bg-white p-5 text-center">
          <div class="text-slate-600 font-medium">You're watching as host. Players are racing below.</div>
        </div>

        <div v-if="match.status === 'active' && myPlayer && !myPlayer.completed" class="space-y-2">
          <div v-for="(row, rIdx) in keyboardLayout" :key="rIdx" class="flex justify-center gap-1.5">
            <button
              v-for="k in row"
              :key="k"
              type="button"
              @click="k === 'ENTER' ? submit() : k === 'BACK' ? backspace() : pressLetter(k)"
              class="h-11 sm:h-12 rounded-lg font-semibold text-sm sm:text-base transition-all active:scale-95"
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

        <div v-if="match.status === 'finished'" class="space-y-5">
          <div class="rounded-2xl border border-amber-200 bg-gradient-to-br from-amber-50 to-slate-50 p-6 text-center space-y-3">
            <div v-if="!match.winner_user_id && match.time_limit_seconds" class="text-red-600 font-bold text-sm uppercase tracking-wide">Time's Up!</div>
            <div v-if="match.target" class="text-slate-800">
              The word was <span class="inline-block px-3 py-1 rounded-lg bg-emerald-100 text-emerald-800 font-bold uppercase text-lg tracking-widest">{{ match.target }}</span>
            </div>
            <div v-if="myPlayer && myPlayer.won" class="text-emerald-700 font-semibold">
              You solved it in {{ myPlayer.guess_count }} guess{{ myPlayer.guess_count === 1 ? '' : 'es' }}.
              <span v-if="myPlayer.points_awarded" class="text-sky-700">+{{ myPlayer.points_awarded }} pts</span>
            </div>
            <div v-else-if="myPlayer && !myPlayer.won" class="text-slate-600 text-sm">Better luck next time!</div>
          </div>

          <!-- Podium -->
          <div v-if="standings.length >= 1" class="rounded-2xl border border-slate-200 bg-white p-6">
            <h3 class="text-sm font-bold text-slate-900 text-center mb-1">{{ seriesComplete && match.total_rounds > 1 ? 'Series Podium' : (match.total_rounds > 1 ? 'Round ' + match.current_round + ' Podium' : 'Podium') }}</h3>
            <p v-if="match.total_rounds > 1" class="text-[11px] text-slate-500 text-center mb-4">Series score = total points across all rounds</p>
            <div v-else class="mb-4"></div>
            <div class="flex items-end justify-center gap-3 max-w-sm mx-auto">
              <div v-if="standings[1]" class="flex flex-col items-center flex-1">
                <div class="w-10 h-10 rounded-full bg-slate-200 flex items-center justify-center text-sm font-bold text-slate-700 mb-2">{{ standings[1].full_name?.charAt(0) ?? '?' }}</div>
                <p class="text-[11px] font-semibold text-slate-700 text-center truncate max-w-[80px]">{{ standings[1].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-slate-500">{{ (standings[1].series_points ?? 0) + (standings[1].points_awarded ?? 0) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-slate-200 flex items-end justify-center" style="height: 60px;"><span class="text-lg font-bold text-slate-600 mb-2">2</span></div>
              </div>
              <div v-if="standings[0]" class="flex flex-col items-center flex-1">
                <div class="w-12 h-12 rounded-full bg-amber-100 border-2 border-amber-300 flex items-center justify-center text-base font-bold text-amber-700 mb-2">{{ standings[0].full_name?.charAt(0) ?? '?' }}</div>
                <p class="text-xs font-bold text-slate-900 text-center truncate max-w-[80px]">{{ standings[0].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-amber-700 font-semibold">{{ (standings[0].series_points ?? 0) + (standings[0].points_awarded ?? 0) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-amber-100 border-2 border-amber-200 flex items-end justify-center" style="height: 90px;"><span class="text-2xl mb-2">&#x1F3C6;</span></div>
              </div>
              <div v-if="standings[2]" class="flex flex-col items-center flex-1">
                <div class="w-10 h-10 rounded-full bg-orange-100 flex items-center justify-center text-sm font-bold text-orange-700 mb-2">{{ standings[2].full_name?.charAt(0) ?? '?' }}</div>
                <p class="text-[11px] font-semibold text-slate-700 text-center truncate max-w-[80px]">{{ standings[2].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-slate-500">{{ (standings[2].series_points ?? 0) + (standings[2].points_awarded ?? 0) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-orange-100 flex items-end justify-center" style="height: 40px;"><span class="text-lg font-bold text-orange-600 mb-2">3</span></div>
              </div>
            </div>
            <ol v-if="standings.length > 3" class="mt-5 space-y-1.5 border-t border-slate-100 pt-4">
              <li v-for="(p, i) in standings.slice(3)" :key="p.user_id" class="flex items-center gap-3 text-xs px-3 py-1.5 rounded-lg" :class="p.user_id === me?.id ? 'bg-amber-50 border border-amber-200' : 'bg-slate-50'">
                <span class="w-5 h-5 rounded-full bg-slate-100 flex items-center justify-center text-[10px] font-bold text-slate-500">{{ i + 4 }}</span>
                <span class="flex-1 truncate font-medium text-slate-800">{{ p.full_name ?? 'Team member' }}</span>
                <span class="text-slate-500">{{ (p.series_points ?? 0) + (p.points_awarded ?? 0) }} pts</span>
              </li>
            </ol>
          </div>

          <div v-if="hasMoreRounds" class="rounded-2xl border border-sky-200 bg-sky-50 p-5 flex flex-wrap items-center justify-between gap-3">
            <div class="text-sm text-sky-900">
              <strong>Round {{ match.current_round }} of {{ match.total_rounds }} finished.</strong>
              <span class="text-sky-800"> {{ isHost ? 'Start the next round when everyone is ready.' : 'Waiting for the host to start the next round.' }}</span>
            </div>
            <button v-if="isHost" type="button" :disabled="advancing" class="text-sm px-4 py-2 rounded-full bg-sky-600 text-white font-semibold hover:bg-sky-700 disabled:opacity-40" @click="advanceRound">
              {{ advancing ? 'Starting...' : 'Start next round' }}
            </button>
          </div>
        </div>

        <div v-if="myPlayer && myPlayer.completed && match.status === 'active'" class="rounded-2xl border border-slate-200 bg-white p-5 text-center">
          <div v-if="myPlayer.won" class="text-emerald-700 font-semibold">You solved it! Waiting for others to finish.</div>
          <div v-else class="text-slate-700 font-semibold">Out of guesses. Waiting for others to finish.</div>
        </div>
      </div>

      <aside class="rounded-2xl border border-slate-200 bg-white p-4 space-y-3 lg:sticky lg:top-4">
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-bold text-slate-900">Live board</h3>
          <span class="text-[10px] uppercase tracking-wide text-slate-500">{{ standings.length }} players</span>
        </div>
        <ol class="space-y-3">
          <li v-for="(p, i) in standings" :key="p.user_id" class="space-y-1.5">
            <div class="flex items-center justify-between text-xs">
              <div class="flex items-center gap-2 min-w-0">
                <span class="w-4 text-right font-bold text-slate-400 tabular-nums">{{ i + 1 }}</span>
                <span class="truncate font-semibold text-slate-800">
                  {{ p.full_name ?? 'Team member' }}
                  <span v-if="p.user_id === me?.id" class="text-[10px] uppercase text-emerald-700 font-bold ml-1">You</span>
                </span>
              </div>
              <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold" :class="statusBadge(p).cls">{{ statusBadge(p).label }}</span>
            </div>
            <div class="flex flex-col gap-0.5">
              <div v-for="(row, rIdx) in p.results" :key="rIdx" class="flex gap-0.5">
                <div
                  v-for="(status, ci) in row"
                  :key="ci"
                  class="w-3 h-3 rounded-sm"
                  :class="miniTileClass(status)"
                ></div>
              </div>
              <div v-if="p.results.length === 0" class="text-[10px] text-slate-400">No guesses yet</div>
            </div>
          </li>
        </ol>
        <button type="button" class="w-full text-xs px-3 py-2 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-50" @click="leaveRoom">
          {{ match.status === 'finished' ? 'Leave room' : 'Give up and leave' }}
        </button>
      </aside>
    </div>
  </section>
</template>

<style scoped>
@keyframes wshake {
  0%, 100% { transform: translateX(0); }
  20% { transform: translateX(-6px); }
  40% { transform: translateX(6px); }
  60% { transform: translateX(-4px); }
  80% { transform: translateX(4px); }
}
@keyframes wflip {
  0% { transform: rotateX(0); }
  45% { transform: rotateX(90deg); }
  100% { transform: rotateX(0); }
}
</style>
