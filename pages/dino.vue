<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { useDinoMatch, type DinoMatchBoard, type DinoMatchPlayer } from '~/composables/useDinoMatch'

const supabase = useSupabase()
const toast = useToast()
const route = useRoute()
const router = useRouter()
const dinoMatch = useDinoMatch()

const activeTab = ref<'solo' | 'multiplayer'>((route.query.tab as string) === 'multi' || route.query.match ? 'multiplayer' : 'solo')
const activeMatchId = ref<string | null>(null)
const matchBoard = ref<DinoMatchBoard | null>(null)
const joinCode = ref((route.query.match as string) || '')
const creatingRoom = ref(false)
const joiningRoom = ref(false)
const selectedTimeLimit = ref<number | null>(60)
const matchCountdown = ref<number | null>(null)
const advancing = ref(false)
const roundsInput = ref(1)
let matchUnsubscribe: (() => void) | null = null
let matchTimerInterval: ReturnType<typeof setInterval> | null = null

const matchMatch = computed(() => matchBoard.value?.match ?? null)
const matchPlayers = computed(() => (matchBoard.value?.players ?? []).filter(p => p.status !== 'left'))
const isHost = computed(() => matchMatch.value && me.value && matchMatch.value.host_user_id === me.value)
const me = ref<string | null>(null)
const myMatchPlayer = computed<DinoMatchPlayer | null>(() => matchPlayers.value.find(p => p.user_id === me.value) ?? null)
const matchTimerUrgent = computed(() => matchCountdown.value !== null && matchCountdown.value <= 10)
const matchTimerWarning = computed(() => matchCountdown.value !== null && matchCountdown.value <= 30 && matchCountdown.value > 10)

function formatMatchTime(secs: number): string {
  const m = Math.floor(secs / 60)
  const s = secs % 60
  return m > 0 ? `${m}:${s.toString().padStart(2, '0')}` : `${s}s`
}

function startMatchTimer() {
  stopMatchTimer()
  if (!matchMatch.value?.deadline_at) return
  matchTimerInterval = setInterval(() => {
    if (!matchMatch.value?.deadline_at) { stopMatchTimer(); return }
    const remaining = Math.max(0, Math.ceil((new Date(matchMatch.value.deadline_at).getTime() - Date.now()) / 1000))
    matchCountdown.value = remaining
    if (remaining <= 0) { stopMatchTimer(); refreshMatch() }
  }, 1000)
}
function stopMatchTimer() { if (matchTimerInterval) { clearInterval(matchTimerInterval); matchTimerInterval = null } }

async function refreshMatch() {
  if (!activeMatchId.value) return
  try {
    matchBoard.value = await dinoMatch.loadBoard(activeMatchId.value)
    if (matchBoard.value?.match) {
      roundsInput.value = Math.max(1, (matchBoard.value.match as any).total_rounds ?? 1)
    }
    if (matchBoard.value?.match?.status === 'active' && matchBoard.value.match.deadline_at && !matchTimerInterval) startMatchTimer()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not load room')
  }
}

async function saveRounds() {
  if (!matchMatch.value) return
  try {
    await dinoMatch.setRounds(matchMatch.value.id, roundsInput.value)
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
    await dinoMatch.nextRound(matchMatch.value.id)
    await refreshMatch()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not start next round')
  } finally {
    advancing.value = false
  }
}

async function handleCreateRoom() {
  creatingRoom.value = true
  try {
    const m = await dinoMatch.createMatch({ timeLimit: selectedTimeLimit.value })
    activeMatchId.value = m.id
    router.replace({ query: { tab: 'multi', match: m.code } })
    await refreshMatch()
    matchUnsubscribe = dinoMatch.subscribe(m.id, refreshMatch)
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not create room')
  } finally {
    creatingRoom.value = false
  }
}

async function handleJoinRoom() {
  if (!joinCode.value.trim()) return
  joiningRoom.value = true
  try {
    const m = await dinoMatch.joinByCode(joinCode.value.trim())
    activeMatchId.value = m.id
    router.replace({ query: { tab: 'multi', match: m.code } })
    await refreshMatch()
    matchUnsubscribe = dinoMatch.subscribe(m.id, refreshMatch)
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not join room')
  } finally {
    joiningRoom.value = false
  }
}

async function handleLeaveRoom() {
  if (activeMatchId.value && matchMatch.value?.status === 'pending') {
    try { await dinoMatch.leave(activeMatchId.value) } catch {}
  }
  if (matchUnsubscribe) { matchUnsubscribe(); matchUnsubscribe = null }
  stopMatchTimer()
  activeMatchId.value = null
  matchBoard.value = null
  joinCode.value = ''
  router.replace({ query: { tab: 'multi' } })
}

async function handleStartMatch() {
  if (!activeMatchId.value) return
  try {
    await dinoMatch.start(activeMatchId.value)
    await refreshMatch()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not start')
  }
}

async function handleMatchJoinAsPlayer() {
  if (!matchMatch.value) return
  try {
    await dinoMatch.joinByCode(matchMatch.value.code)
    await refreshMatch()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not join')
  }
}

function copyMatchInfo(text: string, label: string) {
  navigator.clipboard.writeText(text).then(() => toast.success(`${label} copied`)).catch(() => toast.error('Copy failed'))
}

function matchStandings(): DinoMatchPlayer[] {
  return [...matchPlayers.value].sort((a, b) => {
    const sa = ((a as any).series_points ?? 0) + ((a as any).points_awarded ?? 0)
    const sb = ((b as any).series_points ?? 0) + ((b as any).points_awarded ?? 0)
    if (sa !== sb) return sb - sa
    if (a.score !== b.score) return b.score - a.score
    return b.duration_ms - a.duration_ms
  })
}

function seriesPts(p: DinoMatchPlayer): number {
  return ((p as any).series_points ?? 0) + ((p as any).points_awarded ?? 0)
}

