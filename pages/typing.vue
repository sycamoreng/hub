<script setup lang="ts">
import { useTypingGame, TYPING_MODES, type TypingMode, type TypingCategory, type TypingPrompt, type TypingRun } from '~/composables/useTypingGame'

const toast = useToast()
const { loadCategories, loadPrompts, submitRun, loadMyRuns, loadMyBest, loadLeaderboard, createMatch, joinMatch, loadMatchByCode } = useTypingGame()
const route = useRoute()
const router = useRouter()

type Phase = 'idle' | 'running' | 'finished'

const categories = ref<TypingCategory[]>([])
const prompts = ref<TypingPrompt[]>([])
const myRuns = ref<TypingRun[]>([])
const myBest = ref<Record<TypingMode, number>>({ timed_30s: 0, timed_60s: 0, timed_120s: 0, sprint: 0 })
const leaderboard = ref<any[]>([])

const selectedCategoryId = ref<string>('')
const selectedMode = ref<TypingMode>('timed_60s')
const lengthTier = ref<'' | 'short' | 'medium' | 'long'>('')
const leaderboardMode = ref<TypingMode>('timed_60s')

const phase = ref<Phase>('idle')
const targetText = ref<string>('')
const typed = ref<string>('')
const startedAt = ref<number>(0)
const elapsedMs = ref<number>(0)
const errors = ref<number>(0)
const correctChars = ref<number>(0)
const lastResult = ref<{ wpm: number; accuracy: number; points: number; isPb: boolean } | null>(null)

let tickHandle: number | null = null

// ----- Multiplayer state -----
const activeMatchId = ref<string>('')
const joinCode = ref('')
const creatingMatch = ref(false)
const joiningMatch = ref(false)

async function hostMatch() {
  creatingMatch.value = true
  try {
    const m = await createMatch({
      categoryId: selectedCategoryId.value || null,
      promptId: null,
      mode: selectedMode.value
    })
    activeMatchId.value = m.id
    await router.replace({ query: { ...route.query, match: m.code } })
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not create match')
  } finally {
    creatingMatch.value = false
  }
}

async function joinByCode() {
  const code = joinCode.value.trim().toUpperCase()
  if (!code) return
  joiningMatch.value = true
  try {
    const m = await joinMatch(code)
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
    const m = await loadMatchByCode(code)
    if (!m) return
    if (m.status === 'pending') {
      const joined = await joinMatch(code)
      activeMatchId.value = joined.id
    } else {
      activeMatchId.value = m.id
    }
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not open match')
  }
}

async function loadAll() {
  const [cats, runs, best, lb] = await Promise.all([
    loadCategories(),
    loadMyRuns(10),
    loadMyBest(),
    loadLeaderboard({ mode: leaderboardMode.value })
  ])
  categories.value = cats
  myRuns.value = runs
  myBest.value = best
  leaderboard.value = lb
  if (!selectedCategoryId.value && cats.length) selectedCategoryId.value = cats[0].id
  await refreshPrompts()
}

async function refreshPrompts() {
  prompts.value = await loadPrompts({
    categoryId: selectedCategoryId.value || undefined,
    tier: lengthTier.value || undefined
  })
}

watch([selectedCategoryId, lengthTier], refreshPrompts)
watch(leaderboardMode, async () => {
  leaderboard.value = await loadLeaderboard({ mode: leaderboardMode.value })
})

onMounted(async () => { await loadAll(); await tryEnterFromQuery() })

function pickPrompt() {
  if (!prompts.value.length) {
    toast.error('No prompts available for this filter.')
    return ''
  }
  const idx = Math.floor(Math.random() * prompts.value.length)
  return prompts.value[idx].text
}

function durationFor(mode: TypingMode): number {
  const m = TYPING_MODES.find(x => x.id === mode)
  return m?.durationMs ?? 60_000
}

function start() {
  const text = pickPrompt()
  if (!text) return
  targetText.value = text
  typed.value = ''
  errors.value = 0
  correctChars.value = 0
  elapsedMs.value = 0
  startedAt.value = performance.now()
  phase.value = 'running'
  lastResult.value = null
  nextTick(() => (document.getElementById('typing-input') as HTMLTextAreaElement)?.focus())

  if (tickHandle) cancelAnimationFrame(tickHandle)
  const tick = () => {
    if (phase.value !== 'running') return
    elapsedMs.value = performance.now() - startedAt.value
    const dur = durationFor(selectedMode.value)
    if (dur > 0 && elapsedMs.value >= dur) {
      finish('timeout')
      return
    }
    tickHandle = requestAnimationFrame(tick)
  }
  tickHandle = requestAnimationFrame(tick)
}

