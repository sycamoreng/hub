<script setup lang="ts">
import { useCrossword, type CrosswordPuzzle, type CrosswordMatchBoard, type CrosswordMatchPlayer } from '~/composables/useCrossword'
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const toast = useToast()
const route = useRoute()
const router = useRouter()
const cw = useCrossword()

const activeTab = ref<'daily' | 'multiplayer'>((route.query.tab as string) === 'multi' || route.query.match ? 'multiplayer' : 'daily')

// Daily state
const puzzle = ref<CrosswordPuzzle | null>(null)
const playerGrid = ref<(string | null)[][]>([])
const dailyCompleted = ref(false)
const dailyTime = ref(0)
const loadingDaily = ref(false)
const checking = ref(false)
const selectedCell = ref<[number, number] | null>(null)
const direction = ref<'across' | 'down'>('across')
const hiddenInputRef = ref<HTMLInputElement | null>(null)
let timerStart = 0
let dailyTimerInterval: ReturnType<typeof setInterval> | null = null

// Multiplayer state
const matchBoard = ref<CrosswordMatchBoard | null>(null)
const multiGrid = ref<(string | null)[][]>([])
const activeMatchId = ref<string | null>(null)
const joinCode = ref((route.query.match as string) || '')
const creatingRoom = ref(false)
const joiningRoom = ref(false)
const selectedTimeLimit = ref<number | null>(120)
const submittingMulti = ref(false)
const countdown = ref<number | null>(null)
const multiStartTime = ref(0)
const me = ref<string | null>(null)
let matchUnsub: (() => void) | null = null
let matchTimerInterval: ReturnType<typeof setInterval> | null = null

const matchMatch = computed(() => matchBoard.value?.match ?? null)
const matchPlayers = computed(() => (matchBoard.value?.players ?? []).filter(p => p.status !== 'left'))
const isHost = computed(() => matchMatch.value && me.value && matchMatch.value.host_user_id === me.value)
const myPlayer = computed<CrosswordMatchPlayer | null>(() => matchPlayers.value.find(p => p.user_id === me.value) ?? null)
const timerUrgent = computed(() => countdown.value !== null && countdown.value <= 10)
const timerWarning = computed(() => countdown.value !== null && countdown.value <= 30 && countdown.value > 10)

const rankedPlayers = computed(() => {
  return [...matchPlayers.value].sort((a, b) => {
    const sa = ((a as any).series_points ?? 0) + ((a as any).points_awarded ?? 0)
    const sb = ((b as any).series_points ?? 0) + ((b as any).points_awarded ?? 0)
    if (sa !== sb) return sb - sa
    if (a.won && !b.won) return -1
    if (!a.won && b.won) return 1
    if (a.won && b.won) return a.time_seconds - b.time_seconds
    return 0
  })
})

function seriesPts(p: CrosswordMatchPlayer): number {
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
    await cw.setRounds(matchMatch.value.id, roundsInput.value)
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
    await cw.nextRound(matchMatch.value.id)
    multiGrid.value = []
    await refreshMatch()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not start next round')
  } finally {
    advancing.value = false
  }
}

// Which grid is active for input
const activeGridRef = computed(() => activeTab.value === 'daily' ? playerGrid : multiGrid)
const activePuzzle = computed(() => activeTab.value === 'daily' ? puzzle.value : matchBoard.value?.puzzle ?? null)

function formatTime(secs: number): string {
  const m = Math.floor(secs / 60); const s = secs % 60
  return `${m}:${s.toString().padStart(2, '0')}`
}

function initGrid(grid: (string | null)[][]) {
  return grid.map(row => row.map(cell => cell !== null ? '' : null))
}

function isBlocked(r: number, c: number, grid: (string | null)[][] | null): boolean {
  if (!grid) return true
  return grid[r]?.[c] === null || grid[r]?.[c] === undefined
}

function cellNumber(r: number, c: number): number | null {
  const pz = activePuzzle.value
  if (!pz) return null
  for (const cl of [...pz.clues_across, ...pz.clues_down]) {
    if (cl.row === r && cl.col === c) return cl.number
  }
  return null
}