const seriesComplete = computed(() =>
  !!matchMatch.value && matchMatch.value.status === 'finished' && ((matchMatch.value as any).current_round ?? 1) >= ((matchMatch.value as any).total_rounds ?? 1)
)
const hasMoreRounds = computed(() =>
  !!matchMatch.value && matchMatch.value.status === 'finished' && ((matchMatch.value as any).current_round ?? 1) < ((matchMatch.value as any).total_rounds ?? 1)
)

function matchRankBadge(i: number): string {
  if (i === 0) return 'bg-amber-100 text-amber-700'
  if (i === 1) return 'bg-slate-200 text-slate-700'
  if (i === 2) return 'bg-orange-100 text-orange-700'
  return 'bg-slate-100 text-slate-500'
}

type Phase = 'idle' | 'running' | 'over'

interface LeaderRow {
  user_id: string
  best: number
  name: string
  avatar: string | null
  role: string | null
}

const phase = ref<Phase>('idle')
const score = ref(0)
const personalBest = ref(0)
const lastScore = ref(0)
const lastIsPb = ref(false)
const submitting = ref(false)
const leaderboard = ref<LeaderRow[]>([])
const loadingBoard = ref(true)

const canvasRef = ref<HTMLCanvasElement | null>(null)
const containerRef = ref<HTMLDivElement | null>(null)

// World constants (logical px - canvas is scaled to fit)
const WORLD_W = 900
const WORLD_H = 260
const GROUND_Y = 220
const GRAVITY = 1900            // px/s^2
const JUMP_VELOCITY = -720      // px/s
const DUCK_VELOCITY = 1400      // extra downward force
const RUNNER_X = 80
const RUNNER_W = 44
const RUNNER_H = 48
const RUNNER_DUCK_H = 30

let rafId: number | null = null
let lastTs = 0
let runner = { y: GROUND_Y - RUNNER_H, vy: 0, ducking: false, legPhase: 0 }
let obstacles: Array<{ x: number; w: number; h: number; type: 'cone' | 'tree' | 'bird'; yOffset?: number; flap?: number }> = []
let scrollX = 0
let speed = 360 // px/s, increases over time
let spawnTimer = 0
let nextSpawn = 1.2
let runStartedAt = 0
let cloudPositions: Array<{ x: number; y: number; size: number }> = []

function resetWorld() {
  runner = { y: GROUND_Y - RUNNER_H, vy: 0, ducking: false, legPhase: 0 }
  obstacles = []
  scrollX = 0
  speed = 360
  spawnTimer = 0
  nextSpawn = 1.2
  score.value = 0
  cloudPositions = [
    { x: 200, y: 60, size: 1 },
    { x: 480, y: 90, size: 0.8 },
    { x: 720, y: 50, size: 1.1 }
  ]
}

function startGame() {
  resetWorld()
  phase.value = 'running'
  runStartedAt = performance.now()
  lastTs = performance.now()
  rafId = requestAnimationFrame(loop)
}

function endGame() {
  if (phase.value !== 'running') return
  phase.value = 'over'
  if (rafId !== null) cancelAnimationFrame(rafId)
  rafId = null
  const finalScore = Math.floor(score.value)
  const durationMs = performance.now() - runStartedAt
  const isPb = finalScore > personalBest.value
  lastScore.value = finalScore
  lastIsPb.value = isPb
  if (isPb) personalBest.value = finalScore
  void submitRun(finalScore, durationMs)
  if (activeMatchId.value && matchMatch.value?.status === 'active') {
    void dinoMatch.crash(activeMatchId.value, finalScore, durationMs).then(b => { matchBoard.value = b }).catch(() => {})
  }
}

async function submitRun(finalScore: number, durationMs: number) {
  if (finalScore <= 0) return
  submitting.value = true
  try {
    const { data, error } = await supabase.rpc('dino_submit_score', {
      p_score: Math.floor(finalScore),
      p_duration_ms: Math.round(durationMs)
    })
    if (error) throw error
    void loadLeaderboard()
  } catch (e: any) {
    toast.error(e.message ?? 'Could not save run')
  } finally {
    submitting.value = false
  }
}

async function loadPersonalBest() {
  const { data: sess } = await supabase.auth.getUser()
  const userId = sess.user?.id
  if (!userId) return
  const { data } = await supabase
    .from('dino_runner_scores')
    .select('score')
    .eq('user_id', userId)
    .order('score', { ascending: false })
    .limit(1)
    .maybeSingle()
  personalBest.value = (data as any)?.score ?? 0
}

async function loadLeaderboard() {
  loadingBoard.value = true
  try {
    const { data, error } = await supabase.rpc('dino_leaderboard', { p_limit: 10 })
    if (error) throw error
    leaderboard.value = ((data ?? []) as any[]).map(row => ({
      user_id: row.user_id,
      best: row.best,
      name: row.name ?? 'Sycamore staff',
      avatar: row.avatar ?? null,
      role: row.role ?? null
    }))
  } finally {
    loadingBoard.value = false
  }
}

// ---------- Game loop ----------
function loop(ts: number) {
  if (phase.value !== 'running') return
  const dt = Math.min(0.05, (ts - lastTs) / 1000)
  lastTs = ts
  step(dt)
  draw()
  rafId = requestAnimationFrame(loop)
}

