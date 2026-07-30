<script setup lang="ts">
import { useCodeBreaker, COLORS, type CodeBreakerGame, type CodeBreakerMatchBoard, type CodeBreakerMatchPlayer } from '~/composables/useCodeBreaker'
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const toast = useToast()
const route = useRoute()
const router = useRouter()
const cb = useCodeBreaker()

const activeTab = ref<'daily' | 'multiplayer'>((route.query.tab as string) === 'multi' || route.query.match ? 'multiplayer' : 'daily')

// Daily state
const game = ref<CodeBreakerGame | null>(null)
const currentGuess = ref<string[]>(['', '', '', ''])
const activeSlot = ref(0)
const loadingDaily = ref(false)
const submittingGuess = ref(false)

// Multiplayer state
const matchBoard = ref<CodeBreakerMatchBoard | null>(null)
const activeMatchId = ref<string | null>(null)
const joinCode = ref((route.query.match as string) || '')
const creatingRoom = ref(false)
const joiningRoom = ref(false)
const selectedTimeLimit = ref<number | null>(120)
const multiGuess = ref<string[]>(['', '', '', ''])
const multiActiveSlot = ref(0)
const submittingMulti = ref(false)
const countdown = ref<number | null>(null)
const me = ref<string | null>(null)
let matchUnsub: (() => void) | null = null
let timerInterval: ReturnType<typeof setInterval> | null = null

const matchMatch = computed(() => matchBoard.value?.match ?? null)
const matchPlayers = computed(() => (matchBoard.value?.players ?? []).filter(p => p.status !== 'left'))
const isHost = computed(() => matchMatch.value && me.value && matchMatch.value.host_user_id === me.value)
const myPlayer = computed<CodeBreakerMatchPlayer | null>(() => matchPlayers.value.find(p => p.user_id === me.value) ?? null)
const timerUrgent = computed(() => countdown.value !== null && countdown.value <= 10)
const timerWarning = computed(() => countdown.value !== null && countdown.value <= 30 && countdown.value > 10)

const rankedPlayers = computed(() => {
  return [...matchPlayers.value].sort((a, b) => {
    const sa = ((a as any).series_points ?? 0) + ((a as any).points_awarded ?? 0)
    const sb = ((b as any).series_points ?? 0) + ((b as any).points_awarded ?? 0)
    if (sa !== sb) return sb - sa
    if (a.won && !b.won) return -1
    if (!a.won && b.won) return 1
    if (a.won && b.won) return a.guess_count - b.guess_count
    return b.guess_count - a.guess_count
  })
})

function seriesPts(p: CodeBreakerMatchPlayer): number {
  return ((p as any).series_points ?? 0) + ((p as any).points_awarded ?? 0)
}

const advancing = ref(false)
const roundsInput = ref(1)
const seriesComplete = computed(() =>
  !!matchMatch.value && matchMatch.value.status === 'finished' && ((matchMatch.value as any).current_round ?? 1) >= ((matchMatch.value as any).total_rounds ?? 1)
)
const hasMoreRounds = computed(() =>
  !!matchMatch.value && matchMatch.value.status === 'finished' && ((matchMatch.value as any).current_round ?? 1) < ((matchMatch.value as any).total_rounds ?? 1)
)

async function saveRounds() {
  if (!matchMatch.value) return
  try {
    await cb.setRounds(matchMatch.value.id, roundsInput.value)
    toast.success(`Best of ${roundsInput.value}`)
    await refreshMatch()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not update rounds')
  }
}

async function advanceRound() {
  if (!matchMatch.value || advancing.value) return
  advancing.value = true
  try {
    await cb.nextRound(matchMatch.value.id)
    await refreshMatch()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not start next round')
  } finally {
    advancing.value = false
  }
}

const COLOR_MAP: Record<string, string> = {
  red: 'bg-red-500', blue: 'bg-blue-500', green: 'bg-emerald-500',
  yellow: 'bg-yellow-400', purple: 'bg-purple-500', orange: 'bg-orange-500'
}
const COLOR_BORDER: Record<string, string> = {
  red: 'border-red-600', blue: 'border-blue-600', green: 'border-emerald-600',
  yellow: 'border-yellow-500', purple: 'border-purple-600', orange: 'border-orange-600'
}
const COLOR_RING: Record<string, string> = {
  red: 'ring-red-300', blue: 'ring-blue-300', green: 'ring-emerald-300',
  yellow: 'ring-yellow-200', purple: 'ring-purple-300', orange: 'ring-orange-300'
}

function formatTime(secs: number): string {
  const m = Math.floor(secs / 60); const s = secs % 60
  return m > 0 ? `${m}:${s.toString().padStart(2, '0')}` : `${s}s`
}

