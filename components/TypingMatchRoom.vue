<script setup lang="ts">
import { useTypingGame, TYPING_MODES } from '~/composables/useTypingGame'
import { useSupabase } from '~/utils/supabase'

const props = defineProps<{ matchId: string }>()
const emit = defineEmits<{ (e: 'leave'): void }>()

const supabase = useSupabase()
const toast = useToast()
const {
  loadMatchById, loadMatchParticipants, subscribeMatch,
  startMatch, inviteToMatch, declineMatch, submitMatchRun, searchInvitees
} = useTypingGame()

const match = ref<any>(null)
const players = ref<any[]>([])
const me = ref<{ id: string } | null>(null)
const inviteTerm = ref('')
const inviteResults = ref<Array<{ auth_user_id: string; full_name: string; role: string }>>([])
const inviting = ref(false)

const typed = ref('')
const errors = ref(0)
const correctChars = ref(0)
const elapsedMs = ref(0)
const startEpochMs = ref(0)
const phase = ref<'lobby' | 'racing' | 'submitted'>('lobby')
const submitted = ref(false)
let raceTick: number | null = null
let unsubscribe: (() => void) | null = null

const isHost = computed(() => match.value && me.value && match.value.host_user_id === me.value.id)
const myPlayer = computed(() => players.value.find(p => p.user_id === me.value?.id) ?? null)
const joinedCount = computed(() => players.value.filter(p => p.status === 'joined' || p.status === 'finished').length)
const modeLabel = computed(() => TYPING_MODES.find(m => m.id === match.value?.mode)?.label ?? '')

async function refresh() {
  match.value = await loadMatchById(props.matchId)
  players.value = await loadMatchParticipants(props.matchId)
  if (match.value?.status === 'active' && phase.value === 'lobby' && !submitted.value) {
    beginRacing()
  }
  if (match.value?.status === 'finished' && phase.value !== 'submitted') {
    if (raceTick) cancelAnimationFrame(raceTick)
    phase.value = 'submitted'
  }
}

onMounted(async () => {
  const { data } = await supabase.auth.getUser()
  me.value = data.user ? { id: data.user.id } : null
  await refresh()
  unsubscribe = subscribeMatch(props.matchId, refresh)
})

onBeforeUnmount(() => {
  if (raceTick) cancelAnimationFrame(raceTick)
  if (unsubscribe) unsubscribe()
})

watch(inviteTerm, async () => {
  inviteResults.value = await searchInvitees(inviteTerm.value)
})

async function startSearch() {
  inviting.value = true
  inviteResults.value = await searchInvitees('')
}

async function invite(userId: string) {
  if (!match.value) return
  try {
    await inviteToMatch(match.value.id, userId)
    toast.success('Invited')
    await refresh()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not invite')
  }
}

async function copy(text: string, label: string) {
  try {
    await navigator.clipboard.writeText(text)
    toast.success(`${label} copied`)
  } catch {
    toast.error('Copy failed')
  }
}

async function hostStart() {
  if (!match.value) return
  try {
    await startMatch(match.value.id)
    await refresh()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not start')
  }
}

function beginRacing() {
  if (!match.value || phase.value === 'racing' || phase.value === 'submitted') return
  phase.value = 'racing'
  typed.value = ''
  errors.value = 0
  correctChars.value = 0
  startEpochMs.value = match.value.started_at ? new Date(match.value.started_at).getTime() : Date.now()
  elapsedMs.value = Math.max(0, Date.now() - startEpochMs.value)
  nextTick(() => (document.getElementById('match-typing-input') as HTMLTextAreaElement)?.focus())
  if (raceTick) cancelAnimationFrame(raceTick)
  const dur = durationMs(match.value.mode)
  const loop = () => {
    if (phase.value !== 'racing') return
    elapsedMs.value = Date.now() - startEpochMs.value
    if (dur > 0 && elapsedMs.value >= dur) {
      finishRun('timeout')
      return
    }
    raceTick = requestAnimationFrame(loop)
  }
  raceTick = requestAnimationFrame(loop)
}