function activeClue(r: number, c: number): { number: number; clue: string } | null {
  const pz = activePuzzle.value
  if (!pz) return null
  const clueList = direction.value === 'across' ? pz.clues_across : pz.clues_down
  for (const cl of clueList) {
    if (direction.value === 'across' && cl.row === r && c >= cl.col && c < cl.col + cl.length) return cl
    if (direction.value === 'down' && cl.col === c && r >= cl.row && r < cl.row + cl.length) return cl
  }
  return null
}

const currentClue = computed(() => {
  if (!selectedCell.value) return null
  return activeClue(selectedCell.value[0], selectedCell.value[1])
})

function highlightedCells(): Set<string> {
  const set = new Set<string>()
  if (!selectedCell.value || !activePuzzle.value) return set
  const [sr, sc] = selectedCell.value
  const cl = activeClue(sr, sc)
  if (!cl) return set
  if (direction.value === 'across') {
    for (let c = cl.col; c < cl.col + cl.length; c++) set.add(`${cl.row},${c}`)
  } else {
    for (let r = cl.row; r < cl.row + cl.length; r++) set.add(`${r},${cl.col}`)
  }
  return set
}

function selectCell(r: number, c: number) {
  const pz = activePuzzle.value
  if (!pz || isBlocked(r, c, pz.grid)) return
  if (selectedCell.value && selectedCell.value[0] === r && selectedCell.value[1] === c) {
    direction.value = direction.value === 'across' ? 'down' : 'across'
  } else {
    selectedCell.value = [r, c]
  }
  nextTick(() => hiddenInputRef.value?.focus())
}

function isSelected(r: number, c: number): boolean {
  if (!selectedCell.value) return false
  return selectedCell.value[0] === r && selectedCell.value[1] === c
}

function findNextCell(r: number, c: number, forward: boolean): [number, number] | null {
  const pz = activePuzzle.value
  if (!pz) return null
  const dr = direction.value === 'down' ? (forward ? 1 : -1) : 0
  const dc = direction.value === 'across' ? (forward ? 1 : -1) : 0
  const nr = r + dr; const nc = c + dc
  if (nr >= 0 && nr < 5 && nc >= 0 && nc < 5 && !isBlocked(nr, nc, pz.grid)) return [nr, nc]
  return null
}

function handleHiddenInput(e: Event) {
  const input = e.target as HTMLInputElement
  const val = input.value
  input.value = ''
  if (!selectedCell.value || !val) return
  const letter = val.replace(/[^a-zA-Z]/g, '').slice(-1).toUpperCase()
  if (!letter) return
  const [r, c] = selectedCell.value
  activeGridRef.value[r][c] = letter
  const next = findNextCell(r, c, true)
  if (next) selectedCell.value = next
}

function handleHiddenKeydown(e: KeyboardEvent) {
  handleGridKeydown(e)
}

function handleGridKeydown(e: KeyboardEvent) {
  if (!selectedCell.value) return
  const [r, c] = selectedCell.value
  if (e.key === 'Backspace') {
    e.preventDefault()
    if (activeGridRef.value[r][c]) {
      activeGridRef.value[r][c] = ''
    } else {
      const prev = findNextCell(r, c, false)
      if (prev) { selectedCell.value = prev; activeGridRef.value[prev[0]][prev[1]] = '' }
    }
  } else if (e.key === 'ArrowRight') { e.preventDefault(); moveTo(r, c + 1) }
  else if (e.key === 'ArrowLeft') { e.preventDefault(); moveTo(r, c - 1) }
  else if (e.key === 'ArrowDown') { e.preventDefault(); moveTo(r + 1, c) }
  else if (e.key === 'ArrowUp') { e.preventDefault(); moveTo(r - 1, c) }
  else if (e.key === 'Tab') { e.preventDefault(); direction.value = direction.value === 'across' ? 'down' : 'across' }
  else if (e.key.length === 1 && /^[a-zA-Z]$/.test(e.key)) {
    e.preventDefault()
    activeGridRef.value[r][c] = e.key.toUpperCase()
    const next = findNextCell(r, c, true)
    if (next) selectedCell.value = next
  }
}