function onInput(e: Event) {
  if (phase.value !== 'running') return
  const value = (e.target as HTMLTextAreaElement).value
  typed.value = value
  // Recompute counters for the typed prefix vs target
  let mistakes = 0
  let correct = 0
  for (let i = 0; i < value.length; i++) {
    if (i >= targetText.value.length) { mistakes++; continue }
    if (value[i] === targetText.value[i]) correct++
    else mistakes++
  }
  errors.value = mistakes
  correctChars.value = correct
  if (selectedMode.value === 'sprint' && value === targetText.value) finish('sprint_complete')
}

function calcResult() {
  const minutes = Math.max(0.05, elapsedMs.value / 60_000)
  const wpm = Math.round((correctChars.value / 5) / minutes * 100) / 100
  const totalPressed = correctChars.value + errors.value
  const accuracy = totalPressed === 0 ? 0 : Math.round((correctChars.value / totalPressed) * 10000) / 100
  return { wpm, accuracy }
}

async function finish(_why: string) {
  if (phase.value !== 'running') return
  phase.value = 'finished'
  if (tickHandle) cancelAnimationFrame(tickHandle)
  const { wpm, accuracy } = calcResult()
  const wordsTyped = correctChars.value === 0 ? 0 : Math.floor(correctChars.value / 5)
  try {
    const res = await submitRun({
      categoryId: selectedCategoryId.value || null,
      mode: selectedMode.value,
      wpm,
      accuracy,
      charactersTyped: typed.value.length,
      wordsTyped,
      errors: errors.value,
      durationMs: Math.round(elapsedMs.value)
    })
    lastResult.value = { wpm, accuracy, points: res.points_awarded, isPb: res.is_personal_best }
    if (res.is_personal_best) toast.success(`New personal best: ${wpm} WPM`)
    else if (res.points_awarded > 0) toast.success(`+${res.points_awarded} points · ${wpm} WPM`)
    else toast.info(`Run saved · ${wpm} WPM`)
    const [runs, best, lb] = await Promise.all([
      loadMyRuns(10),
      loadMyBest(),
      loadLeaderboard({ mode: leaderboardMode.value })
    ])
    myRuns.value = runs
    myBest.value = best
    leaderboard.value = lb
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not save run')
  }
}

function reset() {
  phase.value = 'idle'
  typed.value = ''
  targetText.value = ''
  errors.value = 0
  correctChars.value = 0
  elapsedMs.value = 0
  lastResult.value = null
  if (tickHandle) cancelAnimationFrame(tickHandle)
}

const remainingMs = computed(() => {
  if (selectedMode.value === 'sprint') return 0
  return Math.max(0, durationFor(selectedMode.value) - elapsedMs.value)
})

const live = computed(() => calcResult())

const targetChars = computed(() => targetText.value.split(''))

function charClass(i: number): string {
  if (i >= typed.value.length) {
    return i === typed.value.length && phase.value === 'running' ? 'bg-sycamore-100 rounded text-sycamore-900' : 'text-slate-400'
  }
  if (typed.value[i] === targetText.value[i]) return 'text-emerald-700'
  return 'bg-rose-100 text-rose-700 rounded'
}

function formatTime(ms: number): string {
  const s = Math.max(0, ms) / 1000
  return s < 10 ? s.toFixed(1) + 's' : Math.round(s) + 's'
}

function modeLabel(m: TypingMode) {
  return TYPING_MODES.find(x => x.id === m)?.label ?? m
}

function dateShort(s: string): string {
  if (!s) return ''
  const d = new Date(s)
  return d.toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })
}

onBeforeUnmount(() => { if (tickHandle) cancelAnimationFrame(tickHandle) })
</script>