function pickDailyColor(color: string) {
  currentGuess.value[activeSlot.value] = color
  if (activeSlot.value < 3) activeSlot.value = activeSlot.value + 1
}

function clearDailySlot(index: number) {
  currentGuess.value[index] = ''
  activeSlot.value = index
}

function pickMultiColor(color: string) {
  multiGuess.value[multiActiveSlot.value] = color
  if (multiActiveSlot.value < 3) multiActiveSlot.value = multiActiveSlot.value + 1
}

function clearMultiSlot(index: number) {
  multiGuess.value[index] = ''
  multiActiveSlot.value = index
}

function startTimer() {
  stopTimer()
  if (!matchMatch.value?.deadline_at) return
  timerInterval = setInterval(() => {
    if (!matchMatch.value?.deadline_at) { stopTimer(); return }
    const remaining = Math.max(0, Math.ceil((new Date(matchMatch.value.deadline_at).getTime() - Date.now()) / 1000))
    countdown.value = remaining
    if (remaining <= 0) { stopTimer(); refreshMatch() }
  }, 1000)
}
function stopTimer() { if (timerInterval) { clearInterval(timerInterval); timerInterval = null } }

async function loadDailyGame() {
  loadingDaily.value = true
  try { game.value = await cb.startDaily() } catch (e: any) { toast.error(e?.message ?? 'Could not load puzzle') }
  finally { loadingDaily.value = false }
}

async function submitDailyGuess() {
  if (currentGuess.value.some(c => !c)) return
  submittingGuess.value = true
  try {
    game.value = await cb.dailyGuess(currentGuess.value)
    if (game.value.won) toast.success('You cracked the code!')
    else if (game.value.completed) toast.error('Game over!')
    currentGuess.value = ['', '', '', '']
    activeSlot.value = 0
  } catch (e: any) { toast.error(e?.message ?? 'Failed') }
  finally { submittingGuess.value = false }
}

async function refreshMatch() {
  if (!activeMatchId.value) return
  try {
    matchBoard.value = await cb.loadBoard(activeMatchId.value)
    if (matchBoard.value?.match) {
      roundsInput.value = Math.max(1, (matchBoard.value.match as any).total_rounds ?? 1)
    }
    if (matchBoard.value?.match?.status === 'active' && matchBoard.value.match.deadline_at && !timerInterval) startTimer()
  } catch (e: any) { toast.error(e?.message ?? 'Could not load room') }
}

async function handleCreateRoom() {
  creatingRoom.value = true
  try {
    const m = await cb.createMatch({ timeLimit: selectedTimeLimit.value })
    activeMatchId.value = m.id
    router.replace({ query: { tab: 'multi', match: m.code } })
    await refreshMatch()
    matchUnsub = cb.subscribe(m.id, refreshMatch)
  } catch (e: any) { toast.error(e?.message ?? 'Could not create room') }
  finally { creatingRoom.value = false }
}

async function handleJoinRoom() {
  if (!joinCode.value.trim()) return
  joiningRoom.value = true
  try {
    const m = await cb.joinByCode(joinCode.value.trim())
    activeMatchId.value = m.id
    router.replace({ query: { tab: 'multi', match: m.code } })
    await refreshMatch()
    matchUnsub = cb.subscribe(m.id, refreshMatch)
  } catch (e: any) { toast.error(e?.message ?? 'Could not join room') }
  finally { joiningRoom.value = false }
}

async function handleLeaveRoom() {
  if (activeMatchId.value && matchMatch.value?.status === 'pending') {
    try { await cb.leave(activeMatchId.value) } catch {}
  }
  if (matchUnsub) { matchUnsub(); matchUnsub = null }
  stopTimer()
  activeMatchId.value = null
  matchBoard.value = null
  joinCode.value = ''
}

async function handleStartMatch() {
  if (!activeMatchId.value) return
  try { await cb.start(activeMatchId.value); await refreshMatch() }
  catch (e: any) { toast.error(e?.message ?? 'Could not start') }
}

async function handleMatchJoin() {
  if (!matchMatch.value) return
  try { await cb.joinByCode(matchMatch.value.code); await refreshMatch() }
  catch (e: any) { toast.error(e?.message ?? 'Could not join') }
}