function moveTo(r: number, c: number) {
  const pz = activePuzzle.value
  if (!pz) return
  if (r >= 0 && r < 5 && c >= 0 && c < 5 && !isBlocked(r, c, pz.grid)) selectedCell.value = [r, c]
}

// Daily
async function loadDailyPuzzle() {
  loadingDaily.value = true
  try {
    const data = await cw.loadDaily()
    puzzle.value = data.puzzle
    dailyCompleted.value = data.attempt.completed
    dailyTime.value = data.attempt.time_seconds
    if (data.attempt.grid_state && Array.isArray(data.attempt.grid_state) && data.attempt.grid_state.length > 0) {
      playerGrid.value = data.attempt.grid_state
    } else {
      playerGrid.value = initGrid(data.puzzle.grid)
    }
    if (!dailyCompleted.value) {
      timerStart = Date.now() - dailyTime.value * 1000
      dailyTimerInterval = setInterval(() => {
        dailyTime.value = Math.floor((Date.now() - timerStart) / 1000)
      }, 1000)
    }
  } catch (e: any) { toast.error(e?.message ?? 'Could not load puzzle') }
  finally { loadingDaily.value = false }
}

async function checkDailySolution() {
  checking.value = true
  try {
    const res = await cw.checkDaily(playerGrid.value, dailyTime.value)
    if (res.correct) {
      dailyCompleted.value = true
      if (dailyTimerInterval) { clearInterval(dailyTimerInterval); dailyTimerInterval = null }
      toast.success('Crossword complete!')
    } else {
      toast.error('Not quite right — some letters are incorrect.')
    }
  } catch (e: any) { toast.error(e?.message ?? 'Failed') }
  finally { checking.value = false }
}

// Multiplayer
function startMatchTimer() {
  stopMatchTimer()
  if (!matchMatch.value?.deadline_at) return
  matchTimerInterval = setInterval(() => {
    if (!matchMatch.value?.deadline_at) { stopMatchTimer(); return }
    const remaining = Math.max(0, Math.ceil((new Date(matchMatch.value.deadline_at).getTime() - Date.now()) / 1000))
    countdown.value = remaining
    if (remaining <= 0) { stopMatchTimer(); refreshMatch() }
  }, 1000)
}
function stopMatchTimer() { if (matchTimerInterval) { clearInterval(matchTimerInterval); matchTimerInterval = null } }

async function refreshMatch() {
  if (!activeMatchId.value) return
  try {
    matchBoard.value = await cw.loadBoard(activeMatchId.value)
    if (matchBoard.value?.match) {
      roundsInput.value = Math.max(1, (matchBoard.value.match as any).total_rounds ?? 1)
    }
    if (matchBoard.value?.match?.status === 'active') {
      if (matchBoard.value.match.deadline_at && !matchTimerInterval) startMatchTimer()
      if (matchBoard.value.puzzle && multiGrid.value.flat().every(c => c === '' || c === null)) {
        multiGrid.value = initGrid(matchBoard.value.puzzle.grid)
        multiStartTime.value = Date.now()
      }
    }
  } catch (e: any) { toast.error(e?.message ?? 'Could not load room') }
}

async function handleCreateRoom() {
  creatingRoom.value = true
  try {
    const m = await cw.createMatch({ timeLimit: selectedTimeLimit.value })
    activeMatchId.value = m.id
    router.replace({ query: { tab: 'multi', match: m.code } })
    await refreshMatch()
    matchUnsub = cw.subscribe(m.id, refreshMatch)
  } catch (e: any) { toast.error(e?.message ?? 'Could not create room') }
  finally { creatingRoom.value = false }
}

async function handleJoinRoom() {
  if (!joinCode.value.trim()) return
  joiningRoom.value = true
  try {
    const m = await cw.joinByCode(joinCode.value.trim())
    activeMatchId.value = m.id
    router.replace({ query: { tab: 'multi', match: m.code } })
    await refreshMatch()
    matchUnsub = cw.subscribe(m.id, refreshMatch)
  } catch (e: any) { toast.error(e?.message ?? 'Could not join room') }
  finally { joiningRoom.value = false }
}