function durationMs(mode: string): number {
  return TYPING_MODES.find(m => m.id === mode)?.durationMs ?? 60_000
}

function onInput(e: Event) {
  if (phase.value !== 'racing' || !match.value) return
  const value = (e.target as HTMLTextAreaElement).value
  typed.value = value
  let mistakes = 0
  let correct = 0
  const target = match.value.prompt_text ?? ''
  for (let i = 0; i < value.length; i++) {
    if (i >= target.length) { mistakes++; continue }
    if (value[i] === target[i]) correct++
    else mistakes++
  }
  errors.value = mistakes
  correctChars.value = correct
  if (match.value.mode === 'sprint' && value === target) finishRun('sprint_complete')
}

function calcResult() {
  const minutes = Math.max(0.05, elapsedMs.value / 60_000)
  const wpm = Math.round((correctChars.value / 5) / minutes * 100) / 100
  const total = correctChars.value + errors.value
  const accuracy = total === 0 ? 0 : Math.round((correctChars.value / total) * 10000) / 100
  return { wpm, accuracy }
}

const live = computed(() => calcResult())

const remainingMs = computed(() => {
  if (!match.value) return 0
  if (match.value.mode === 'sprint') return 0
  return Math.max(0, durationMs(match.value.mode) - elapsedMs.value)
})

async function finishRun(_reason: string) {
  if (!match.value || submitted.value) return
  submitted.value = true
  phase.value = 'submitted'
  if (raceTick) cancelAnimationFrame(raceTick)
  const { wpm, accuracy } = calcResult()
  const wordsTyped = correctChars.value === 0 ? 0 : Math.floor(correctChars.value / 5)
  try {
    const res = await submitMatchRun(match.value.id, {
      wpm, accuracy,
      charactersTyped: typed.value.length,
      wordsTyped,
      errors: errors.value,
      durationMs: Math.round(elapsedMs.value)
    }) as any
    const points = res?.run?.points_awarded ?? 0
    if (points > 0) toast.success(`+${points} points · ${wpm} WPM`)
    else toast.success(`Submitted: ${wpm} WPM`)
    await refresh()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not submit')
  }
}

async function leaveLobby() {
  if (!match.value) { emit('leave'); return }
  try {
    if (myPlayer.value && myPlayer.value.status !== 'finished' && match.value.host_user_id !== me.value?.id) {
      await declineMatch(match.value.id)
    }
  } finally {
    emit('leave')
  }
}

const promptChars = computed(() => (match.value?.prompt_text ?? '').split(''))

function charClass(i: number): string {
  if (!match.value) return ''
  const target = match.value.prompt_text ?? ''
  if (i >= typed.value.length) {
    return i === typed.value.length && phase.value === 'racing' ? 'bg-sycamore-100 rounded text-sycamore-900' : 'text-slate-400'
  }
  if (typed.value[i] === target[i]) return 'text-emerald-700'
  return 'bg-rose-100 text-rose-700 rounded'
}

function formatTime(ms: number): string {
  const s = Math.max(0, ms) / 1000
  return s < 10 ? s.toFixed(1) + 's' : Math.round(s) + 's'
}

const standings = computed(() => {
  return [...players.value].sort((a, b) => {
    if (a.status === 'finished' && b.status !== 'finished') return -1
    if (b.status === 'finished' && a.status !== 'finished') return 1
    return Number(b.wpm) - Number(a.wpm)
  })
})

function statusBadge(p: any): { label: string; cls: string } {
  if (p.status === 'finished') return { label: 'Finished', cls: 'bg-emerald-100 text-emerald-800' }
  if (p.status === 'invited') return { label: 'Invited', cls: 'bg-amber-100 text-amber-800' }
  if (p.status === 'declined') return { label: 'Declined', cls: 'bg-slate-100 text-slate-600' }
  if (match.value?.status === 'active') return { label: 'Racing', cls: 'bg-sky-100 text-sky-800' }
  return { label: 'Joined', cls: 'bg-slate-100 text-slate-700' }
}
</script>