function step(dt: number) {
  // gradual speed up
  speed += 14 * dt
  scrollX += speed * dt
  score.value += speed * dt * 0.05

  // runner physics
  if (runner.ducking && runner.y < GROUND_Y - currentRunnerHeight()) {
    runner.vy += DUCK_VELOCITY * dt
  }
  runner.vy += GRAVITY * dt
  runner.y += runner.vy * dt
  const bottomY = GROUND_Y - currentRunnerHeight()
  if (runner.y > bottomY) {
    runner.y = bottomY
    runner.vy = 0
  }
  if (runner.y >= bottomY - 0.5) {
    runner.legPhase += dt * (speed / 60)
  }

  // clouds
  for (const c of cloudPositions) {
    c.x -= speed * 0.25 * dt
    if (c.x < -80) {
      c.x = WORLD_W + Math.random() * 200
      c.y = 30 + Math.random() * 90
      c.size = 0.7 + Math.random() * 0.6
    }
  }

  // obstacles
  spawnTimer += dt
  if (spawnTimer >= nextSpawn) {
    spawnTimer = 0
    const r = Math.random()
    const minGap = 0.7
    const maxGap = 1.6
    nextSpawn = minGap + Math.random() * (maxGap - minGap) * (360 / speed)
    if (r < 0.55) {
      // single coffee cone
      obstacles.push({ x: WORLD_W + 20, w: 22, h: 36, type: 'cone' })
    } else if (r < 0.85) {
      // tree cluster
      const w = 36 + Math.floor(Math.random() * 24)
      obstacles.push({ x: WORLD_W + 20, w, h: 50, type: 'tree' })
    } else {
      // bird (passes through at varied heights)
      const heights = [GROUND_Y - 90, GROUND_Y - 60, GROUND_Y - 30]
      const yOffset = heights[Math.floor(Math.random() * heights.length)]
      obstacles.push({ x: WORLD_W + 20, w: 38, h: 24, type: 'bird', yOffset, flap: 0 })
    }
  }
  for (const o of obstacles) {
    o.x -= speed * dt
    if (o.type === 'bird') o.flap = (o.flap ?? 0) + dt * 8
  }
  obstacles = obstacles.filter(o => o.x + o.w > -10)

  // collision
  const r = currentRunnerRect()
  for (const o of obstacles) {
    const ob = obstacleRect(o)
    if (rectsOverlap(r, ob)) {
      endGame()
      return
    }
  }
}

function currentRunnerHeight() {
  return runner.ducking && runner.vy === 0 ? RUNNER_DUCK_H : RUNNER_H
}

function currentRunnerRect() {
  const h = currentRunnerHeight()
  // tighten hitbox a touch for fairness
  return { x: RUNNER_X + 6, y: runner.y + 4, w: RUNNER_W - 12, h: h - 6 }
}

function obstacleRect(o: { x: number; w: number; h: number; type: string; yOffset?: number }) {
  if (o.type === 'bird') {
    return { x: o.x + 4, y: (o.yOffset ?? GROUND_Y - 60) + 4, w: o.w - 8, h: o.h - 6 }
  }
  return { x: o.x + 3, y: GROUND_Y - o.h + 3, w: o.w - 6, h: o.h - 4 }
}

function rectsOverlap(a: { x: number; y: number; w: number; h: number }, b: { x: number; y: number; w: number; h: number }) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

// ---------- Render ----------
function draw() {
  const cv = canvasRef.value
  if (!cv) return
  const ctx = cv.getContext('2d')
  if (!ctx) return

  // sky gradient
  const grad = ctx.createLinearGradient(0, 0, 0, WORLD_H)
  grad.addColorStop(0, '#ecfdf5')
  grad.addColorStop(1, '#ffffff')
  ctx.fillStyle = grad
  ctx.fillRect(0, 0, WORLD_W, WORLD_H)

  // clouds
  ctx.fillStyle = 'rgba(15, 110, 66, 0.08)'
  for (const c of cloudPositions) drawCloud(ctx, c.x, c.y, c.size)

  // ground line
  ctx.strokeStyle = '#0f6e42'
  ctx.lineWidth = 2
  ctx.beginPath()
  ctx.moveTo(0, GROUND_Y + 1)
  ctx.lineTo(WORLD_W, GROUND_Y + 1)
  ctx.stroke()

  // ground dashes (parallax)
  ctx.fillStyle = '#0f6e42'
  const dashSpacing = 32
  const offset = -(scrollX % dashSpacing)
  for (let x = offset; x < WORLD_W; x += dashSpacing) {
    ctx.fillRect(x, GROUND_Y + 8, 12, 2)
  }

  // obstacles
  for (const o of obstacles) drawObstacle(ctx, o)

  // runner (Sycamore squirrel)
  drawRunner(ctx)

  // HUD
  ctx.fillStyle = '#0f172a'
  ctx.font = 'bold 18px ui-sans-serif, system-ui, sans-serif'
  ctx.textAlign = 'right'
  ctx.fillText(String(Math.floor(score.value)).padStart(5, '0'), WORLD_W - 16, 28)
  ctx.fillStyle = '#64748b'
  ctx.font = '12px ui-sans-serif, system-ui, sans-serif'
  ctx.fillText(`HI ${String(Math.max(personalBest.value, Math.floor(score.value))).padStart(5, '0')}`, WORLD_W - 90, 28)
  ctx.textAlign = 'left'
}

function drawCloud(ctx: CanvasRenderingContext2D, x: number, y: number, size: number) {
  ctx.beginPath()
  ctx.arc(x, y, 14 * size, 0, Math.PI * 2)
  ctx.arc(x + 14 * size, y - 6 * size, 11 * size, 0, Math.PI * 2)
  ctx.arc(x + 26 * size, y, 13 * size, 0, Math.PI * 2)
  ctx.arc(x + 14 * size, y + 4 * size, 10 * size, 0, Math.PI * 2)
  ctx.fill()
}