async function handleLeaveRoom() {
  if (activeMatchId.value && matchMatch.value?.status === 'pending') {
    try { await cw.leave(activeMatchId.value) } catch {}
  }
  if (matchUnsub) { matchUnsub(); matchUnsub = null }
  stopMatchTimer()
  activeMatchId.value = null
  matchBoard.value = null
  multiGrid.value = []
  joinCode.value = ''
}

async function handleStartMatch() {
  if (!activeMatchId.value) return
  try { await cw.start(activeMatchId.value); await refreshMatch() }
  catch (e: any) { toast.error(e?.message ?? 'Could not start') }
}

async function handleMatchJoin() {
  if (!matchMatch.value) return
  try { await cw.joinByCode(matchMatch.value.code); await refreshMatch() }
  catch (e: any) { toast.error(e?.message ?? 'Could not join') }
}

async function submitMultiSolution() {
  if (!activeMatchId.value) return
  submittingMulti.value = true
  const elapsed = Math.floor((Date.now() - multiStartTime.value) / 1000)
  try {
    const res = await cw.submit(activeMatchId.value, multiGrid.value, elapsed)
    if ('correct' in res && !res.correct) {
      toast.error('Not correct yet — keep trying!')
    } else {
      matchBoard.value = res as CrosswordMatchBoard
      const mp = (res as CrosswordMatchBoard).players?.find(p => p.user_id === me.value)
      if (mp?.won) toast.success(`Correct! +${mp.points_awarded} points`)
    }
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
  if (activeTab.value === 'daily') loadDailyPuzzle()
  if (joinCode.value) handleJoinRoom()
})

onBeforeUnmount(() => {
  if (dailyTimerInterval) clearInterval(dailyTimerInterval)
  if (matchUnsub) matchUnsub()
  stopMatchTimer()
})

watch(activeTab, (tab) => { if (tab === 'daily' && !puzzle.value) loadDailyPuzzle() })
</script>

