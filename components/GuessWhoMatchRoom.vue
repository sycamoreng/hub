<script setup lang="ts">
import { useGuessWhoMatch, type GuessWhoMatchBoard, type GuessWhoMatchPlayer } from '~/composables/useGuessWhoMatch'
import { type ClueItem } from '~/composables/useGuessWho'
import { useSupabase } from '~/utils/supabase'

const props = defineProps<{ matchId: string }>()
const emit = defineEmits<{ (e: 'leave'): void }>()

const supabase = useSupabase()
const toast = useToast()
const { loadBoard, start, submitGuess, leave, joinByCode, subscribe, setRounds, nextRound } = useGuessWhoMatch()

const board = ref<GuessWhoMatchBoard | null>(null)
const me = ref<{ id: string } | null>(null)
const firstName = ref('')
const lastName = ref('')
const submitting = ref(false)
const advancing = ref(false)
const countdown = ref<number | null>(null)
const roundsInput = ref(1)
let unsubscribe: (() => void) | null = null
let timerInterval: ReturnType<typeof setInterval> | null = null

const isHost = computed(() => board.value && me.value && board.value.match.host_user_id === me.value.id)
const match = computed(() => board.value?.match ?? null)
const myPlayer = computed<GuessWhoMatchPlayer | null>(() =>
  board.value?.players.find(p => p.user_id === me.value?.id) ?? null
)
const isSpectator = computed(() => isHost.value && !myPlayer.value)
const activePlayers = computed(() => (board.value?.players ?? []).filter(p => p.status !== 'left'))
const joinedCount = computed(() => activePlayers.value.length)

const visibleClues = computed<ClueItem[]>(() => {
  if (!board.value) return []
  return board.value.clues.map(c => parseClue(c))
})

const totalClues = computed(() => match.value?.total_clues ?? 0)

const timerUrgent = computed(() => countdown.value !== null && countdown.value <= 10)
const timerWarning = computed(() => countdown.value !== null && countdown.value <= 30 && countdown.value > 10)

function parseClue(c: string | ClueItem): ClueItem {
  if (typeof c === 'object' && c !== null && 'text' in c) return c as ClueItem
  if (typeof c === 'string') {
    try {
      const parsed = JSON.parse(c)
      if (parsed && parsed.text) return parsed as ClueItem
    } catch {}
    return { category: 'vibe', text: c }
  }
  return { category: 'vibe', text: String(c) }
}

function clueCategoryColor(cat: string): string {
  const colors: Record<string, string> = {
    identity: 'bg-fuchsia-100 text-fuchsia-700',
    vibe: 'bg-purple-100 text-purple-700',
    location: 'bg-blue-100 text-blue-700',
    team: 'bg-amber-100 text-amber-700',
    role: 'bg-emerald-100 text-emerald-700',
    tenure: 'bg-pink-100 text-pink-700',
    connections: 'bg-cyan-100 text-cyan-700',
    fun_fact: 'bg-orange-100 text-orange-700',
    photo: 'bg-rose-100 text-rose-700',
  }
  return colors[cat] || 'bg-slate-100 text-slate-600'
}

function clueCategoryTextColor(cat: string): string {
  const colors: Record<string, string> = {
    identity: 'text-fuchsia-600',
    vibe: 'text-purple-600',
    location: 'text-blue-600',
    team: 'text-amber-600',
    role: 'text-emerald-600',
    tenure: 'text-pink-600',
    connections: 'text-cyan-600',
    fun_fact: 'text-orange-600',
    photo: 'text-rose-600',
  }
  return colors[cat] || 'text-slate-500'
}

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
    if (remaining <= 0) {
      stopTimer()
      refresh()
    }
  }, 1000)
}

function stopTimer() {
  if (timerInterval) { clearInterval(timerInterval); timerInterval = null }
}