async function submitMultiGuess() {
  if (!activeMatchId.value || multiGuess.value.some(c => !c)) return
  submittingMulti.value = true
  try {
    const board = await cb.matchGuess(activeMatchId.value, multiGuess.value)
    matchBoard.value = board
    multiGuess.value = ['', '', '', '']
    multiActiveSlot.value = 0
    const me2 = board.players.find(p => p.user_id === me.value)
    if (me2?.won) toast.success(`Cracked it! +${me2.points_awarded} points`)
    else if (me2?.completed) toast.error('Out of guesses!')
  } catch (e: any) {
    if (e?.message?.includes('time expired')) { toast.error('Time is up!'); refreshMatch() }
    else toast.error(e?.message ?? 'Failed')
  }
  finally { submittingMulti.value = false }
}

function copyInfo(text: string, label: string) {
  navigator.clipboard.writeText(text).then(() => toast.success(`${label} copied`)).catch(() => toast.error('Copy failed'))
}

onMounted(async () => {
  const { data } = await supabase.auth.getUser()
  me.value = data.user?.id ?? null
  if (activeTab.value === 'daily') loadDailyGame()
  if (joinCode.value) handleJoinRoom()
})

onBeforeUnmount(() => { if (matchUnsub) matchUnsub(); stopTimer() })

watch(activeTab, (tab) => { if (tab === 'daily' && !game.value) loadDailyGame() })
</script>