<template>
  <div class="max-w-3xl mx-auto pb-10">
    <input ref="hiddenInputRef" type="text" autocomplete="off" autocapitalize="characters" autocorrect="off" spellcheck="false"
      class="fixed opacity-0 pointer-events-none w-px h-px"
      style="top:-100px;left:0;z-index:-1;"
      @input="handleHiddenInput"
      @keydown="handleHiddenKeydown" />

    <header class="text-center mb-6">
      <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-sky-50 border border-sky-200 text-[11px] font-semibold uppercase tracking-[0.2em] text-sky-700">
        <span class="w-1.5 h-1.5 rounded-full bg-sky-500"></span>
        Word puzzle
      </div>
      <h1 class="mt-3 text-2xl sm:text-4xl font-bold text-slate-900 tracking-tight">Mini Crossword</h1>
      <p class="mt-1 text-xs sm:text-sm text-slate-500 max-w-md mx-auto">Fill the 5x5 grid using the clues. Tap a cell to start typing, tap it again to switch direction.</p>
    </header>

    <div class="flex gap-1 mb-6 p-1 rounded-xl bg-slate-100 max-w-xs mx-auto">
      <button type="button" class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg transition-all"
        :class="activeTab === 'daily' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
        @click="activeTab = 'daily'">Daily</button>
      <button type="button" class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg transition-all"
        :class="activeTab === 'multiplayer' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
        @click="activeTab = 'multiplayer'">Multiplayer</button>
    </div>

    <!-- DAILY -->
    <div v-if="activeTab === 'daily'">
      <div v-if="loadingDaily" class="text-center text-sm text-slate-400 py-10">Loading puzzle...</div>
      <div v-else-if="puzzle" class="space-y-5">
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold text-slate-500 uppercase tracking-wide">Time: {{ formatTime(dailyTime) }}</span>
          <span v-if="dailyCompleted" class="px-3 py-1 rounded-full bg-emerald-100 text-emerald-700 text-xs font-bold">Complete!</span>
          <div v-else class="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-slate-100">
            <span class="w-2 h-2 rounded-full" :class="direction === 'across' ? 'bg-sky-500' : 'bg-violet-500'"></span>
            <span class="text-[11px] font-semibold text-slate-600 uppercase">{{ direction }}</span>
          </div>
        </div>

        <div v-if="currentClue && !dailyCompleted" class="rounded-xl bg-sky-50 border border-sky-200 px-4 py-2.5 text-sm text-sky-800">
          <span class="font-bold mr-1.5">{{ currentClue.number }} {{ direction }}:</span>{{ currentClue.clue }}
        </div>

        <div class="flex justify-center outline-none" tabindex="0" @keydown="handleGridKeydown" @click="hiddenInputRef?.focus()">
          <div class="inline-grid gap-0.5 bg-slate-900 p-0.5 rounded-lg select-none" style="grid-template-columns: repeat(5, 1fr)">
            <template v-for="r in 5" :key="'r'+r">
              <template v-for="c in 5" :key="'c'+r+c">
                <div v-if="isBlocked(r-1, c-1, puzzle.grid)" class="w-12 h-12 sm:w-14 sm:h-14 bg-slate-900"></div>
                <div v-else
                  class="w-12 h-12 sm:w-14 sm:h-14 relative cursor-pointer flex items-center justify-center text-lg font-bold transition-colors"
                  :class="[
                    isSelected(r-1, c-1) ? 'bg-sky-300' : highlightedCells().has((r-1)+','+(c-1)) ? 'bg-sky-100' : 'bg-white',
                    dailyCompleted ? 'text-emerald-700' : 'text-slate-900'
                  ]"
                  @click="selectCell(r-1, c-1)">
                  <span v-if="cellNumber(r-1, c-1)" class="absolute top-0.5 left-1 text-[9px] font-semibold text-slate-400 leading-none">{{ cellNumber(r-1, c-1) }}</span>
                  {{ playerGrid[r-1]?.[c-1] ?? '' }}
                </div>
              </template>
            </template>
          </div>
        </div>

        <div class="grid sm:grid-cols-2 gap-4">
          <div class="card p-4">
            <h3 class="text-xs font-bold text-slate-900 uppercase tracking-wide mb-2">Across</h3>
            <ul class="space-y-1.5">
              <li v-for="cl in puzzle.clues_across" :key="'a'+cl.number"
                class="text-sm px-2 py-1 rounded-lg cursor-pointer transition-colors"
                :class="currentClue?.number === cl.number && direction === 'across' ? 'bg-sky-100 text-sky-900' : 'text-slate-700 hover:bg-slate-50'"
                @click="selectedCell = [cl.row, cl.col]; direction = 'across'; hiddenInputRef?.focus()">
                <span class="font-bold text-slate-500 mr-1">{{ cl.number }}.</span>{{ cl.clue }}
              </li>
            </ul>
          </div>
          <div class="card p-4">
            <h3 class="text-xs font-bold text-slate-900 uppercase tracking-wide mb-2">Down</h3>
            <ul class="space-y-1.5">
              <li v-for="cl in puzzle.clues_down" :key="'d'+cl.number"
                class="text-sm px-2 py-1 rounded-lg cursor-pointer transition-colors"
                :class="currentClue?.number === cl.number && direction === 'down' ? 'bg-violet-100 text-violet-900' : 'text-slate-700 hover:bg-slate-50'"
                @click="selectedCell = [cl.row, cl.col]; direction = 'down'; hiddenInputRef?.focus()">
                <span class="font-bold text-slate-500 mr-1">{{ cl.number }}.</span>{{ cl.clue }}
              </li>
            </ul>
          </div>
        </div>

        <button v-if="!dailyCompleted" type="button" class="btn-primary w-full justify-center" :disabled="checking" @click="checkDailySolution">
          {{ checking ? 'Checking...' : 'Check Solution' }}
        </button>
      </div>
    </div>

    <!-- MULTIPLAYER -->
    <div v-else>
      <template v-if="activeMatchId && matchBoard && matchMatch">
        <header class="rounded-2xl border border-sky-200 bg-gradient-to-br from-sky-50 to-amber-50 p-5 mb-5">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div class="text-[11px] uppercase tracking-wider text-sky-700 font-bold">Crossword Race</div>
              <h2 class="text-xl font-bold text-slate-900">Multiplayer Room</h2>
              <p class="text-sm text-slate-600">
                <span v-if="matchMatch.status === 'pending'">Lobby. {{ matchPlayers.length }} joined.</span>
                <span v-else-if="matchMatch.status === 'active'">Race to complete the grid!</span>
                <span v-else-if="matchMatch.status === 'finished' && hasMoreRounds">Round {{ (matchMatch as any).current_round }} of {{ (matchMatch as any).total_rounds }} complete. Next round up!</span>
                <span v-if="matchMatch && ((matchMatch as any).total_rounds ?? 1) > 1" class="block text-[11px] mt-1 font-semibold text-sky-700">Round {{ (matchMatch as any).current_round ?? 1 }} of {{ (matchMatch as any).total_rounds ?? 1 }}</span>
                <span v-else>Race complete.</span>
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
              <div class="h-full rounded-full transition-all duration-1000" :class="timerUrgent ? 'bg-red-500' : timerWarning ? 'bg-amber-400' : 'bg-sky-500'"
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
                  <span v-if="p.user_id === matchMatch.host_user_id" class="text-[11px] uppercase text-sky-700 font-bold ml-1">Host</span>
                </span>
              </li>
            </ul>
          </article>
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
              <button v-if="isHost" type="button" class="text-sm px-4 py-2 rounded-full bg-sky-600 text-white font-semibold disabled:opacity-40" :disabled="matchPlayers.length < 1" @click="handleStartMatch">Start</button>
            </div>
          </div>
        </div>

        <!-- Active game -->
        <div v-else-if="matchMatch.status === 'active' && matchBoard.puzzle" class="grid lg:grid-cols-[1fr_280px] gap-5 items-start">
          <div class="space-y-4">
            <div v-if="currentClue" class="rounded-xl bg-sky-50 border border-sky-200 px-4 py-2.5 text-sm text-sky-800">
              <span class="font-bold mr-1.5">{{ currentClue.number }} {{ direction }}:</span>{{ currentClue.clue }}
            </div>
            <div class="card p-4">
              <div class="flex justify-center outline-none" tabindex="0" @keydown="handleGridKeydown" @click="hiddenInputRef?.focus()">
                <div class="inline-grid gap-0.5 bg-slate-900 p-0.5 rounded-lg select-none" style="grid-template-columns: repeat(5, 1fr)">
                  <template v-for="r in 5" :key="'mr'+r">
                    <template v-for="c in 5" :key="'mc'+r+c">
                      <div v-if="isBlocked(r-1, c-1, matchBoard.puzzle.grid)" class="w-11 h-11 sm:w-13 sm:h-13 bg-slate-900"></div>
                      <div v-else class="w-11 h-11 sm:w-13 sm:h-13 relative cursor-pointer flex items-center justify-center text-base font-bold transition-colors"
                        :class="isSelected(r-1, c-1) ? 'bg-sky-300' : highlightedCells().has((r-1)+','+(c-1)) ? 'bg-sky-100' : 'bg-white'"
                        @click="selectCell(r-1, c-1)">
                        <span v-if="cellNumber(r-1, c-1)" class="absolute top-0.5 left-0.5 text-[8px] font-semibold text-slate-400 leading-none">{{ cellNumber(r-1, c-1) }}</span>
                        {{ multiGrid[r-1]?.[c-1] ?? '' }}
                      </div>
                    </template>
                  </template>
                </div>
              </div>
            </div>
            <div class="grid sm:grid-cols-2 gap-3">
              <div class="card p-3">
                <h3 class="text-[10px] font-bold text-slate-900 uppercase tracking-wide mb-1">Across</h3>
                <ul class="space-y-1">
                  <li v-for="cl in matchBoard.puzzle.clues_across" :key="'ma'+cl.number"
                    class="text-xs px-2 py-0.5 rounded cursor-pointer transition-colors"
                    :class="currentClue?.number === cl.number && direction === 'across' ? 'bg-sky-100 text-sky-900' : 'text-slate-700 hover:bg-slate-50'"
                    @click="selectedCell = [cl.row, cl.col]; direction = 'across'; hiddenInputRef?.focus()">
                    <span class="font-bold text-slate-500 mr-1">{{ cl.number }}.</span>{{ cl.clue }}
                  </li>
                </ul>
              </div>
              <div class="card p-3">
                <h3 class="text-[10px] font-bold text-slate-900 uppercase tracking-wide mb-1">Down</h3>
                <ul class="space-y-1">
                  <li v-for="cl in matchBoard.puzzle.clues_down" :key="'md'+cl.number"
                    class="text-xs px-2 py-0.5 rounded cursor-pointer transition-colors"
                    :class="currentClue?.number === cl.number && direction === 'down' ? 'bg-violet-100 text-violet-900' : 'text-slate-700 hover:bg-slate-50'"
                    @click="selectedCell = [cl.row, cl.col]; direction = 'down'; hiddenInputRef?.focus()">
                    <span class="font-bold text-slate-500 mr-1">{{ cl.number }}.</span>{{ cl.clue }}
                  </li>
                </ul>
              </div>
            </div>
            <button v-if="myPlayer && !myPlayer.completed" type="button" class="btn-primary w-full justify-center" :disabled="submittingMulti" @click="submitMultiSolution">
              {{ submittingMulti ? 'Checking...' : 'Submit Solution' }}
            </button>
            <div v-else-if="myPlayer?.completed && matchMatch.status === 'active'" class="card p-5 text-center text-emerald-700 font-semibold">
              You finished! Waiting for others...
            </div>
          </div>
          <aside class="rounded-2xl border border-slate-200 bg-white p-4 space-y-3 lg:sticky lg:top-4">
            <h3 class="text-sm font-bold text-slate-900">Live board</h3>
            <ol class="space-y-2">
              <li v-for="p in matchPlayers" :key="p.user_id" class="flex items-center justify-between text-xs">
                <span class="truncate font-medium text-slate-800">
                  {{ p.full_name ?? 'Team member' }}
                  <span v-if="p.user_id === me" class="text-[10px] text-sky-700 font-bold ml-1">You</span>
                </span>
                <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold"
                  :class="p.won ? 'bg-emerald-100 text-emerald-800' : p.status === 'playing' ? 'bg-sky-100 text-sky-800' : 'bg-slate-200 text-slate-600'">
                  {{ p.won ? `Done (${formatTime(p.time_seconds)})` : 'Working...' }}
                </span>
              </li>
            </ol>
            <button type="button" class="w-full text-xs px-3 py-2 rounded-full bg-white border border-slate-300 text-slate-700" @click="handleLeaveRoom">Leave</button>
          </aside>
        </div>

        <!-- Finished with Podium -->
        <div v-else-if="matchMatch.status === 'finished'" class="space-y-5">
          <article class="card p-6 text-center" :class="myPlayer?.won ? 'border-emerald-200 bg-emerald-50' : 'border-amber-200 bg-amber-50'">
            <div v-if="!matchMatch.winner_user_id && matchMatch.time_limit_seconds" class="text-red-600 font-bold text-sm uppercase tracking-wide mb-2">Time's Up!</div>
            <h2 class="text-lg font-bold" :class="myPlayer?.won ? 'text-emerald-800' : 'text-slate-800'">{{ myPlayer?.won ? 'You completed it!' : 'Race Over' }}</h2>
            <p v-if="myPlayer?.points_awarded" class="text-sm mt-1 text-emerald-600">+{{ myPlayer.points_awarded }} points</p>
          </article>

          <article v-if="rankedPlayers.length >= 1" class="card p-6">
            <h3 class="text-sm font-bold text-slate-900 text-center mb-6">{{ seriesComplete && ((matchMatch as any)?.total_rounds ?? 1) > 1 ? 'Series Podium' : (((matchMatch as any)?.total_rounds ?? 1) > 1 ? 'Round ' + ((matchMatch as any)?.current_round ?? 1) + ' Podium' : 'Podium') }}</h3>
            <div class="flex items-end justify-center gap-3 max-w-sm mx-auto">
              <div v-if="rankedPlayers[1]" class="flex flex-col items-center flex-1">
                <div class="w-10 h-10 rounded-full bg-slate-200 flex items-center justify-center text-sm font-bold text-slate-700 mb-2">{{ rankedPlayers[1].full_name?.charAt(0) ?? '?' }}</div>
                <p class="text-[11px] font-semibold text-slate-700 text-center truncate max-w-[80px]">{{ rankedPlayers[1].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-slate-500">{{ seriesPts(rankedPlayers[1]) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-slate-200 flex items-end justify-center" style="height: 60px;"><span class="text-lg font-bold text-slate-600 mb-2">2</span></div>
              </div>
              <div v-if="rankedPlayers[0]" class="flex flex-col items-center flex-1">
                <div class="w-12 h-12 rounded-full bg-amber-100 border-2 border-amber-300 flex items-center justify-center text-base font-bold text-amber-700 mb-2">{{ rankedPlayers[0].full_name?.charAt(0) ?? '?' }}</div>
                <p class="text-xs font-bold text-slate-900 text-center truncate max-w-[80px]">{{ rankedPlayers[0].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-amber-700 font-semibold">{{ seriesPts(rankedPlayers[0]) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-amber-100 border-2 border-amber-200 flex items-end justify-center" style="height: 90px;"><span class="text-2xl mb-2">&#x1F3C6;</span></div>
              </div>
              <div v-if="rankedPlayers[2]" class="flex flex-col items-center flex-1">
                <div class="w-10 h-10 rounded-full bg-orange-100 flex items-center justify-center text-sm font-bold text-orange-700 mb-2">{{ rankedPlayers[2].full_name?.charAt(0) ?? '?' }}</div>
                <p class="text-[11px] font-semibold text-slate-700 text-center truncate max-w-[80px]">{{ rankedPlayers[2].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-slate-500">{{ seriesPts(rankedPlayers[2]) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-orange-100 flex items-end justify-center" style="height: 40px;"><span class="text-lg font-bold text-orange-600 mb-2">3</span></div>
              </div>
            </div>
            <ol v-if="rankedPlayers.length > 3" class="mt-5 space-y-1.5 border-t border-slate-100 pt-4">
              <li v-for="(p, i) in rankedPlayers.slice(3)" :key="p.user_id" class="flex items-center gap-3 text-xs px-3 py-1.5 rounded-lg" :class="p.user_id === me ? 'bg-sky-50 border border-sky-200' : 'bg-slate-50'">
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
          <div class="w-14 h-14 mx-auto rounded-full bg-sky-100 text-sky-700 flex items-center justify-center mb-4 text-2xl font-bold">#</div>
          <h2 class="text-lg font-semibold text-slate-900">Multiplayer Crossword Race</h2>
          <p class="text-sm text-slate-500 mt-1 max-w-sm mx-auto">Everyone solves the same 5x5 puzzle. First to complete it correctly wins!</p>
          <div class="mt-5 max-w-xs mx-auto">
            <label class="block text-xs font-semibold text-slate-600 uppercase tracking-wide mb-2 text-left">Timer</label>
            <div class="grid grid-cols-5 gap-1.5">
              <button v-for="opt in [{ label: 'None', value: null }, { label: '60s', value: 60 }, { label: '90s', value: 90 }, { label: '2m', value: 120 }, { label: '5m', value: 300 }]"
                :key="String(opt.value)" type="button"
                class="px-2 py-1.5 text-xs font-semibold rounded-lg border transition-all"
                :class="selectedTimeLimit === opt.value ? 'bg-sky-600 text-white border-sky-600' : 'bg-white text-slate-600 border-slate-200 hover:border-sky-300'"
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