async function refresh() {
  try {
    board.value = await loadBoard(props.matchId)
    if (board.value?.match) {
      roundsInput.value = Math.max(1, board.value.match.total_rounds ?? 1)
    }
    if (board.value?.match?.status === 'active' && board.value.match.deadline_at) {
      if (!timerInterval) startTimer()
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
    firstName.value = ''
    lastName.value = ''
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
})

onBeforeUnmount(() => {
  if (unsubscribe) unsubscribe()
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

async function handleGuess() {
  if (!match.value || !firstName.value.trim() || !lastName.value.trim()) return
  submitting.value = true
  try {
    const updatedBoard = await submitGuess(match.value.id, firstName.value.trim(), lastName.value.trim())
    firstName.value = ''
    lastName.value = ''
    board.value = updatedBoard
    const updatedMe = updatedBoard.players.find(p => p.user_id === me.value?.id)
    if (updatedMe?.won) {
      toast.success(`Correct! +${updatedMe.points_awarded} points`)
    } else if (updatedMe?.completed) {
      toast.error('Out of guesses!')
    }
  } catch (e: any) {
    const msg = e?.message ?? ''
    if (msg.includes('time expired')) {
      toast.error('Time is up!')
      await refresh()
    } else {
      toast.error(msg || 'Failed to submit guess')
    }
  } finally {
    submitting.value = false
  }
}

const guessesRemaining = computed(() => {
  if (!match.value || !myPlayer.value) return 0
  return match.value.max_guesses - myPlayer.value.guess_count
})

const standings = computed(() => {
  return [...activePlayers.value].sort((a, b) => {
    const sa = (a.series_points ?? 0) + (a.points_awarded ?? 0)
    const sb = (b.series_points ?? 0) + (b.points_awarded ?? 0)
    if (sa !== sb) return sb - sa
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

function statusBadge(p: GuessWhoMatchPlayer): { label: string; cls: string } {
  if (p.won) return { label: `Solved (${p.guess_count})`, cls: 'bg-emerald-100 text-emerald-800' }
  if (p.completed) return { label: 'Out', cls: 'bg-slate-200 text-slate-700' }
  if (match.value?.status === 'active') return { label: `${p.guess_count} guesses`, cls: 'bg-sky-100 text-sky-800' }
  return { label: 'Ready', cls: 'bg-slate-100 text-slate-700' }
}

const solvedCount = computed(() => activePlayers.value.filter(p => p.won).length)
const remainingCount = computed(() => activePlayers.value.filter(p => !p.completed).length)
</script>

<template>
  <section v-if="board && match" class="space-y-5">
    <!-- Room header -->
    <header class="rounded-2xl border border-purple-200 bg-gradient-to-br from-purple-50 to-amber-50 p-5 sm:p-6">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div class="text-[11px] uppercase tracking-wider text-purple-700 font-bold">Guess Who Room</div>
          <h2 class="text-xl font-bold text-slate-900">Multiplayer Guess Who</h2>
          <p class="text-sm text-slate-600">
            <span v-if="match.status === 'pending'">Lobby open. {{ joinedCount }} of {{ match.max_players }} joined.</span>
            <span v-else-if="match.status === 'active'">
              Race in progress!
              <span v-if="solvedCount > 0" class="text-emerald-600 font-semibold ml-1">{{ solvedCount }} solved</span>
              <span v-if="remainingCount > 0" class="text-slate-400 ml-1">/ {{ remainingCount }} still guessing</span>
            </span>
            <span v-else-if="match.status === 'finished' && hasMoreRounds">Round {{ match.current_round }} of {{ match.total_rounds }} complete. Next round up!</span>
            <span v-else-if="match.status === 'finished'">Game complete.</span>
            <span v-else>Room cancelled.</span>
          </p>
          <div v-if="match.total_rounds > 1" class="mt-1 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-white/70 border border-purple-200 text-[11px] font-bold text-purple-800">
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
          <span class="font-semibold" :class="timerUrgent ? 'text-red-600' : timerWarning ? 'text-amber-600' : 'text-slate-600'">
            Time Remaining
          </span>
          <span class="font-mono font-bold text-lg" :class="timerUrgent ? 'text-red-600 animate-pulse' : timerWarning ? 'text-amber-600' : 'text-slate-900'">
            {{ formatTime(countdown) }}
          </span>
        </div>
        <div class="w-full h-2 rounded-full bg-slate-200 overflow-hidden">
          <div
            class="h-full rounded-full transition-all duration-1000 ease-linear"
            :class="timerUrgent ? 'bg-red-500' : timerWarning ? 'bg-amber-400' : 'bg-purple-500'"
            :style="{ width: match.time_limit_seconds ? Math.max(0, (countdown / match.time_limit_seconds) * 100) + '%' : '100%' }"
          ></div>
        </div>
      </div>
    </header>

    <!-- Pending / Lobby -->
    <div v-if="match.status === 'pending'" class="grid lg:grid-cols-2 gap-4">
      <article class="rounded-2xl border border-slate-200 bg-white p-5">
        <h3 class="text-sm font-bold text-slate-900 mb-3">Players ({{ joinedCount }} / {{ match.max_players }})</h3>
        <ul class="space-y-2">
          <li v-for="p in activePlayers" :key="p.user_id" class="flex items-center justify-between text-sm">
            <span class="truncate font-medium text-slate-800">
              {{ p.full_name ?? 'Team member' }}
              <span v-if="p.user_id === match.host_user_id" class="text-[11px] uppercase text-purple-700 font-bold ml-1">Host</span>
            </span>
            <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold bg-slate-100 text-slate-700">Ready</span>
          </li>
        </ul>
      </article>

      <article class="rounded-2xl border border-slate-200 bg-white p-5">
        <h3 class="text-sm font-bold text-slate-900 mb-2">How this works</h3>
        <ul class="text-sm text-slate-600 space-y-1.5 list-disc list-inside">
          <li>Everyone races to identify the same mystery colleague.</li>
          <li>Clues are revealed progressively &mdash; each wrong guess unlocks more for <strong>everyone</strong>.</li>
          <li>Up to {{ match.max_players }} players per room, {{ match.max_guesses }} guesses each.</li>
          <li>First to solve gets up to 15 points + speed bonus.</li>
          <li v-if="match.time_limit_seconds" class="text-amber-700 font-medium">
            Timed round: {{ match.time_limit_seconds }} seconds to guess. Fastest solver gets bonus points!
          </li>
          <li v-else class="text-slate-400">No time limit &mdash; take your time.</li>
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
          <button v-if="isHost" type="button" class="text-sm px-4 py-2 rounded-full bg-purple-600 text-white font-semibold hover:bg-purple-700 disabled:opacity-40" :disabled="joinedCount < 1" @click="hostStart">Start game</button>
        </div>
      </article>
    </div>

    <!-- Active / Finished game -->
    <div v-else class="grid lg:grid-cols-[1fr_320px] gap-5 items-start">
      <div class="space-y-5">
        <!-- Clues card -->
        <article class="card p-6">
          <div class="flex items-center gap-2 mb-4">
            <div class="w-8 h-8 rounded-full bg-purple-100 text-purple-700 flex items-center justify-center">
              <SidebarIcon name="sparkle" class="w-4 h-4" />
            </div>
            <h2 class="text-base font-semibold text-slate-900">Clues</h2>
            <span class="ml-auto text-xs text-slate-400">{{ visibleClues.length }} of {{ totalClues }} revealed</span>
          </div>

          <ol class="space-y-3">
            <li v-for="(clue, i) in visibleClues" :key="i" class="flex gap-3 items-start">
              <span class="shrink-0 w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold mt-0.5"
                :class="clueCategoryColor(clue.category)">{{ i + 1 }}</span>
              <div class="flex-1">
                <span class="text-[10px] uppercase tracking-wider font-semibold" :class="clueCategoryTextColor(clue.category)">{{ clue.category.replace('_', ' ') }}</span>
                <p class="text-sm text-slate-700 leading-relaxed">{{ clue.text }}</p>
                <div v-if="clue.category === 'photo' && clue.avatar_url" class="mt-2 relative w-32 h-32 rounded-2xl overflow-hidden border border-slate-200 bg-slate-50">
                  <img :src="clue.avatar_url" alt="Blurred photo hint" class="w-full h-full object-cover" style="filter: blur(14px); transform: scale(1.15);" />
                  <div class="absolute inset-0 pointer-events-none rounded-2xl ring-1 ring-inset ring-rose-200/60"></div>
                </div>
                <p v-else-if="clue.category === 'photo'" class="mt-1 text-xs italic text-slate-400">No photo on file for this teammate.</p>
              </div>
            </li>
            <li v-if="match.status === 'active' && visibleClues.length < totalClues" class="flex gap-3 items-start opacity-50">
              <span class="shrink-0 w-6 h-6 rounded-full bg-slate-100 text-slate-400 flex items-center justify-center text-xs font-bold mt-0.5">?</span>
              <p class="text-sm text-slate-400 italic">A wrong guess by anyone unlocks the next clue...</p>
            </li>
          </ol>
        </article>

        <!-- Guess form -->
        <form v-if="match.status === 'active' && myPlayer && !myPlayer.completed && (countdown === null || countdown > 0)" class="card p-5" @submit.prevent="handleGuess">
          <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-3">
            Make a Guess
            <span class="ml-2 text-purple-600">({{ guessesRemaining }} remaining)</span>
          </h3>
          <div class="grid grid-cols-2 gap-3 mb-4">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">First Name</label>
              <input v-model="firstName" type="text" class="input" placeholder="e.g. John" :disabled="submitting" autocomplete="off" />
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Last Name</label>
              <input v-model="lastName" type="text" class="input" placeholder="e.g. Doe" :disabled="submitting" autocomplete="off" />
            </div>
          </div>
          <button type="submit" class="btn-primary w-full justify-center" :disabled="submitting || !firstName.trim() || !lastName.trim()">
            <span v-if="submitting">Checking...</span>
            <span v-else>Submit Guess</span>
          </button>
          <p v-if="match.time_limit_seconds && countdown !== null && countdown > 0" class="text-[11px] text-center mt-2" :class="timerUrgent ? 'text-red-500 font-semibold' : 'text-slate-400'">
            Solve quickly for a speed bonus (+5 pts if solved in first 25% of time)
          </p>
        </form>

        <!-- Time expired for this player -->
        <div v-if="match.status === 'active' && countdown !== null && countdown <= 0 && myPlayer && !myPlayer.completed" class="card p-5 text-center border-red-200 bg-red-50">
          <div class="text-red-700 font-semibold">Time's up! The clock ran out.</div>
        </div>

        <!-- Spectator message -->
        <div v-if="match.status === 'active' && isSpectator" class="card p-5 text-center">
          <div class="text-slate-600 font-medium">You're watching as host. Players are guessing below.</div>
        </div>

        <!-- Player's own guess history -->
        <div v-if="myPlayer && myPlayer.guesses.length > 0" class="card p-5">
          <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-3">Your Guesses</h3>
          <ul class="space-y-2">
            <li v-for="(g, i) in myPlayer.guesses" :key="i"
              class="flex items-center gap-3 px-3 py-2 rounded-lg"
              :class="g.correct ? 'bg-emerald-50 border border-emerald-200' : 'bg-rose-50 border border-rose-200'">
              <span class="shrink-0 w-5 h-5 rounded-full flex items-center justify-center text-xs font-bold text-white"
                :class="g.correct ? 'bg-emerald-500' : 'bg-rose-400'">{{ g.correct ? '&#10003;' : '&#10005;' }}</span>
              <span class="text-sm font-medium" :class="g.correct ? 'text-emerald-800' : 'text-rose-800'">
                {{ g.first_name }} {{ g.last_name }}
              </span>
            </li>
          </ul>
        </div>

        <!-- Waiting message (player done, game still going) -->
        <div v-if="myPlayer && myPlayer.completed && match.status === 'active'" class="card p-5 text-center">
          <div v-if="myPlayer.won" class="text-emerald-700 font-semibold">
            You got it in {{ myPlayer.guess_count }} guess{{ myPlayer.guess_count !== 1 ? 'es' : '' }}! Waiting for others...
          </div>
          <div v-else class="text-slate-700 font-semibold">Out of guesses. Waiting for others to finish.</div>
        </div>

        <!-- Game over: reveal answer -->
        <div v-if="match.status === 'finished'" class="space-y-5">
          <div class="card p-6 text-center" :class="myPlayer?.won ? 'border-emerald-200 bg-emerald-50' : 'border-amber-200 bg-amber-50'">
            <div v-if="!match.winner_user_id && match.time_limit_seconds" class="text-red-600 font-bold text-sm uppercase tracking-wide mb-2">Time's Up!</div>
            <div v-if="myPlayer?.won" class="w-14 h-14 mx-auto rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center mb-3">
              <SidebarIcon name="star" class="w-7 h-7" />
            </div>
            <h2 class="text-lg font-bold" :class="myPlayer?.won ? 'text-emerald-800' : 'text-slate-800'">
              {{ myPlayer?.won ? 'You got it!' : 'Game over' }}
            </h2>
            <p v-if="myPlayer?.won" class="text-sm text-emerald-600 mt-1">
              You earned <span class="font-bold">{{ myPlayer.points_awarded }}</span> point{{ myPlayer.points_awarded !== 1 ? 's' : '' }}
              <span v-if="myPlayer.points_awarded > 15" class="text-amber-600 font-semibold ml-1">(includes speed bonus!)</span>
            </p>
            <div v-if="board.answer" class="mt-5 flex flex-col items-center gap-3">
              <img v-if="board.answer.avatar_url" :src="board.answer.avatar_url" :alt="board.answer.full_name"
                class="w-20 h-20 rounded-full object-cover border-2 border-slate-200" />
              <div>
                <p class="text-base font-bold text-slate-900">{{ board.answer.full_name }}</p>
                <p class="text-sm text-slate-500">{{ board.answer.role }}</p>
                <p v-if="board.answer.department" class="text-xs text-slate-400">{{ board.answer.department }}</p>
              </div>
            </div>
          </div>

          <!-- Podium -->
          <div v-if="standings.length >= 1" class="card p-6">
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
              <li v-for="(p, i) in standings.slice(3)" :key="p.user_id" class="flex items-center gap-3 text-xs px-3 py-1.5 rounded-lg" :class="p.user_id === me?.id ? 'bg-purple-50 border border-purple-200' : 'bg-slate-50'">
                <span class="w-5 h-5 rounded-full bg-slate-100 flex items-center justify-center text-[10px] font-bold text-slate-500">{{ i + 4 }}</span>
                <span class="flex-1 truncate font-medium text-slate-800">{{ p.full_name ?? 'Team member' }}</span>
                <span class="text-slate-500">{{ (p.series_points ?? 0) + (p.points_awarded ?? 0) }} pts</span>
              </li>
            </ol>
          </div>

          <div v-if="hasMoreRounds" class="card p-5 flex flex-wrap items-center justify-between gap-3 border-sky-200 bg-sky-50">
            <div class="text-sm text-sky-900">
              <strong>Round {{ match.current_round }} of {{ match.total_rounds }} finished.</strong>
              <span class="text-sky-800"> {{ isHost ? 'Start the next round when everyone is ready.' : 'Waiting for the host to start the next round.' }}</span>
            </div>
            <button v-if="isHost" type="button" :disabled="advancing" class="text-sm px-4 py-2 rounded-full bg-sky-600 text-white font-semibold hover:bg-sky-700 disabled:opacity-40" @click="advanceRound">
              {{ advancing ? 'Starting...' : 'Start next round' }}
            </button>
          </div>
        </div>
      </div>

      <!-- Live board sidebar -->
      <aside class="rounded-2xl border border-slate-200 bg-white p-4 space-y-3 lg:sticky lg:top-4">
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-bold text-slate-900">Live board</h3>
          <span class="text-[10px] uppercase tracking-wide text-slate-500">{{ standings.length }} players</span>
        </div>

        <!-- Position indicator -->
        <div v-if="match.status === 'active' && myPlayer && !myPlayer.completed" class="px-3 py-2 rounded-lg bg-purple-50 border border-purple-200">
          <div class="flex items-center justify-between text-xs">
            <span class="text-purple-700 font-semibold">Your position</span>
            <span class="font-mono font-bold text-purple-900">
              #{{ standings.findIndex(p => p.user_id === me?.id) + 1 }} of {{ standings.length }}
            </span>
          </div>
        </div>

        <ol class="space-y-3">
          <li v-for="(p, i) in standings" :key="p.user_id" class="space-y-1">
            <div class="flex items-center justify-between text-xs">
              <div class="flex items-center gap-2 min-w-0">
                <span class="w-4 text-right font-bold tabular-nums" :class="i === 0 && p.won ? 'text-amber-500' : 'text-slate-400'">
                  {{ i === 0 && p.won ? '&#9733;' : (i + 1) }}
                </span>
                <span class="truncate font-semibold text-slate-800">
                  {{ p.full_name ?? 'Team member' }}
                  <span v-if="p.user_id === me?.id" class="text-[10px] uppercase text-purple-700 font-bold ml-1">You</span>
                </span>
              </div>
              <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold" :class="statusBadge(p).cls">{{ statusBadge(p).label }}</span>
            </div>
            <div class="flex gap-1">
              <div v-for="(g, gi) in p.guesses" :key="gi"
                class="w-4 h-4 rounded-sm flex items-center justify-center text-[8px] font-bold text-white"
                :class="g.correct ? 'bg-emerald-500' : 'bg-rose-400'">
                {{ g.correct ? '&#10003;' : '&#10005;' }}
              </div>
              <div v-if="p.guesses.length === 0" class="text-[10px] text-slate-400">No guesses yet</div>
            </div>
            <div v-if="p.won && p.points_awarded" class="text-[10px] text-emerald-600 font-semibold">+{{ p.points_awarded }} pts</div>
          </li>
        </ol>
        <button type="button" class="w-full text-xs px-3 py-2 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-50" @click="leaveRoom">
          {{ match.status === 'finished' ? 'Leave room' : 'Give up and leave' }}
        </button>
      </aside>
    </div>
  </section>
</template>