function drawObstacle(ctx: CanvasRenderingContext2D, o: { x: number; w: number; h: number; type: string; yOffset?: number; flap?: number }) {
  if (o.type === 'cone') {
    // coffee cup (Sycamore-flavored)
    const x = o.x
    const top = GROUND_Y - o.h
    ctx.fillStyle = '#0f6e42'
    ctx.beginPath()
    ctx.moveTo(x + 2, GROUND_Y)
    ctx.lineTo(x + o.w - 2, GROUND_Y)
    ctx.lineTo(x + o.w - 4, top + 6)
    ctx.lineTo(x + 4, top + 6)
    ctx.closePath()
    ctx.fill()
    // lid
    ctx.fillStyle = '#0b1a2c'
    ctx.fillRect(x + 2, top + 2, o.w - 4, 6)
    // steam
    ctx.strokeStyle = 'rgba(15,110,66,0.5)'
    ctx.lineWidth = 1.5
    ctx.beginPath()
    ctx.moveTo(x + o.w / 2 - 3, top - 2)
    ctx.quadraticCurveTo(x + o.w / 2 + 3, top - 8, x + o.w / 2, top - 14)
    ctx.stroke()
  } else if (o.type === 'tree') {
    // sycamore tree silhouette
    const x = o.x
    const top = GROUND_Y - o.h
    ctx.fillStyle = '#0b3d28'
    ctx.fillRect(x + o.w / 2 - 3, top + 22, 6, o.h - 22)
    ctx.fillStyle = '#0f6e42'
    ctx.beginPath()
    ctx.arc(x + o.w / 2, top + 18, 16, 0, Math.PI * 2)
    ctx.arc(x + o.w / 2 - 12, top + 24, 12, 0, Math.PI * 2)
    ctx.arc(x + o.w / 2 + 12, top + 24, 12, 0, Math.PI * 2)
    ctx.fill()
  } else if (o.type === 'bird') {
    const x = o.x
    const y = o.yOffset ?? GROUND_Y - 60
    ctx.fillStyle = '#0b1a2c'
    // body
    ctx.beginPath()
    ctx.ellipse(x + 18, y + 12, 14, 7, 0, 0, Math.PI * 2)
    ctx.fill()
    // head
    ctx.beginPath()
    ctx.arc(x + 30, y + 8, 5, 0, Math.PI * 2)
    ctx.fill()
    // beak
    ctx.fillStyle = '#fbbf24'
    ctx.beginPath()
    ctx.moveTo(x + 34, y + 8)
    ctx.lineTo(x + 40, y + 7)
    ctx.lineTo(x + 34, y + 10)
    ctx.closePath()
    ctx.fill()
    // wing flap
    const flap = Math.sin(o.flap ?? 0)
    ctx.fillStyle = '#0b1a2c'
    ctx.beginPath()
    ctx.moveTo(x + 14, y + 10)
    ctx.lineTo(x + 20, y - 2 - flap * 6)
    ctx.lineTo(x + 26, y + 10)
    ctx.closePath()
    ctx.fill()
  }
}

function drawRunner(ctx: CanvasRenderingContext2D) {
  const x = RUNNER_X
  const grounded = runner.y >= GROUND_Y - currentRunnerHeight() - 0.5
  const ducking = runner.ducking && grounded
  const w = RUNNER_W
  const h = ducking ? RUNNER_DUCK_H : RUNNER_H
  const y = runner.y

  // body (squirrel-ish silhouette in Sycamore green)
  ctx.fillStyle = '#0f6e42'
  // tail
  ctx.beginPath()
  if (ducking) {
    ctx.ellipse(x + w - 4, y + h * 0.4, 10, 6, -0.3, 0, Math.PI * 2)
  } else {
    ctx.ellipse(x + w - 6, y + 8, 12, 14, -0.5, 0, Math.PI * 2)
  }
  ctx.fill()

  // body
  ctx.fillStyle = '#0b3d28'
  if (ducking) {
    roundRect(ctx, x + 4, y + 4, w - 12, h - 6, 8)
  } else {
    roundRect(ctx, x + 8, y + 12, w - 18, h - 18, 6)
  }
  ctx.fill()

  // head
  ctx.fillStyle = '#0f6e42'
  if (ducking) {
    ctx.beginPath()
    ctx.arc(x + 12, y + 12, 8, 0, Math.PI * 2)
    ctx.fill()
  } else {
    ctx.beginPath()
    ctx.arc(x + 14, y + 12, 10, 0, Math.PI * 2)
    ctx.fill()
  }

  // ear
  ctx.fillStyle = '#0b3d28'
  ctx.beginPath()
  ctx.moveTo(x + 8, y + (ducking ? 6 : 4))
  ctx.lineTo(x + 14, y + (ducking ? 0 : -2))
  ctx.lineTo(x + 16, y + (ducking ? 8 : 8))
  ctx.closePath()
  ctx.fill()

  // eye
  ctx.fillStyle = '#fbfcff'
  ctx.beginPath()
  ctx.arc(x + 16, y + (ducking ? 11 : 11), 2, 0, Math.PI * 2)
  ctx.fill()
  ctx.fillStyle = '#0b1a2c'
  ctx.beginPath()
  ctx.arc(x + 16.5, y + (ducking ? 11 : 11), 1, 0, Math.PI * 2)
  ctx.fill()

  // legs (animated when on ground)
  ctx.fillStyle = '#0b3d28'
  if (!grounded) {
    ctx.fillRect(x + 12, y + h - 8, 6, 10)
    ctx.fillRect(x + 24, y + h - 8, 6, 10)
  } else {
    const sw = Math.sin(runner.legPhase * 6)
    const cw = Math.cos(runner.legPhase * 6)
    if (ducking) {
      ctx.fillRect(x + 10 + sw * 3, y + h - 4, 6, 6)
      ctx.fillRect(x + 22 + cw * 3, y + h - 4, 6, 6)
    } else {
      ctx.fillRect(x + 12, y + h - 6 + sw * 3, 6, 8 + Math.abs(sw) * 2)
      ctx.fillRect(x + 24, y + h - 6 + cw * 3, 6, 8 + Math.abs(cw) * 2)
    }
  }
}

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  ctx.lineTo(x + w - r, y)
  ctx.quadraticCurveTo(x + w, y, x + w, y + r)
  ctx.lineTo(x + w, y + h - r)
  ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
  ctx.lineTo(x + r, y + h)
  ctx.quadraticCurveTo(x, y + h, x, y + h - r)
  ctx.lineTo(x, y + r)
  ctx.quadraticCurveTo(x, y, x + r, y)
  ctx.closePath()
}

// ---------- Input ----------
function jump() {
  if (phase.value === 'idle' || phase.value === 'over') {
    startGame()
    return
  }
  if (phase.value !== 'running') return
  // allow jump only when grounded
  if (runner.y >= GROUND_Y - currentRunnerHeight() - 0.5) {
    runner.vy = JUMP_VELOCITY
    runner.ducking = false
  }
}

function setDuck(active: boolean) {
  if (phase.value !== 'running') return
  runner.ducking = active
}