<template>
  <section v-if="match" class="space-y-5">
    <header class="card p-5 sm:p-6 bg-gradient-to-br from-sycamore-50 to-leaf-50 border-sycamore-200">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div class="text-[11px] uppercase tracking-wider text-sycamore-700 font-bold">Match · {{ modeLabel }}</div>
          <h2 class="text-xl font-bold text-slate-900">Typing Sprint room</h2>
          <p class="text-sm text-slate-600">
            <span v-if="match.status === 'pending'">Waiting in the lobby. {{ joinedCount }} player(s) ready.</span>
            <span v-else-if="match.status === 'active'">Race in progress.</span>
            <span v-else>Race complete.</span>
          </p>
        </div>
        <div class="flex flex-col items-end gap-1">
          <div class="font-mono text-2xl font-bold tracking-widest text-slate-900">{{ match.code }}</div>
          <div class="flex gap-2">
            <button class="btn-secondary text-xs" @click="copy(match.code, 'Code')">Copy code</button>
            <button class="btn-secondary text-xs" @click="copy(`${$route.fullPath.split('?')[0]}?match=${match.code}`, 'Link')">Copy link</button>
          </div>
        </div>
      </div>
    </header>

    <div v-if="match.status === 'pending'" class="grid lg:grid-cols-2 gap-4">
      <article class="card p-5">
        <h3 class="text-sm font-bold text-slate-900 mb-3">Players ({{ players.length }})</h3>
        <ul class="space-y-2">
          <li v-for="p in players" :key="p.id" class="flex items-center justify-between text-sm">
            <span class="truncate font-medium text-slate-800">
              {{ p.profile?.full_name ?? 'Team member' }}
              <span v-if="p.user_id === match.host_user_id" class="text-[11px] uppercase text-sycamore-700 font-bold ml-1">Host</span>
            </span>
            <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold" :class="statusBadge(p).cls">{{ statusBadge(p).label }}</span>
          </li>
        </ul>
      </article>

      <article class="card p-5">
        <header class="flex items-center justify-between mb-3 gap-2">
          <h3 class="text-sm font-bold text-slate-900">Invite teammates</h3>
          <button v-if="!inviting" class="btn-secondary text-xs" @click="startSearch">Browse staff</button>
        </header>
        <div v-if="inviting" class="space-y-2">
          <input v-model="inviteTerm" placeholder="Search by name..." class="input text-sm" />
          <ul class="max-h-64 overflow-y-auto divide-y divide-slate-100 border border-slate-200 rounded-lg">
            <li v-for="r in inviteResults" :key="r.auth_user_id" class="flex items-center justify-between p-2 text-sm">
              <span class="truncate">
                <span class="font-medium text-slate-800">{{ r.full_name }}</span>
                <span class="text-xs text-slate-500 ml-1">{{ r.role }}</span>
              </span>
              <button
                class="btn-primary text-xs"
                :disabled="players.some(p => p.user_id === r.auth_user_id)"
                @click="invite(r.auth_user_id)"
              >
                {{ players.some(p => p.user_id === r.auth_user_id) ? 'Added' : 'Invite' }}
              </button>
            </li>
          </ul>
        </div>
        <p v-else class="text-xs text-slate-500">Or share the code <span class="font-mono font-bold">{{ match.code }}</span> with anyone — they can paste it on the Typing Sprint page to join.</p>
      </article>

      <article class="card p-5 lg:col-span-2 flex flex-wrap items-center justify-between gap-3">
        <div class="text-sm text-slate-700">
          <span v-if="isHost">Click Start when everyone has joined.</span>
          <span v-else>Waiting for the host to start the race.</span>
        </div>
        <div class="flex gap-2">
          <button class="btn-secondary text-sm" @click="leaveLobby">Leave</button>
          <button v-if="isHost" class="btn-primary text-sm" :disabled="joinedCount < 1" @click="hostStart">Start race</button>
        </div>
      </article>
    </div>

    <div v-else-if="match.status === 'active'" class="space-y-4">
      <div class="grid grid-cols-4 gap-2 text-center">
        <div class="rounded-xl border border-slate-200 bg-slate-50 p-3">
          <div class="text-[10px] uppercase tracking-wide text-slate-500">{{ match.mode === 'sprint' ? 'Elapsed' : 'Time left' }}</div>
          <div class="text-xl font-bold text-slate-900 tabular-nums">{{ match.mode === 'sprint' ? formatTime(elapsedMs) : formatTime(remainingMs) }}</div>
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
        <span v-for="(c, i) in promptChars" :key="i" :class="charClass(i)">{{ c }}</span>
      </div>

      <textarea
        id="match-typing-input"
        :value="typed"
        @input="onInput"
        rows="3"
        autocapitalize="off"
        spellcheck="false"
        autocomplete="off"
        class="input font-mono text-base resize-none"
        :placeholder="phase === 'racing' ? 'Type to race...' : 'Waiting...'"
        :disabled="phase !== 'racing'"
      ></textarea>

      <div class="flex justify-end">
        <button v-if="phase === 'racing'" class="btn-secondary" @click="finishRun('manual')">Stop and submit</button>
      </div>

      <article class="card p-4">
        <h3 class="text-sm font-bold text-slate-900 mb-2">Live standings</h3>
        <ol class="divide-y divide-slate-100">
          <li v-for="(p, i) in standings" :key="p.id" class="flex items-center justify-between py-2 text-sm">
            <div class="flex items-center gap-3 min-w-0">
              <span class="w-6 text-right text-xs font-bold text-slate-400 tabular-nums">{{ i + 1 }}</span>
              <span class="truncate font-medium text-slate-800">{{ p.profile?.full_name ?? 'Team member' }}</span>
              <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold" :class="statusBadge(p).cls">{{ statusBadge(p).label }}</span>
            </div>
            <span class="font-bold tabular-nums" :class="p.status === 'finished' ? 'text-sycamore-700' : 'text-slate-400'">
              {{ p.status === 'finished' ? Number(p.wpm).toFixed(1) + ' WPM' : '—' }}
            </span>
          </li>
        </ol>
      </article>
    </div>

    <div v-else class="space-y-4">
      <article class="card p-5">
        <header class="mb-3">
          <h3 class="text-base font-bold text-slate-900">Final podium</h3>
          <p class="text-xs text-slate-500">Ranked by WPM, then accuracy.</p>
        </header>
        <ol class="space-y-2">
          <li v-for="(p, i) in standings" :key="p.id" class="flex items-center justify-between text-sm rounded-xl border border-slate-200 px-3 py-2"
              :class="i === 0 ? 'bg-leaf-50 border-leaf-200' : 'bg-white'">
            <div class="flex items-center gap-3 min-w-0">
              <span class="w-6 text-right text-base font-extrabold text-slate-700 tabular-nums">{{ p.rank ?? (i + 1) }}</span>
              <span class="truncate font-semibold text-slate-800">{{ p.profile?.full_name ?? 'Team member' }}</span>
              <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold" :class="statusBadge(p).cls">{{ statusBadge(p).label }}</span>
            </div>
            <span class="font-bold text-sycamore-700 tabular-nums">
              {{ p.status === 'finished' ? Number(p.wpm).toFixed(1) + ' WPM · ' + Number(p.accuracy).toFixed(0) + '%' : '—' }}
            </span>
          </li>
        </ol>
      </article>
      <div class="flex justify-end">
        <button class="btn-primary" @click="emit('leave')">Leave room</button>
      </div>
    </div>
  </section>
</template>