<template>
  <div class="max-w-3xl mx-auto pb-10">
    <header class="text-center mb-6">
      <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-violet-50 border border-violet-200 text-[11px] font-semibold uppercase tracking-[0.2em] text-violet-700">
        <span class="w-1.5 h-1.5 rounded-full bg-violet-500"></span>
        Logic puzzle
      </div>
      <h1 class="mt-3 text-2xl sm:text-4xl font-bold text-slate-900 tracking-tight">Code Breaker</h1>
      <p class="mt-1 text-xs sm:text-sm text-slate-500 max-w-md mx-auto">
        Guess the secret 4-color code in 10 tries.
      </p>
    </header>

    <!-- Tabs -->
    <div class="flex gap-1 mb-6 p-1 rounded-xl bg-slate-100 max-w-xs mx-auto">
      <button type="button" class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg transition-all"
        :class="activeTab === 'daily' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
        @click="activeTab = 'daily'">Daily</button>
      <button type="button" class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg transition-all"
        :class="activeTab === 'multiplayer' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
        @click="activeTab = 'multiplayer'">Multiplayer</button>
    </div>

    <!-- === DAILY === -->
    <div v-if="activeTab === 'daily'">
      <div v-if="loadingDaily" class="text-center text-sm text-slate-400 py-10">Loading today's code...</div>
      <div v-else-if="game" class="space-y-5">

        <!-- How to play (always visible, collapsible) -->
        <details class="card bg-violet-50 border-violet-200" :open="game.guess_count === 0 && !game.completed ? true : undefined">
          <summary class="p-4 cursor-pointer select-none flex items-center justify-between">
            <h3 class="text-xs font-bold text-violet-800 uppercase tracking-wide">How to play</h3>
            <span class="text-xs text-violet-500">tap to toggle</span>
          </summary>
          <div class="px-4 pb-4">
            <ol class="text-xs text-violet-700 space-y-1.5 list-decimal list-inside">
              <li>Tap a <span class="font-bold">slot</span> below to select it (highlighted with a ring).</li>
              <li>Tap a <span class="font-bold">color</span> from the palette to fill that slot.</li>
              <li>Once all 4 slots are filled, press <span class="font-bold">Submit Guess</span>.</li>
              <li>Read the feedback pegs:
                <div class="mt-1 ml-4 space-y-1">
                  <span class="flex items-center gap-2">
                    <span class="w-4 h-4 rounded-full bg-slate-900 border border-slate-700 inline-block shrink-0"></span>
                    <span>= right color, right position</span>
                  </span>
                  <span class="flex items-center gap-2">
                    <span class="w-4 h-4 rounded-full bg-white border-2 border-slate-400 inline-block shrink-0"></span>
                    <span>= right color, wrong position</span>
                  </span>
                  <span class="flex items-center gap-2">
                    <span class="w-4 h-4 rounded-full border-2 border-dashed border-slate-200 inline-block shrink-0"></span>
                    <span>= color not in code</span>
                  </span>
                </div>
              </li>
              <li>You have <span class="font-bold">10 guesses</span> to crack the 4-color code. Good luck!</li>
            </ol>
          </div>
        </details>

        <!-- Guess history -->
        <div v-if="game.guesses.length > 0" class="card p-5 space-y-3">
          <h2 class="text-sm font-bold text-slate-900">Guesses ({{ game.guess_count }} / 10)</h2>
          <div v-for="(guess, i) in game.guesses" :key="i" class="flex items-center gap-4 py-1.5" :class="i < game.guesses.length - 1 ? 'border-b border-slate-100' : ''">
            <span class="w-5 text-xs text-slate-400 font-mono text-right shrink-0">{{ i + 1 }}</span>
            <div class="flex gap-2">
              <div v-for="(c, j) in guess" :key="j" class="w-9 h-9 rounded-full border-2 shadow-sm" :class="[COLOR_MAP[c], COLOR_BORDER[c]]"></div>
            </div>
            <div class="flex gap-1.5 ml-auto">
              <div v-for="(fb, j) in game.feedback[i]" :key="j"
                class="w-5 h-5 rounded-full border-2"
                :class="fb === 'black' ? 'bg-slate-900 border-slate-700' : 'bg-white border-slate-400'"></div>
              <div v-for="n in (4 - game.feedback[i].length)" :key="'e'+n" class="w-5 h-5 rounded-full border-2 border-dashed border-slate-200"></div>
            </div>
          </div>
        </div>

        <!-- Guess input -->
        <div v-if="!game.completed" class="card p-5 space-y-5">
          <div>
            <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-3">Your guess</h3>
            <!-- 4 slots -->
            <div class="flex justify-center gap-4">
              <button v-for="(_, i) in 4" :key="i" type="button"
                class="w-12 h-12 sm:w-14 sm:h-14 rounded-full border-[3px] transition-all relative"
                :class="[
                  currentGuess[i] ? [COLOR_MAP[currentGuess[i]], COLOR_BORDER[currentGuess[i]]] : 'border-dashed border-slate-300 bg-slate-50',
                  activeSlot === i ? 'ring-4 ring-offset-2 ' + (currentGuess[i] ? COLOR_RING[currentGuess[i]] : 'ring-violet-200') : '',
                ]"
                @click="activeSlot = i">
                <span v-if="currentGuess[i]" class="absolute -top-1 -right-1 w-4 h-4 rounded-full bg-white border border-slate-300 flex items-center justify-center text-[8px] text-slate-500 cursor-pointer hover:bg-red-50 hover:border-red-300 hover:text-red-500"
                  @click.stop="clearDailySlot(i)">x</span>
                <span v-else class="text-xs text-slate-400 font-bold">{{ i + 1 }}</span>
              </button>
            </div>
          </div>

          <!-- Color palette -->
          <div>
            <p class="text-xs text-slate-400 mb-2 text-center">Tap a color to fill slot {{ activeSlot + 1 }}</p>
            <div class="flex justify-center gap-3 flex-wrap">
              <button v-for="c in COLORS" :key="c" type="button"
                class="w-10 h-10 sm:w-11 sm:h-11 rounded-full border-2 transition-all hover:scale-110 active:scale-95 shadow-sm"
                :class="[COLOR_MAP[c], COLOR_BORDER[c]]"
                @click="pickDailyColor(c)">
              </button>
            </div>
          </div>

          <button type="button" class="btn-primary w-full justify-center" :disabled="submittingGuess || currentGuess.some(c => !c)" @click="submitDailyGuess">
            {{ submittingGuess ? 'Checking...' : 'Submit Guess' }}
          </button>
        </div>

        <!-- Result -->
        <div v-if="game.completed" class="card p-6 text-center" :class="game.won ? 'border-emerald-200 bg-emerald-50' : 'border-amber-200 bg-amber-50'">
          <h2 class="text-lg font-bold" :class="game.won ? 'text-emerald-800' : 'text-slate-800'">
            {{ game.won ? 'Code Cracked!' : 'Game Over' }}
          </h2>
          <p v-if="game.won" class="text-sm text-emerald-600 mt-1">You solved it in {{ game.guess_count }} guess{{ game.guess_count !== 1 ? 'es' : '' }}!</p>
          <div v-if="game.secret_code" class="mt-4">
            <p class="text-xs text-slate-500 font-semibold uppercase tracking-wide mb-2">The secret code was:</p>
            <div class="flex justify-center gap-3">
              <div v-for="(c, i) in game.secret_code" :key="i" class="w-11 h-11 rounded-full border-2 shadow-sm" :class="[COLOR_MAP[c], COLOR_BORDER[c]]"></div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- === MULTIPLAYER === -->
    <div v-else>
      <template v-if="activeMatchId && matchBoard && matchMatch">
        <header class="rounded-2xl border border-violet-200 bg-gradient-to-br from-violet-50 to-amber-50 p-5 mb-5">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div class="text-[11px] uppercase tracking-wider text-violet-700 font-bold">Code Breaker Race</div>
              <h2 class="text-xl font-bold text-slate-900">Multiplayer Room</h2>
              <p class="text-sm text-slate-600">
                <span v-if="matchMatch.status === 'pending'">Lobby. {{ matchPlayers.length }} joined.</span>
                <span v-else-if="matchMatch.status === 'active'">Race to crack the code!</span>
                <span v-else-if="matchMatch.status === 'finished' && hasMoreRounds">Round {{ (matchMatch as any).current_round }} of {{ (matchMatch as any).total_rounds }} complete. Next round up!</span>
                <span v-else-if="matchMatch.status === 'finished'">{{ ((matchMatch as any).total_rounds ?? 1) > 1 ? 'Series complete.' : 'Round complete.' }}</span>
                <span v-if="matchMatch && ((matchMatch as any).total_rounds ?? 1) > 1" class="block text-[11px] mt-1 font-semibold text-sky-700">Round {{ (matchMatch as any).current_round ?? 1 }} of {{ (matchMatch as any).total_rounds ?? 1 }}</span>
                <span v-else>Game complete.</span>
              </p>
            </div>
            <div class="flex flex-col items-end gap-1">
              <div class="font-mono text-2xl font-bold tracking-widest text-slate-900">{{ matchMatch.code }}</div>
              <button type="button" class="text-xs px-3 py-1 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-50" @click="copyInfo(matchMatch.code, 'Code')">Copy code</button>
            </div>
          </div>
          <div v-if="matchMatch.status === 'active' && countdown !== null" class="mt-4">
            <div class="flex items-center justify-between text-xs mb-1">
              <span class="font-semibold" :class="timerUrgent ? 'text-red-600' : timerWarning ? 'text-amber-600' : 'text-slate-600'">Time</span>
              <span class="font-mono font-bold text-lg" :class="timerUrgent ? 'text-red-600 animate-pulse' : timerWarning ? 'text-amber-600' : 'text-slate-900'">{{ formatTime(countdown) }}</span>
            </div>
            <div class="w-full h-2 rounded-full bg-slate-200 overflow-hidden">
              <div class="h-full rounded-full transition-all duration-1000" :class="timerUrgent ? 'bg-red-500' : timerWarning ? 'bg-amber-400' : 'bg-violet-500'"
                :style="{ width: matchMatch.time_limit_seconds ? Math.max(0, (countdown / matchMatch.time_limit_seconds) * 100) + '%' : '100%' }"></div>
            </div>
          </div>
        </header>

        <!-- Lobby -->
        <div v-if="matchMatch.status === 'pending'" class="space-y-4">
          <article class="card p-5">
            <h3 class="text-sm font-bold text-slate-900 mb-3">Players ({{ matchPlayers.length }})</h3>
            <ul class="space-y-2">
              <li v-for="p in matchPlayers" :key="p.user_id" class="flex items-center justify-between text-sm">
                <span class="truncate font-medium text-slate-800">{{ p.full_name ?? 'Team member' }}
                  <span v-if="p.user_id === matchMatch.host_user_id" class="text-[11px] uppercase text-violet-700 font-bold ml-1">Host</span>
                </span>
              </li>
            </ul>
          </article>
          <div class="card p-4 bg-violet-50 border-violet-200 text-xs text-violet-700 space-y-1">
            <p class="font-bold text-violet-800">How to play</p>
            <p>Everyone races to guess the same secret 4-color code. Tap a slot, then tap a color to fill it. Submit your guess and read the feedback pegs.</p>
          </div>
          <article v-if="isHost" class="card p-4">
            <div class="flex flex-wrap items-center gap-2">
              <label class="text-xs font-bold text-slate-700">Rounds</label>
              <select v-model.number="roundsInput" class="text-xs px-2 py-1 rounded border border-slate-300 bg-white">
                <option v-for="n in [1,2,3,5,7,10]" :key="n" :value="n">Best of {{ n }}</option>
              </select>
              <button type="button" class="text-xs px-3 py-1.5 rounded-full bg-slate-900 text-white hover:bg-slate-800" @click="saveRounds">Save</button>
              <span class="text-[11px] text-slate-500">Auto-continues after each round.</span>
            </div>
          </article>
          <div class="flex flex-wrap items-center justify-between gap-3 card p-4">
            <span class="text-sm text-slate-600">
              <span v-if="isHost && !myPlayer">You're hosting.</span>
              <span v-else-if="isHost">Start when ready.</span>
              <span v-else>Waiting for host...</span>
            </span>
            <div class="flex gap-2">
              <button v-if="myPlayer" type="button" class="text-sm px-4 py-2 rounded-full bg-white border border-slate-300 text-slate-700" @click="handleLeaveRoom">Leave</button>
              <button v-if="isHost && !myPlayer" type="button" class="text-sm px-4 py-2 rounded-full bg-blue-600 text-white font-semibold" @click="handleMatchJoin">Join as player</button>
              <button v-if="isHost" type="button" class="text-sm px-4 py-2 rounded-full bg-violet-600 text-white font-semibold disabled:opacity-40" :disabled="matchPlayers.length < 1" @click="handleStartMatch">Start</button>
            </div>
          </div>
        </div>

        <!-- Active game -->
        <div v-else-if="matchMatch.status === 'active'" class="grid lg:grid-cols-[1fr_280px] gap-5 items-start">
          <div class="space-y-4">
            <!-- My guess history -->
            <div v-if="myPlayer && myPlayer.guesses.length > 0" class="card p-5 space-y-2">
              <h3 class="text-sm font-bold text-slate-900">Your guesses ({{ myPlayer.guess_count }} / {{ matchMatch.max_guesses }})</h3>
              <div v-for="(guess, i) in myPlayer.guesses" :key="i" class="flex items-center gap-3 py-1" :class="i < myPlayer.guesses.length - 1 ? 'border-b border-slate-100' : ''">
                <span class="w-4 text-[10px] text-slate-400 font-mono text-right shrink-0">{{ i + 1 }}</span>
                <div class="flex gap-1.5">
                  <div v-for="(c, j) in guess" :key="j" class="w-7 h-7 rounded-full border-2 shadow-sm" :class="[COLOR_MAP[c], COLOR_BORDER[c]]"></div>
                </div>
                <div class="flex gap-1 ml-auto">
                  <div v-for="(fb, j) in myPlayer.feedback[i]" :key="j" class="w-4 h-4 rounded-full border-2"
                    :class="fb === 'black' ? 'bg-slate-900 border-slate-700' : 'bg-white border-slate-400'"></div>
                  <div v-for="n in (4 - myPlayer.feedback[i].length)" :key="'e'+n" class="w-4 h-4 rounded-full border-2 border-dashed border-slate-200"></div>
                </div>
              </div>
            </div>

            <!-- Guess input -->
            <div v-if="myPlayer && !myPlayer.completed" class="card p-5 space-y-4">
              <div class="flex justify-center gap-3">
                <button v-for="(_, i) in 4" :key="i" type="button"
                  class="w-11 h-11 rounded-full border-[3px] transition-all relative"
                  :class="[
                    multiGuess[i] ? [COLOR_MAP[multiGuess[i]], COLOR_BORDER[multiGuess[i]]] : 'border-dashed border-slate-300 bg-slate-50',
                    multiActiveSlot === i ? 'ring-4 ring-offset-2 ' + (multiGuess[i] ? COLOR_RING[multiGuess[i]] : 'ring-violet-200') : '',
                  ]"
                  @click="multiActiveSlot = i">
                  <span v-if="multiGuess[i]" class="absolute -top-1 -right-1 w-4 h-4 rounded-full bg-white border border-slate-300 flex items-center justify-center text-[8px] text-slate-500 cursor-pointer"
                    @click.stop="clearMultiSlot(i)">x</span>
                  <span v-else class="text-[10px] text-slate-400 font-bold">{{ i + 1 }}</span>
                </button>
              </div>
              <div class="flex justify-center gap-2.5 flex-wrap">
                <button v-for="c in COLORS" :key="c" type="button"
                  class="w-9 h-9 rounded-full border-2 transition-all hover:scale-110 active:scale-95 shadow-sm"
                  :class="[COLOR_MAP[c], COLOR_BORDER[c]]"
                  @click="pickMultiColor(c)"></button>
              </div>
              <button type="button" class="btn-primary w-full justify-center" :disabled="submittingMulti || multiGuess.some(c => !c)" @click="submitMultiGuess">
                {{ submittingMulti ? 'Checking...' : 'Submit' }}
              </button>
            </div>
            <div v-else-if="myPlayer?.completed" class="card p-5 text-center">
              <div v-if="myPlayer.won" class="text-emerald-700 font-semibold">Cracked it in {{ myPlayer.guess_count }}! Waiting for others...</div>
              <div v-else class="text-slate-600">Out of guesses. Waiting for others.</div>
            </div>
          </div>

          <!-- Sidebar -->
          <aside class="rounded-2xl border border-slate-200 bg-white p-4 space-y-3 lg:sticky lg:top-4">
            <h3 class="text-sm font-bold text-slate-900">Live board</h3>
            <ol class="space-y-2">
              <li v-for="p in matchPlayers" :key="p.user_id" class="flex items-center justify-between text-xs">
                <span class="truncate font-medium text-slate-800">
                  {{ p.full_name ?? 'Team member' }}
                  <span v-if="p.user_id === me" class="text-[10px] text-violet-700 font-bold ml-1">You</span>
                </span>
                <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold"
                  :class="p.won ? 'bg-emerald-100 text-emerald-800' : p.completed ? 'bg-slate-200 text-slate-700' : 'bg-sky-100 text-sky-800'">
                  {{ p.won ? `Solved (${p.guess_count})` : p.completed ? 'Out' : `${p.guess_count} guesses` }}
                </span>
              </li>
            </ol>
            <button type="button" class="w-full text-xs px-3 py-2 rounded-full bg-white border border-slate-300 text-slate-700" @click="handleLeaveRoom">Leave</button>
          </aside>
        </div>

        <!-- Finished -->
        <div v-else-if="matchMatch.status === 'finished'" class="space-y-5">
          <article class="card p-6 text-center" :class="myPlayer?.won ? 'border-emerald-200 bg-emerald-50' : 'border-amber-200 bg-amber-50'">
            <div v-if="!matchMatch.winner_user_id && matchMatch.time_limit_seconds" class="text-red-600 font-bold text-sm uppercase tracking-wide mb-2">Time's Up!</div>
            <h2 class="text-lg font-bold" :class="myPlayer?.won ? 'text-emerald-800' : 'text-slate-800'">{{ myPlayer?.won ? 'You cracked it!' : 'Game Over' }}</h2>
            <p v-if="myPlayer?.points_awarded" class="text-sm mt-1 text-emerald-600">+{{ myPlayer.points_awarded }} points</p>
            <div v-if="matchMatch.secret_code" class="mt-4">
              <p class="text-xs text-slate-500 font-semibold uppercase tracking-wide mb-2">The secret code was:</p>
              <div class="flex justify-center gap-3">
                <div v-for="(c, i) in matchMatch.secret_code" :key="i" class="w-11 h-11 rounded-full border-2 shadow-sm" :class="[COLOR_MAP[c], COLOR_BORDER[c]]"></div>
              </div>
            </div>
          </article>

          <!-- Podium -->
          <article v-if="rankedPlayers.length >= 1" class="card p-6">
            <h3 class="text-sm font-bold text-slate-900 text-center mb-6">{{ seriesComplete && ((matchMatch as any)?.total_rounds ?? 1) > 1 ? 'Series Podium' : (((matchMatch as any)?.total_rounds ?? 1) > 1 ? 'Round ' + ((matchMatch as any)?.current_round ?? 1) + ' Podium' : 'Podium') }}</h3>
            <div class="flex items-end justify-center gap-3 max-w-sm mx-auto">
              <!-- 2nd Place -->
              <div v-if="rankedPlayers[1]" class="flex flex-col items-center flex-1">
                <div class="w-10 h-10 rounded-full bg-slate-200 flex items-center justify-center text-sm font-bold text-slate-700 mb-2">
                  {{ rankedPlayers[1].full_name?.charAt(0) ?? '?' }}
                </div>
                <p class="text-[11px] font-semibold text-slate-700 text-center truncate max-w-[80px]">{{ rankedPlayers[1].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-slate-500">{{ seriesPts(rankedPlayers[1]) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-slate-200 flex items-end justify-center" style="height: 60px;">
                  <span class="text-lg font-bold text-slate-600 mb-2">2</span>
                </div>
              </div>
              <!-- 1st Place -->
              <div v-if="rankedPlayers[0]" class="flex flex-col items-center flex-1">
                <div class="w-12 h-12 rounded-full bg-amber-100 border-2 border-amber-300 flex items-center justify-center text-base font-bold text-amber-700 mb-2">
                  {{ rankedPlayers[0].full_name?.charAt(0) ?? '?' }}
                </div>
                <p class="text-xs font-bold text-slate-900 text-center truncate max-w-[80px]">{{ rankedPlayers[0].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-amber-700 font-semibold">{{ seriesPts(rankedPlayers[0]) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-amber-100 border-2 border-amber-200 flex items-end justify-center" style="height: 90px;">
                  <span class="text-2xl mb-2">&#x1F3C6;</span>
                </div>
              </div>
              <!-- 3rd Place -->
              <div v-if="rankedPlayers[2]" class="flex flex-col items-center flex-1">
                <div class="w-10 h-10 rounded-full bg-orange-100 flex items-center justify-center text-sm font-bold text-orange-700 mb-2">
                  {{ rankedPlayers[2].full_name?.charAt(0) ?? '?' }}
                </div>
                <p class="text-[11px] font-semibold text-slate-700 text-center truncate max-w-[80px]">{{ rankedPlayers[2].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-slate-500">{{ seriesPts(rankedPlayers[2]) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-orange-100 flex items-end justify-center" style="height: 40px;">
                  <span class="text-lg font-bold text-orange-600 mb-2">3</span>
                </div>
              </div>
            </div>
            <!-- Remaining players -->
            <ol v-if="rankedPlayers.length > 3" class="mt-5 space-y-1.5 border-t border-slate-100 pt-4">
              <li v-for="(p, i) in rankedPlayers.slice(3)" :key="p.user_id" class="flex items-center gap-3 text-xs px-3 py-1.5 rounded-lg" :class="p.user_id === me ? 'bg-violet-50 border border-violet-200' : 'bg-slate-50'">
                <span class="w-5 h-5 rounded-full bg-slate-100 flex items-center justify-center text-[10px] font-bold text-slate-500">{{ i + 4 }}</span>
                <span class="flex-1 truncate font-medium text-slate-800">{{ p.full_name ?? 'Team member' }}</span>
                <span class="text-slate-500">{{ seriesPts(p) }} pts</span>
              </li>
            </ol>
          </article>

          <div v-if="hasMoreRounds" class="rounded-2xl border border-sky-200 bg-sky-50 p-5 flex flex-wrap items-center justify-between gap-3">
            <div class="text-sm text-sky-900">
              <strong>Round {{ (matchMatch as any).current_round }} of {{ (matchMatch as any).total_rounds }} finished.</strong>
              <span class="text-sky-800"> {{ isHost ? 'Start the next round when everyone is ready.' : 'Waiting for the host to start the next round.' }}</span>
            </div>
            <button v-if="isHost" type="button" :disabled="advancing" class="text-sm px-4 py-2 rounded-full bg-sky-600 text-white font-semibold hover:bg-sky-700 disabled:opacity-40" @click="advanceRound">
              {{ advancing ? 'Starting...' : 'Start next round' }}
            </button>
          </div>

          <button type="button" class="btn-secondary w-full justify-center" @click="handleLeaveRoom">Leave room</button>
        </div>
      </template>

      <!-- Create / Join -->
      <div v-else class="space-y-5">
        <article class="card p-6 text-center">
          <div class="w-14 h-14 mx-auto rounded-full bg-violet-100 text-violet-700 flex items-center justify-center mb-4">
            <SidebarIcon name="lock" class="w-7 h-7" />
          </div>
          <h2 class="text-lg font-semibold text-slate-900">Multiplayer Code Breaker</h2>
          <p class="text-sm text-slate-500 mt-1 max-w-sm mx-auto">Race to crack the same 4-color code. First to solve wins the most points.</p>
          <div class="mt-5 max-w-xs mx-auto">
            <label class="block text-xs font-semibold text-slate-600 uppercase tracking-wide mb-2 text-left">Timer</label>
            <div class="grid grid-cols-5 gap-1.5">
              <button v-for="opt in [{ label: 'None', value: null }, { label: '60s', value: 60 }, { label: '90s', value: 90 }, { label: '2m', value: 120 }, { label: '5m', value: 300 }]"
                :key="String(opt.value)" type="button"
                class="px-2 py-1.5 text-xs font-semibold rounded-lg border transition-all"
                :class="selectedTimeLimit === opt.value ? 'bg-violet-600 text-white border-violet-600' : 'bg-white text-slate-600 border-slate-200 hover:border-violet-300'"
                @click="selectedTimeLimit = opt.value">{{ opt.label }}</button>
            </div>
          </div>
          <button type="button" class="btn-primary mt-5 px-8" :disabled="creatingRoom" @click="handleCreateRoom">
            {{ creatingRoom ? 'Creating...' : 'Create Room' }}
          </button>
        </article>
        <div class="relative">
          <div class="absolute inset-0 flex items-center"><div class="w-full border-t border-slate-200"></div></div>
          <div class="relative flex justify-center"><span class="bg-white px-3 text-xs font-semibold text-slate-400 uppercase">or join</span></div>
        </div>
        <form class="card p-5" @submit.prevent="handleJoinRoom">
          <label class="block text-xs font-semibold text-slate-600 uppercase tracking-wide mb-2">Room Code</label>
          <div class="flex gap-3">
            <input v-model="joinCode" type="text" class="input flex-1 text-center font-mono text-lg uppercase tracking-widest" placeholder="ABCDEF" maxlength="6" :disabled="joiningRoom" />
            <button type="submit" class="btn-primary px-5" :disabled="joiningRoom || joinCode.trim().length < 4">{{ joiningRoom ? '...' : 'Join' }}</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