function onKeyDown(e: KeyboardEvent) {
  const tag = (e.target as HTMLElement)?.tagName
  if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return
  if (e.code === 'Space' || e.code === 'ArrowUp' || e.code === 'KeyW') {
    e.preventDefault()
    jump()
  } else if (e.code === 'ArrowDown' || e.code === 'KeyS') {
    e.preventDefault()
    setDuck(true)
  }
}
function onKeyUp(e: KeyboardEvent) {
  if (e.code === 'ArrowDown' || e.code === 'KeyS') setDuck(false)
}

function onTouchStart(e: TouchEvent) {
  e.preventDefault()
  jump()
}

// ---------- Lifecycle ----------
function fitCanvas() {
  const cv = canvasRef.value
  const wrap = containerRef.value
  if (!cv || !wrap) return
  const ratio = WORLD_W / WORLD_H
  const cssWidth = Math.min(wrap.clientWidth, 960)
  const cssHeight = cssWidth / ratio
  const dpr = window.devicePixelRatio || 1
  cv.width = WORLD_W * dpr
  cv.height = WORLD_H * dpr
  cv.style.width = `${cssWidth}px`
  cv.style.height = `${cssHeight}px`
  const ctx = cv.getContext('2d')
  if (ctx) ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  draw()
}

onMounted(async () => {
  fitCanvas()
  window.addEventListener('resize', fitCanvas)
  window.addEventListener('keydown', onKeyDown)
  window.addEventListener('keyup', onKeyUp)
  void loadPersonalBest()
  void loadLeaderboard()
  draw()
  const { data } = await supabase.auth.getUser()
  me.value = data.user?.id ?? null
  if (joinCode.value) { await handleJoinRoom() }
})

onBeforeUnmount(() => {
  if (rafId !== null) cancelAnimationFrame(rafId)
  window.removeEventListener('resize', fitCanvas)
  window.removeEventListener('keydown', onKeyDown)
  window.removeEventListener('keyup', onKeyUp)
  if (matchUnsubscribe) matchUnsubscribe()
  stopMatchTimer()
})

useHead({ title: 'Sycamore Run' })
</script>

