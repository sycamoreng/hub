<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { useGamification } from '~/composables/useGamification'

const supabase = useSupabase()
const toast = useToast()
const { awardPoints } = useGamification()

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
  const isPb = finalScore > personalBest.value
  lastScore.value = finalScore
  lastIsPb.value = isPb
  if (isPb) personalBest.value = finalScore
  void submitRun(finalScore, performance.now() - runStartedAt)
}

async function submitRun(finalScore: number, durationMs: number) {
  if (finalScore <= 0) return
  submitting.value = true
  try {
    const { data: sess } = await supabase.auth.getUser()
    const userId = sess.user?.id
    if (!userId) return
    const { error } = await supabase.from('dino_runner_scores').insert({
      user_id: userId,
      score: finalScore,
      duration_ms: Math.round(durationMs)
    })
    if (error) throw error
    const points = Math.min(20, Math.max(1, Math.floor(finalScore / 100)))
    await awardPoints({
      userId,
      kind: 'dino_run_completed',
      refType: 'dino_run',
      refId: `${userId}-${Date.now()}`,
      points,
      note: `Sycamore Run score ${finalScore}`
    })
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
    const { data } = await supabase
      .from('dino_runner_scores')
      .select('user_id, score')
    const bestByUser = new Map<string, number>()
    for (const row of (data ?? []) as Array<{ user_id: string; score: number }>) {
      const cur = bestByUser.get(row.user_id) ?? 0
      if (row.score > cur) bestByUser.set(row.user_id, row.score)
    }
    const userIds = Array.from(bestByUser.keys())
    if (userIds.length === 0) {
      leaderboard.value = []
      return
    }
    const [{ data: staff }, { data: profiles }] = await Promise.all([
      supabase.from('staff_members').select('full_name, role, auth_user_id').in('auth_user_id', userIds),
      supabase.from('user_profiles').select('user_id, avatar_url').in('user_id', userIds)
    ])
    const staffMap = new Map((staff ?? []).map((s: any) => [s.auth_user_id, s]))
    const profMap = new Map((profiles ?? []).map((p: any) => [p.user_id, p]))
    leaderboard.value = userIds
      .map(uid => {
        const s = staffMap.get(uid) as any
        const p = profMap.get(uid) as any
        return {
          user_id: uid,
          best: bestByUser.get(uid) ?? 0,
          name: s?.full_name || 'Sycamore staff',
          avatar: p?.avatar_url ?? null,
          role: s?.role ?? null
        }
      })
      .sort((a, b) => b.best - a.best)
      .slice(0, 10)
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

onMounted(() => {
  fitCanvas()
  window.addEventListener('resize', fitCanvas)
  window.addEventListener('keydown', onKeyDown)
  window.addEventListener('keyup', onKeyUp)
  void loadPersonalBest()
  void loadLeaderboard()
  draw()
})

onBeforeUnmount(() => {
  if (rafId !== null) cancelAnimationFrame(rafId)
  window.removeEventListener('resize', fitCanvas)
  window.removeEventListener('keydown', onKeyDown)
  window.removeEventListener('keyup', onKeyUp)
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

    <div ref="containerRef" class="bg-white border border-slate-200 rounded-3xl p-3 sm:p-4 shadow-sm">
      <div class="relative" @touchstart="onTouchStart">
        <canvas
          ref="canvasRef"
          class="block w-full rounded-2xl bg-emerald-50/40 border border-emerald-100"
          tabindex="0"
        />

        <div
          v-if="phase === 'idle'"
          class="absolute inset-0 flex flex-col items-center justify-center text-center px-4"
        >
          <div class="bg-white/90 backdrop-blur rounded-2xl border border-emerald-200 px-6 py-5 max-w-sm shadow">
            <div class="text-emerald-700 font-bold uppercase tracking-[0.2em] text-[11px]">Ready</div>
            <div class="text-lg font-semibold text-slate-900 mt-1">Tap or press Space to run</div>
            <div class="mt-2 text-xs text-slate-500">Up arrow / Space to jump &middot; Down arrow to duck</div>
            <button
              type="button"
              class="mt-4 inline-flex items-center justify-center px-5 py-2.5 rounded-full bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-semibold"
              @click="startGame"
            >
              Start running
            </button>
          </div>
        </div>

        <div
          v-else-if="phase === 'over'"
          class="absolute inset-0 flex flex-col items-center justify-center text-center px-4"
        >
          <div class="bg-white/95 backdrop-blur rounded-2xl border border-emerald-200 px-6 py-5 max-w-sm shadow-lg">
            <div class="text-emerald-700 font-bold uppercase tracking-[0.2em] text-[11px]">Run finished</div>
            <div class="mt-1 text-2xl sm:text-3xl font-bold text-slate-900 tabular-nums">{{ lastScore }}</div>
            <div v-if="lastIsPb" class="mt-1 text-emerald-700 text-sm font-semibold">New personal best!</div>
            <div v-else class="mt-1 text-slate-500 text-xs">Personal best: {{ personalBest }}</div>
            <button
              type="button"
              class="mt-4 inline-flex items-center justify-center px-5 py-2.5 rounded-full bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-semibold"
              @click="startGame"
            >
              Run again
            </button>
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
        <button
          type="button"
          class="text-xs text-emerald-700 hover:text-emerald-800 font-semibold"
          @click="loadLeaderboard"
        >
          Refresh
        </button>
      </div>

      <div v-if="loadingBoard" class="text-sm text-slate-400 py-6 text-center">Loading leaderboard...</div>
      <div v-else-if="leaderboard.length === 0" class="text-sm text-slate-400 py-6 text-center bg-white border border-slate-200 rounded-2xl">
        No runs yet. Be the first to set a record.
      </div>
      <ul v-else class="bg-white border border-slate-200 rounded-2xl divide-y divide-slate-100 overflow-hidden">
        <li
          v-for="(row, i) in leaderboard"
          :key="row.user_id"
          class="flex items-center gap-3 px-4 py-3"
        >
          <div
            class="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold"
            :class="i === 0 ? 'bg-amber-100 text-amber-700' : i === 1 ? 'bg-slate-200 text-slate-700' : i === 2 ? 'bg-orange-100 text-orange-700' : 'bg-slate-100 text-slate-500'"
          >
            {{ i + 1 }}
          </div>
          <img
            v-if="row.avatar"
            :src="row.avatar"
            :alt="row.name"
            class="w-9 h-9 rounded-full object-cover border border-slate-200"
          />
          <div v-else class="w-9 h-9 rounded-full bg-emerald-100 text-emerald-700 font-bold flex items-center justify-center text-sm">
            {{ (row.name?.[0] ?? '?').toUpperCase() }}
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-sm font-semibold text-slate-900 truncate">{{ row.name }}</div>
            <div v-if="row.role" class="text-xs text-slate-500 truncate">{{ row.role }}</div>
          </div>
          <div class="text-base font-bold text-slate-900 tabular-nums">{{ row.best }}</div>
        </li>
      </ul>
    </section>
  </div>
</template>