<template>
  <div class="space-y-6 max-w-5xl mx-auto">
    <header class="card p-6 sm:p-8 bg-gradient-to-br from-sycamore-50 to-leaf-50 border-sycamore-200">
      <div class="flex items-center gap-3">
        <div class="w-12 h-12 rounded-xl bg-sycamore-600 text-white flex items-center justify-center font-bold text-xl">TS</div>
        <div>
          <h1 class="section-title">Typing Sprint</h1>
          <p class="section-subtitle">Type the prompt as quickly and accurately as you can. Earn leaderboard points for every solid run.</p>
        </div>
      </div>
    </header>

    <TypingMatchRoom v-if="activeMatchId" :match-id="activeMatchId" @leave="leaveMatch" />

    <template v-else>
    <section class="card p-5 flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-sm font-bold text-slate-900">Race a teammate</h2>
        <p class="text-xs text-slate-500">Host a match with the current category and mode, or join one with a code.</p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <input v-model="joinCode" placeholder="Code" maxlength="8" class="input !w-32 uppercase tracking-widest font-mono" />
        <button class="btn-secondary text-sm" :disabled="joiningMatch || !joinCode.trim()" @click="joinByCode">
          {{ joiningMatch ? 'Joining...' : 'Join match' }}
        </button>
        <button class="btn-primary text-sm" :disabled="creatingMatch || !prompts.length" @click="hostMatch">
          {{ creatingMatch ? 'Creating...' : 'Host new match' }}
        </button>
      </div>
    </section>

    <section class="card p-5 sm:p-6 space-y-4">
      <div class="grid sm:grid-cols-3 gap-3">
        <label class="block text-xs font-medium text-slate-600">
          <span class="block mb-1 uppercase tracking-wide">Category</span>
          <select v-model="selectedCategoryId" class="input" :disabled="phase === 'running'">
            <option v-for="c in categories" :key="c.id" :value="c.id">{{ c.name }}</option>
          </select>
        </label>
        <label class="block text-xs font-medium text-slate-600">
          <span class="block mb-1 uppercase tracking-wide">Mode</span>
          <select v-model="selectedMode" class="input" :disabled="phase === 'running'">
            <option v-for="m in TYPING_MODES" :key="m.id" :value="m.id">{{ m.label }}</option>
          </select>
        </label>
        <label class="block text-xs font-medium text-slate-600">
          <span class="block mb-1 uppercase tracking-wide">Length</span>
          <select v-model="lengthTier" class="input" :disabled="phase === 'running'">
            <option value="">Any length</option>
            <option value="short">Short</option>
            <option value="medium">Medium</option>
            <option value="long">Long</option>
          </select>
        </label>
      </div>

      <div v-if="phase === 'idle'" class="rounded-xl border border-dashed border-slate-300 p-6 text-center">
        <p class="text-sm text-slate-500 mb-3">Pick your settings, then click below to start. The timer begins on your first keystroke after Start.</p>
        <button class="btn-primary" @click="start" :disabled="!prompts.length">{{ prompts.length ? 'Start typing' : 'No prompts available' }}</button>
      </div>

      <div v-if="phase !== 'idle'" class="space-y-4">
        <div class="grid grid-cols-4 gap-2 text-center">
          <div class="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <div class="text-[10px] uppercase tracking-wide text-slate-500">{{ selectedMode === 'sprint' ? 'Elapsed' : 'Time left' }}</div>
            <div class="text-xl font-bold text-slate-900 tabular-nums">
              {{ selectedMode === 'sprint' ? formatTime(elapsedMs) : formatTime(remainingMs) }}
            </div>
          </div>
          <div class="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <div class="text-[10px] uppercase tracking-wide text-slate-500">WPM</div>
            <div class="text-xl font-bold text-sycamore-700 tabular-nums">{{ live.wpm }}</div>
          </div>
          <div class="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <div class="text-[10px] uppercase tracking-wide text-slate-500">Accuracy</div>
            <div class="text-xl font-bold text-slate-900 tabular-nums">{{ live.accuracy.toFixed(0) }}%</div>
          </div>
          <div class="rounded-xl border border-slate-200 bg-slate-50 p-3">
            <div class="text-[10px] uppercase tracking-wide text-slate-500">Errors</div>
            <div class="text-xl font-bold tabular-nums" :class="errors === 0 ? 'text-emerald-700' : 'text-rose-700'">{{ errors }}</div>
          </div>
        </div>

        <div class="rounded-2xl border border-slate-200 bg-white p-5 sm:p-6 font-mono text-lg sm:text-xl leading-relaxed select-none">
          <span v-for="(c, i) in targetChars" :key="i" :class="charClass(i)">{{ c }}</span>
        </div>

        <textarea
          id="typing-input"
          :value="typed"
          @input="onInput"
          rows="3"
          autocapitalize="off"
          spellcheck="false"
          autocomplete="off"
          class="input font-mono text-base resize-none"
          :placeholder="phase === 'running' ? 'Start typing...' : ''"
          :disabled="phase !== 'running'"
        ></textarea>

        <div class="flex flex-wrap items-center gap-2 justify-end">
          <button v-if="phase === 'running'" class="btn-secondary" @click="finish('manual')">Stop</button>
          <button v-if="phase === 'finished'" class="btn-secondary" @click="reset">New run</button>
          <button v-if="phase === 'finished'" class="btn-primary" @click="start">Try another</button>
        </div>

        <div v-if="lastResult && phase === 'finished'"
             class="rounded-xl border bg-leaf-50 border-leaf-200 p-4 text-sm text-leaf-900">
          <div class="font-semibold">
            <span v-if="lastResult.isPb">New personal best.</span>
            <span v-else-if="lastResult.points > 0">Run saved.</span>
            <span v-else>Run saved (no points — keep accuracy at or above 80%).</span>
          </div>
          <div class="text-leaf-800/80">
            {{ lastResult.wpm }} WPM · {{ lastResult.accuracy.toFixed(0) }}% accuracy
            <span v-if="lastResult.points > 0">· +{{ lastResult.points }} points</span>
          </div>
        </div>
      </div>
    </section>

    <section class="grid lg:grid-cols-2 gap-4">
      <article class="card p-5">
        <header class="flex items-center justify-between mb-3">
          <h2 class="text-base font-bold text-slate-900">Your personal bests</h2>
        </header>
        <ul class="divide-y divide-slate-100">
          <li v-for="m in TYPING_MODES" :key="m.id" class="flex items-center justify-between py-2.5 text-sm">
            <span class="text-slate-700">{{ m.label }}</span>
            <span class="font-bold text-slate-900 tabular-nums">{{ Number(myBest[m.id] ?? 0).toFixed(1) }} <span class="text-xs font-normal text-slate-500">WPM</span></span>
          </li>
        </ul>
      </article>

      <article class="card p-5">
        <header class="flex items-center justify-between mb-3 gap-2 flex-wrap">
          <h2 class="text-base font-bold text-slate-900">Leaderboard</h2>
          <select v-model="leaderboardMode" class="input !py-1 !px-2 text-xs max-w-[160px]">
            <option v-for="m in TYPING_MODES" :key="m.id" :value="m.id">{{ m.label }}</option>
          </select>
        </header>
        <ol v-if="leaderboard.length" class="space-y-2">
          <li v-for="(row, i) in leaderboard.slice(0, 10)" :key="row.id" class="flex items-center justify-between text-sm">
            <div class="flex items-center gap-3 min-w-0">
              <span class="w-6 text-right text-xs font-bold text-slate-400 tabular-nums">{{ i + 1 }}</span>
              <span class="truncate font-medium text-slate-800">{{ row.profile?.full_name ?? 'Team member' }}</span>
            </div>
            <span class="font-bold text-sycamore-700 tabular-nums">{{ Number(row.wpm).toFixed(1) }} WPM</span>
          </li>
        </ol>
        <div v-else class="text-sm text-slate-500">No runs yet for this mode. Be the first to set a benchmark.</div>
      </article>
    </section>

    <section class="card p-5 overflow-x-auto">
      <h2 class="text-base font-bold text-slate-900 mb-3">Recent runs</h2>
      <div v-if="myRuns.length === 0" class="text-sm text-slate-500">You haven't completed any runs yet.</div>
      <table v-else class="min-w-full text-xs sm:text-sm">
        <thead class="text-[10px] sm:text-xs uppercase tracking-wide text-slate-500">
          <tr>
            <th class="text-left py-2">When</th>
            <th class="text-left py-2">Mode</th>
            <th class="text-right py-2">WPM</th>
            <th class="text-right py-2">Accuracy</th>
            <th class="text-right py-2">Errors</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="r in myRuns" :key="r.id">
            <td class="py-2 text-slate-600">{{ dateShort(r.finished_at) }}</td>
            <td class="py-2 text-slate-600">{{ modeLabel(r.mode) }}</td>
            <td class="py-2 text-right font-semibold text-slate-900 tabular-nums">{{ Number(r.wpm).toFixed(1) }}</td>
            <td class="py-2 text-right tabular-nums" :class="r.accuracy >= 90 ? 'text-emerald-700' : 'text-slate-600'">{{ Number(r.accuracy).toFixed(0) }}%</td>
            <td class="py-2 text-right tabular-nums text-slate-600">{{ r.errors }}</td>
          </tr>
        </tbody>
      </table>
    </section>
    </template>
  </div>
</template>