<template>
  <div class="max-w-4xl mx-auto pb-10">
    <header class="text-center mb-6">
      <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-50 border border-emerald-200 text-[11px] font-semibold uppercase tracking-[0.2em] text-emerald-700">
        <span class="w-1.5 h-1.5 rounded-full bg-emerald-500"></span>
        Coffee break
      </div>
      <h1 class="mt-3 text-2xl sm:text-4xl font-bold text-slate-900 tracking-tight">Sycamore Run</h1>
      <p class="mt-1 text-xs sm:text-sm text-slate-500">Hop the cups, dodge the canopies, fly past the birds.</p>
    </header>

    <!-- Tabs -->
    <div class="flex gap-1 mb-6 p-1 rounded-xl bg-slate-100 max-w-xs mx-auto">
      <button type="button" class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg transition-all"
        :class="activeTab === 'solo' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
        @click="activeTab = 'solo'">Solo</button>
      <button type="button" class="flex-1 px-4 py-2 text-sm font-semibold rounded-lg transition-all"
        :class="activeTab === 'multiplayer' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
        @click="activeTab = 'multiplayer'">Multiplayer</button>
    </div>

    <!-- === SOLO TAB === -->
    <div v-show="activeTab === 'solo'">
      <div ref="containerRef" class="bg-white border border-slate-200 rounded-3xl p-3 sm:p-4 shadow-sm">
        <div class="relative" @touchstart="onTouchStart">
          <canvas ref="canvasRef" class="block w-full rounded-2xl bg-emerald-50/40 border border-emerald-100" tabindex="0" />
          <div v-if="phase === 'idle'" class="absolute inset-0 flex flex-col items-center justify-center text-center px-4">
            <div class="bg-white/90 backdrop-blur rounded-2xl border border-emerald-200 px-6 py-5 max-w-sm shadow">
              <div class="text-emerald-700 font-bold uppercase tracking-[0.2em] text-[11px]">Ready</div>
              <div class="text-lg font-semibold text-slate-900 mt-1">Tap or press Space to run</div>
              <div class="mt-2 text-xs text-slate-500">Up arrow / Space to jump &middot; Down arrow to duck</div>
              <button type="button" class="mt-4 inline-flex items-center justify-center px-5 py-2.5 rounded-full bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-semibold" @click="startGame">Start running</button>
            </div>
          </div>
          <div v-else-if="phase === 'over'" class="absolute inset-0 flex flex-col items-center justify-center text-center px-4">
            <div class="bg-white/95 backdrop-blur rounded-2xl border border-emerald-200 px-6 py-5 max-w-sm shadow-lg">
              <div class="text-emerald-700 font-bold uppercase tracking-[0.2em] text-[11px]">Run finished</div>
              <div class="mt-1 text-2xl sm:text-3xl font-bold text-slate-900 tabular-nums">{{ lastScore }}</div>
              <div v-if="lastIsPb" class="mt-1 text-emerald-700 text-sm font-semibold">New personal best!</div>
              <div v-else class="mt-1 text-slate-500 text-xs">Personal best: {{ personalBest }}</div>
              <button type="button" class="mt-4 inline-flex items-center justify-center px-5 py-2.5 rounded-full bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-semibold" @click="startGame">Run again</button>
              <div class="mt-2 text-[11px] text-slate-400" v-if="submitting">Saving your run...</div>
            </div>
          </div>
        </div>
        <div class="mt-4 grid grid-cols-3 gap-3 text-center">
          <div class="rounded-xl border border-slate-200 py-3">
            <div class="text-[11px] uppercase tracking-[0.2em] text-slate-400 font-semibold">Score</div>
            <div class="text-xl font-bold text-slate-900 tabular-nums">{{ Math.floor(score) }}</div>
          </div>
          <div class="rounded-xl border border-slate-200 py-3">
            <div class="text-[11px] uppercase tracking-[0.2em] text-slate-400 font-semibold">Personal best</div>
            <div class="text-xl font-bold text-slate-900 tabular-nums">{{ personalBest }}</div>
          </div>
          <div class="rounded-xl border border-slate-200 py-3">
            <div class="text-[11px] uppercase tracking-[0.2em] text-slate-400 font-semibold">Status</div>
            <div class="text-xl font-bold text-emerald-700 capitalize">{{ phase }}</div>
          </div>
        </div>
      </div>

      <section class="mt-8">
        <div class="flex items-end justify-between mb-3">
          <h2 class="text-xl font-semibold text-slate-900">Top runners</h2>
          <button type="button" class="text-xs text-emerald-700 hover:text-emerald-800 font-semibold" @click="loadLeaderboard">Refresh</button>
        </div>
        <div v-if="loadingBoard" class="text-sm text-slate-400 py-6 text-center">Loading leaderboard...</div>
        <div v-else-if="leaderboard.length === 0" class="text-sm text-slate-400 py-6 text-center bg-white border border-slate-200 rounded-2xl">No runs yet. Be the first to set a record.</div>
        <ul v-else class="bg-white border border-slate-200 rounded-2xl divide-y divide-slate-100 overflow-hidden">
          <li v-for="(row, i) in leaderboard" :key="row.user_id" class="flex items-center gap-3 px-4 py-3">
            <div class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold" :class="i === 0 ? 'bg-amber-100 text-amber-700' : i === 1 ? 'bg-slate-200 text-slate-700' : i === 2 ? 'bg-orange-100 text-orange-700' : 'bg-slate-100 text-slate-500'">{{ i + 1 }}</div>
            <img v-if="row.avatar" :src="row.avatar" :alt="row.name" class="w-9 h-9 rounded-full object-cover border border-slate-200" />
            <div v-else class="w-9 h-9 rounded-full bg-emerald-100 text-emerald-700 font-bold flex items-center justify-center text-sm">{{ (row.name?.[0] ?? '?').toUpperCase() }}</div>
            <div class="flex-1 min-w-0">
              <div class="text-sm font-semibold text-slate-900 truncate">{{ row.name }}</div>
              <div v-if="row.role" class="text-xs text-slate-500 truncate">{{ row.role }}</div>
            </div>
            <div class="text-base font-bold text-slate-900 tabular-nums">{{ row.best }}</div>
          </li>
        </ul>
      </section>
    </div>

    <!-- === MULTIPLAYER TAB === -->
    <div v-show="activeTab === 'multiplayer'">
      <!-- Active room -->
      <template v-if="activeMatchId && matchBoard">
        <header class="rounded-2xl border border-emerald-200 bg-gradient-to-br from-emerald-50 to-amber-50 p-5 mb-5">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div class="text-[11px] uppercase tracking-wider text-emerald-700 font-bold">Sycamore Run Race</div>
              <h2 class="text-xl font-bold text-slate-900">Multiplayer Room</h2>
              <p class="text-sm text-slate-600">
                <span v-if="matchMatch?.status === 'pending'">Lobby. {{ matchPlayers.length }} joined.</span>
                <span v-else-if="matchMatch?.status === 'active'">Race in progress! Run as far as you can.</span>
                <span v-else-if="matchMatch?.status === 'finished' && hasMoreRounds">Round {{ (matchMatch as any).current_round }} of {{ (matchMatch as any).total_rounds }} complete. Next round up!</span>
                <span v-else-if="matchMatch?.status === 'finished'">{{ ((matchMatch as any).total_rounds ?? 1) > 1 ? 'Series complete.' : 'Race complete.' }}</span>
              </p>
              <p v-if="matchMatch && ((matchMatch as any).total_rounds ?? 1) > 1" class="text-[11px] mt-1 font-semibold text-sky-700">Round {{ (matchMatch as any).current_round ?? 1 }} of {{ (matchMatch as any).total_rounds ?? 1 }}</p>
            </div>
            <div class="flex flex-col items-end gap-1">
              <div class="font-mono text-2xl font-bold tracking-widest text-slate-900">{{ matchMatch?.code }}</div>
              <div class="flex gap-2">
                <button type="button" class="text-xs px-3 py-1 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-50" @click="copyMatchInfo(matchMatch?.code ?? '', 'Code')">Copy code</button>
              </div>
            </div>
          </div>
          <!-- Timer -->
          <div v-if="matchMatch?.status === 'active' && matchCountdown !== null" class="mt-4">
            <div class="flex items-center justify-between text-xs mb-1">
              <span class="font-semibold" :class="matchTimerUrgent ? 'text-red-600' : matchTimerWarning ? 'text-amber-600' : 'text-slate-600'">Time Remaining</span>
              <span class="font-mono font-bold text-lg" :class="matchTimerUrgent ? 'text-red-600 animate-pulse' : matchTimerWarning ? 'text-amber-600' : 'text-slate-900'">{{ formatMatchTime(matchCountdown) }}</span>
            </div>
            <div class="w-full h-2 rounded-full bg-slate-200 overflow-hidden">
              <div class="h-full rounded-full transition-all duration-1000 ease-linear"
                :class="matchTimerUrgent ? 'bg-red-500' : matchTimerWarning ? 'bg-amber-400' : 'bg-emerald-500'"
                :style="{ width: matchMatch?.time_limit_seconds ? Math.max(0, (matchCountdown / matchMatch.time_limit_seconds) * 100) + '%' : '100%' }"></div>
            </div>
          </div>
        </header>

        <!-- Lobby -->
        <div v-if="matchMatch?.status === 'pending'" class="space-y-4">
          <article class="card p-5">
            <h3 class="text-sm font-bold text-slate-900 mb-3">Players ({{ matchPlayers.length }} / {{ matchMatch.max_players }})</h3>
            <ul class="space-y-2">
              <li v-for="p in matchPlayers" :key="p.user_id" class="flex items-center justify-between text-sm">
                <span class="truncate font-medium text-slate-800">
                  {{ p.full_name ?? 'Team member' }}
                  <span v-if="p.user_id === matchMatch.host_user_id" class="text-[11px] uppercase text-emerald-700 font-bold ml-1">Host</span>
                </span>
                <span class="px-2 py-0.5 rounded-full text-[10px] font-semibold bg-slate-100 text-slate-700">Ready</span>
              </li>
            </ul>
          </article>
          <article v-if="isHost" class="card p-5">
            <h3 class="text-sm font-bold text-slate-900 mb-3">Series length</h3>
            <div class="flex flex-wrap items-center gap-2">
              <label class="text-xs font-bold text-slate-700">Rounds</label>
              <select v-model.number="roundsInput" class="text-xs px-2 py-1 rounded border border-slate-300 bg-white">
                <option v-for="n in [1,2,3,5,7,10]" :key="n" :value="n">Best of {{ n }}</option>
              </select>
              <button type="button" class="text-xs px-3 py-1.5 rounded-full bg-slate-900 text-white hover:bg-slate-800" @click="saveRounds">Save</button>
              <span class="text-[11px] text-slate-500">Auto-continues to the next round when a round finishes.</span>
            </div>
          </article>
          <article class="card p-5 flex flex-wrap items-center justify-between gap-3">
            <div class="text-sm text-slate-700">
              <span v-if="isHost && !myMatchPlayer">You're hosting but not playing.</span>
              <span v-else-if="isHost">Click Start when everyone has joined.</span>
              <span v-else>Waiting for the host to start...</span>
            </div>
            <div class="flex gap-2">
              <button v-if="myMatchPlayer" type="button" class="text-sm px-4 py-2 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-50" @click="handleLeaveRoom">Leave</button>
              <button v-if="isHost && !myMatchPlayer" type="button" class="text-sm px-4 py-2 rounded-full bg-blue-600 text-white font-semibold hover:bg-blue-700" @click="handleMatchJoinAsPlayer">Join as player</button>
              <button v-if="isHost" type="button" class="text-sm px-4 py-2 rounded-full bg-emerald-600 text-white font-semibold hover:bg-emerald-700 disabled:opacity-40" :disabled="matchPlayers.length < 1" @click="handleStartMatch">Start race</button>
            </div>
          </article>
        </div>

        <!-- Active: game canvas + live scoreboard -->
        <div v-else-if="matchMatch?.status === 'active'" class="grid lg:grid-cols-[1fr_280px] gap-5 items-start">
          <div>
            <div ref="containerRef" class="bg-white border border-slate-200 rounded-3xl p-3 shadow-sm">
              <div class="relative" @touchstart="onTouchStart">
                <canvas ref="canvasRef" class="block w-full rounded-2xl bg-emerald-50/40 border border-emerald-100" tabindex="0" />
                <div v-if="phase === 'idle' && myMatchPlayer?.status === 'playing'" class="absolute inset-0 flex flex-col items-center justify-center text-center px-4">
                  <div class="bg-white/90 backdrop-blur rounded-2xl border border-emerald-200 px-6 py-5 max-w-sm shadow">
                    <div class="text-emerald-700 font-bold uppercase tracking-[0.2em] text-[11px]">Race started!</div>
                    <div class="text-lg font-semibold text-slate-900 mt-1">Tap or press Space to run</div>
                    <button type="button" class="mt-4 inline-flex items-center justify-center px-5 py-2.5 rounded-full bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-semibold" @click="startGame">Start running</button>
                  </div>
                </div>
                <div v-else-if="phase === 'over' && myMatchPlayer?.status === 'crashed'" class="absolute inset-0 flex flex-col items-center justify-center text-center px-4">
                  <div class="bg-white/95 backdrop-blur rounded-2xl border border-emerald-200 px-6 py-5 max-w-sm shadow-lg">
                    <div class="text-emerald-700 font-bold uppercase tracking-[0.2em] text-[11px]">You crashed!</div>
                    <div class="mt-1 text-2xl font-bold text-slate-900 tabular-nums">{{ lastScore }}</div>
                    <div class="mt-2 text-sm text-slate-500">Waiting for others to finish...</div>
                  </div>
                </div>
              </div>
              <div class="mt-3 flex items-center justify-between px-2">
                <span class="text-xs text-slate-500">Your score:</span>
                <span class="text-lg font-bold text-slate-900 tabular-nums">{{ Math.floor(score) }}</span>
              </div>
            </div>
          </div>
          <!-- Live scoreboard -->
          <aside class="rounded-2xl border border-slate-200 bg-white p-4 space-y-3 lg:sticky lg:top-4">
            <h3 class="text-sm font-bold text-slate-900">Live scores</h3>
            <ol class="space-y-2">
              <li v-for="(p, i) in matchStandings()" :key="p.user_id" class="flex items-center gap-2 text-xs">
                <span class="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold" :class="matchRankBadge(i)">{{ i + 1 }}</span>
                <span class="flex-1 truncate font-medium text-slate-800">
                  {{ p.full_name ?? 'Team member' }}
                  <span v-if="p.user_id === me" class="text-[10px] uppercase text-emerald-700 font-bold ml-1">You</span>
                </span>
                <span class="tabular-nums font-bold text-slate-900">{{ p.score }}</span>
                <span v-if="p.status === 'crashed'" class="px-1.5 py-0.5 rounded text-[9px] font-bold bg-rose-100 text-rose-700">Crashed</span>
                <span v-else class="px-1.5 py-0.5 rounded text-[9px] font-bold bg-emerald-100 text-emerald-700">Running</span>
              </li>
            </ol>
            <button type="button" class="w-full text-xs px-3 py-2 rounded-full bg-white border border-slate-300 text-slate-700 hover:bg-slate-50" @click="handleLeaveRoom">Leave room</button>
          </aside>
        </div>

        <!-- Finished -->
        <div v-else-if="matchMatch?.status === 'finished'" class="space-y-5">
          <article class="card p-6 text-center" :class="matchStandings()[0]?.user_id === me ? 'border-amber-200 bg-amber-50' : 'border-slate-200 bg-slate-50'">
            <h2 class="text-lg font-bold" :class="matchStandings()[0]?.user_id === me ? 'text-amber-800' : 'text-slate-800'">
              {{ matchStandings()[0]?.user_id === me ? 'You won the race!' : 'Race complete' }}
            </h2>
            <p v-if="myMatchPlayer?.points_awarded" class="text-sm mt-1" :class="matchStandings()[0]?.user_id === me ? 'text-amber-600' : 'text-slate-500'">
              You earned <span class="font-bold">{{ myMatchPlayer.points_awarded }}</span> points
            </p>
          </article>

          <!-- Podium -->
          <article v-if="matchStandings().length >= 1" class="card p-6">
            <h3 class="text-sm font-bold text-slate-900 text-center mb-6">{{ seriesComplete && ((matchMatch as any)?.total_rounds ?? 1) > 1 ? 'Series Podium' : (((matchMatch as any)?.total_rounds ?? 1) > 1 ? 'Round ' + ((matchMatch as any)?.current_round ?? 1) + ' Podium' : 'Podium') }}</h3>
            <div class="flex items-end justify-center gap-3 max-w-sm mx-auto">
              <div v-if="matchStandings()[1]" class="flex flex-col items-center flex-1">
                <div class="w-10 h-10 rounded-full bg-slate-200 flex items-center justify-center text-sm font-bold text-slate-700 mb-2">{{ matchStandings()[1].full_name?.charAt(0) ?? '?' }}</div>
                <p class="text-[11px] font-semibold text-slate-700 text-center truncate max-w-[80px]">{{ matchStandings()[1].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-slate-500">{{ seriesPts(matchStandings()[1]) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-slate-200 flex items-end justify-center" style="height: 60px;"><span class="text-lg font-bold text-slate-600 mb-2">2</span></div>
              </div>
              <div v-if="matchStandings()[0]" class="flex flex-col items-center flex-1">
                <div class="w-12 h-12 rounded-full bg-amber-100 border-2 border-amber-300 flex items-center justify-center text-base font-bold text-amber-700 mb-2">{{ matchStandings()[0].full_name?.charAt(0) ?? '?' }}</div>
                <p class="text-xs font-bold text-slate-900 text-center truncate max-w-[80px]">{{ matchStandings()[0].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-amber-700 font-semibold">{{ seriesPts(matchStandings()[0]) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-amber-100 border-2 border-amber-200 flex items-end justify-center" style="height: 90px;"><span class="text-2xl mb-2">&#x1F3C6;</span></div>
              </div>
              <div v-if="matchStandings()[2]" class="flex flex-col items-center flex-1">
                <div class="w-10 h-10 rounded-full bg-orange-100 flex items-center justify-center text-sm font-bold text-orange-700 mb-2">{{ matchStandings()[2].full_name?.charAt(0) ?? '?' }}</div>
                <p class="text-[11px] font-semibold text-slate-700 text-center truncate max-w-[80px]">{{ matchStandings()[2].full_name?.split(' ')[0] ?? 'Player' }}</p>
                <p class="text-[10px] text-slate-500">{{ seriesPts(matchStandings()[2]) }} pts</p>
                <div class="w-full mt-2 rounded-t-lg bg-orange-100 flex items-end justify-center" style="height: 40px;"><span class="text-lg font-bold text-orange-600 mb-2">3</span></div>
              </div>
            </div>
            <ol v-if="matchStandings().length > 3" class="mt-5 space-y-1.5 border-t border-slate-100 pt-4">
              <li v-for="(p, i) in matchStandings().slice(3)" :key="p.user_id" class="flex items-center gap-3 text-xs px-3 py-1.5 rounded-lg" :class="p.user_id === me ? 'bg-emerald-50 border border-emerald-200' : 'bg-slate-50'">
                <span class="w-5 h-5 rounded-full bg-slate-100 flex items-center justify-center text-[10px] font-bold text-slate-500">{{ i + 4 }}</span>
                <span class="flex-1 truncate font-medium text-slate-800">{{ p.full_name ?? 'Team member' }}</span>
                <span class="tabular-nums font-bold text-slate-900">{{ seriesPts(p) }}</span>
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
          <div class="w-14 h-14 mx-auto rounded-full bg-emerald-100 text-emerald-700 flex items-center justify-center mb-4">
            <SidebarIcon name="users" class="w-7 h-7" />
          </div>
          <h2 class="text-lg font-semibold text-slate-900">Multiplayer Race</h2>
          <p class="text-sm text-slate-500 mt-1 max-w-sm mx-auto">Race your teammates! Everyone plays simultaneously. Highest score wins.</p>

          <div class="mt-5 max-w-xs mx-auto">
            <label class="block text-xs font-semibold text-slate-600 uppercase tracking-wide mb-2 text-left">Time Limit</label>
            <div class="grid grid-cols-5 gap-1.5">
              <button v-for="opt in [{ label: 'None', value: null }, { label: '30s', value: 30 }, { label: '60s', value: 60 }, { label: '90s', value: 90 }, { label: '3m', value: 180 }]"
                :key="String(opt.value)" type="button"
                class="px-2 py-1.5 text-xs font-semibold rounded-lg border transition-all"
                :class="selectedTimeLimit === opt.value ? 'bg-emerald-600 text-white border-emerald-600' : 'bg-white text-slate-600 border-slate-200 hover:border-emerald-300'"
                @click="selectedTimeLimit = opt.value">{{ opt.label }}</button>
            </div>
          </div>

          <button type="button" class="btn-primary mt-5 px-8" :disabled="creatingRoom" @click="handleCreateRoom">
            {{ creatingRoom ? 'Creating...' : 'Create Room' }}
          </button>
        </article>

        <div class="relative">
          <div class="absolute inset-0 flex items-center"><div class="w-full border-t border-slate-200"></div></div>
          <div class="relative flex justify-center"><span class="bg-white px-3 text-xs font-semibold text-slate-400 uppercase">or join a room</span></div>
        </div>

        <form class="card p-5" @submit.prevent="handleJoinRoom">
          <label class="block text-xs font-semibold text-slate-600 uppercase tracking-wide mb-2">Room Code</label>
          <div class="flex gap-3">
            <input v-model="joinCode" type="text" class="input flex-1 text-center font-mono text-lg uppercase tracking-widest" placeholder="ABCDEF" maxlength="6" :disabled="joiningRoom" />
            <button type="submit" class="btn-primary px-5" :disabled="joiningRoom || joinCode.trim().length < 4">
              {{ joiningRoom ? 'Joining...' : 'Join' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
