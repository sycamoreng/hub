<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { user, ready, isAdmin, profile } = useAuth()
const toast = useToast()
const route = useRoute()

interface Prize {
  id: string
  name: string
  icon: string
  color: string
}
interface Settings {
  status: 'draft' | 'sealed' | 'live' | 'closed'
  live_at: string | null
}
interface Allocation {
  id: string
  prize_id: string | null
  is_blank: boolean
  revealed_at: string | null
  prize?: Prize | null
}

const isPreview = computed(() => route.query.preview === '1' && isAdmin.value)

const settings = ref<Settings | null>(null)
const prizes = ref<Prize[]>([])
const allocation = ref<Allocation | null>(null)
const loading = ref(true)
const spinning = ref(false)
const revealed = ref(false)
const rotation = ref(0)
const countdown = ref<string>('')

// Wheel segments: prizes + blank(s). One visible "Better luck" segment for color purposes.
const segments = computed(() => {
  const list = prizes.value.map(p => ({ ...p, isBlank: false }))
  list.push({
    id: 'blank',
    name: 'Better luck next time',
    icon: 'close',
    color: '#64748b',
    isBlank: true
  } as any)
  return list
})

const segmentAngle = computed(() => 360 / Math.max(1, segments.value.length))

async function loadAll() {
  loading.value = true
  try {
    const [sRes, pRes] = await Promise.all([
      supabase.from('raffle_settings').select('status, live_at').eq('id', 1).maybeSingle(),
      supabase.from('raffle_prizes').select('id, name, icon, color, display_order').order('display_order')
    ])
    settings.value = (sRes.data as Settings) || null
    prizes.value = (pRes.data as Prize[]) || []

    if (user.value && !isPreview.value) {
      const { data: staff } = await supabase
        .from('staff_members')
        .select('id')
        .eq('auth_user_id', user.value.id)
        .maybeSingle()
      if (staff) {
        const { data: alloc } = await supabase
          .from('raffle_allocations')
          .select('id, prize_id, is_blank, revealed_at')
          .eq('staff_member_id', (staff as any).id)
          .maybeSingle()
        if (alloc) {
          const a = alloc as any
          let prize: Prize | null = null
          if (a.prize_id && a.revealed_at) {
            prize = prizes.value.find(p => p.id === a.prize_id) || null
          }
          allocation.value = { ...a, prize }
          if (a.revealed_at) revealed.value = true
        }
      }
    }
  } finally {
    loading.value = false
  }
}

function updateCountdown() {
  if (!settings.value?.live_at || settings.value.status !== 'sealed') {
    countdown.value = ''
    return
  }
  const ms = new Date(settings.value.live_at).getTime() - Date.now()
  if (ms <= 0) { countdown.value = ''; return }
  const h = Math.floor(ms / 3_600_000)
  const m = Math.floor((ms % 3_600_000) / 60_000)
  const s = Math.floor((ms % 60_000) / 1000)
  countdown.value = `${h}h ${m}m ${s}s`
}

let timer: any
onMounted(() => {
  timer = setInterval(updateCountdown, 1000)
})
onBeforeUnmount(() => clearInterval(timer))

watch(ready, (v) => { if (v) loadAll() }, { immediate: true })

async function spin() {
  if (spinning.value) return
  spinning.value = true

  let targetIndex: number
  let outcomePrize: Prize | null = null
  let outcomeBlank = false

  if (isPreview.value) {
    // Fake reveal for admin preview
    const pool = segments.value
    const pick = pool[Math.floor(Math.random() * pool.length)]
    targetIndex = segments.value.findIndex(s => s.id === pick.id)
    outcomeBlank = pick.isBlank
    outcomePrize = pick.isBlank ? null : (pick as any)
  } else {
    const { data, error } = await supabase.rpc('raffle_reveal')
    if (error) {
      spinning.value = false
      toast.error(error.message)
      return
    }
    const res = data as any
    outcomeBlank = !!res.is_blank
    if (res.prize) {
      outcomePrize = res.prize as Prize
      targetIndex = segments.value.findIndex(s => s.id === outcomePrize!.id)
    } else {
      targetIndex = segments.value.findIndex(s => (s as any).isBlank)
    }
  }

  // Spin animation: multiple full turns + land with the target segment under the pointer (top, 0deg)
  const full = 360 * 6
  const seg = segmentAngle.value
  // pointer is at top (12 o'clock). Segment i occupies angles [i*seg, (i+1)*seg] before rotation.
  // We want the middle of segment targetIndex at 0 (top). Our visual rotation applies clockwise.
  const mid = (targetIndex + 0.5) * seg
  const finalRotation = full + (360 - mid)
  rotation.value = finalRotation

  setTimeout(() => {
    spinning.value = false
    revealed.value = true
    if (!isPreview.value && allocation.value) {
      allocation.value = {
        ...allocation.value,
        is_blank: outcomeBlank,
        prize_id: outcomePrize?.id ?? null,
        revealed_at: new Date().toISOString(),
        prize: outcomePrize
      }
    } else if (isPreview.value) {
      allocation.value = {
        id: 'preview',
        prize_id: outcomePrize?.id ?? null,
        is_blank: outcomeBlank,
        revealed_at: new Date().toISOString(),
        prize: outcomePrize
      } as Allocation
    }
    if (!outcomeBlank) launchConfetti()
  }, 5200)
}

const confettiPieces = ref<{ id: number; left: number; delay: number; color: string; rotate: number }[]>([])
function launchConfetti() {
  const colors = ['#1f6f9c', '#109847', '#f59e0b', '#ef4444', '#ec4899', '#eab308', '#06b6d4']
  const pieces = []
  for (let i = 0; i < 80; i++) {
    pieces.push({
      id: i,
      left: Math.random() * 100,
      delay: Math.random() * 0.4,
      color: colors[Math.floor(Math.random() * colors.length)],
      rotate: Math.random() * 360
    })
  }
  confettiPieces.value = pieces
  setTimeout(() => { confettiPieces.value = [] }, 3500)
}

function resetPreview() {
  allocation.value = null
  revealed.value = false
  rotation.value = 0
}
</script>

<template>
  <div class="relative min-h-[calc(100vh-6rem)] flex items-center justify-center overflow-hidden py-8">
    <!-- Background flourish -->
    <div class="absolute inset-0 -z-10">
      <div class="absolute top-1/4 left-1/4 w-96 h-96 bg-sycamore-200 rounded-full blur-3xl opacity-30"></div>
      <div class="absolute bottom-1/4 right-1/4 w-96 h-96 bg-leaf-200 rounded-full blur-3xl opacity-40"></div>
    </div>

    <!-- Confetti -->
    <div class="pointer-events-none fixed inset-0 z-50 overflow-hidden" v-if="confettiPieces.length">
      <span
        v-for="c in confettiPieces" :key="c.id"
        class="absolute block w-2 h-3 rounded-sm"
        :style="{
          left: c.left + '%',
          top: '-20px',
          backgroundColor: c.color,
          transform: `rotate(${c.rotate}deg)`,
          animation: `confetti-fall 3s ${c.delay}s linear forwards`
        }"
      ></span>
    </div>

    <div class="w-full max-w-4xl mx-auto">
      <div v-if="loading" class="text-center text-slate-500">Loading...</div>

      <template v-else>
        <div class="text-center mb-6">
          <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-leaf-100 text-leaf-800 text-xs font-semibold tracking-wide uppercase">
            <span class="w-2 h-2 rounded-full bg-leaf-500"></span>
            Workers' Day Raffle
          </div>
          <h1 class="mt-3 text-3xl sm:text-4xl font-bold text-slate-900">
            {{ revealed && allocation && !allocation.is_blank ? "You won!" :
               revealed && allocation && allocation.is_blank ? "Thank you for spinning" :
               "Spin the wheel" }}
          </h1>
          <p v-if="!revealed" class="text-slate-600 mt-2 max-w-md mx-auto text-sm">
            Happy Workers' Day! You get one spin. Tap the button to reveal your prize.
          </p>
          <div v-if="isPreview" class="mt-2 inline-block px-2 py-0.5 rounded bg-amber-100 text-amber-800 text-xs font-medium">
            PREVIEW MODE (admin test spin)
          </div>
        </div>

        <!-- Pre-live states -->
        <div v-if="!isPreview && (!settings || settings.status === 'draft' || settings.status === 'sealed')"
          class="max-w-md mx-auto bg-white border border-slate-200 rounded-2xl p-8 text-center shadow-lg">
          <div class="w-16 h-16 mx-auto rounded-full bg-sycamore-50 flex items-center justify-center mb-4">
            <SidebarIcon name="calendar" />
          </div>
          <div class="font-semibold text-slate-900 text-lg">The raffle isn't live yet</div>
          <div class="text-sm text-slate-500 mt-2">
            <template v-if="settings?.status === 'sealed' && settings.live_at">
              Goes live {{ new Date(settings.live_at).toLocaleString() }}
            </template>
            <template v-else>
              Please check back at 10am on May 1st.
            </template>
          </div>
          <div v-if="countdown" class="mt-4 text-2xl font-bold text-sycamore-700">{{ countdown }}</div>
        </div>

        <!-- Wheel + button (or revealed card) -->
        <div v-else class="grid md:grid-cols-2 gap-8 items-center">
          <!-- Wheel -->
          <div class="relative mx-auto w-[340px] h-[340px] sm:w-[400px] sm:h-[400px]">
            <!-- Pointer -->
            <div class="absolute -top-2 left-1/2 -translate-x-1/2 z-20">
              <svg width="40" height="48" viewBox="0 0 40 48">
                <path d="M20 48 L0 8 Q0 0 8 0 L32 0 Q40 0 40 8 Z" fill="#0a445c" />
                <circle cx="20" cy="12" r="5" fill="#fff" />
              </svg>
            </div>
            <!-- Outer ring -->
            <div class="absolute inset-0 rounded-full shadow-2xl ring-8 ring-sycamore-700"></div>
            <!-- Wheel -->
            <div
              class="relative w-full h-full rounded-full overflow-hidden"
              :style="{
                transform: `rotate(${rotation}deg)`,
                transition: spinning ? 'transform 5s cubic-bezier(0.17, 0.67, 0.12, 0.99)' : 'none'
              }"
            >
              <svg viewBox="-100 -100 200 200" class="w-full h-full block">
                <g v-for="(seg, i) in segments" :key="seg.id">
                  <path
                    :d="`M 0 0 L ${Math.cos((-90 + i * segmentAngle) * Math.PI / 180) * 100} ${Math.sin((-90 + i * segmentAngle) * Math.PI / 180) * 100} A 100 100 0 0 1 ${Math.cos((-90 + (i + 1) * segmentAngle) * Math.PI / 180) * 100} ${Math.sin((-90 + (i + 1) * segmentAngle) * Math.PI / 180) * 100} Z`"
                    :fill="seg.color"
                    stroke="#ffffff"
                    stroke-width="1"
                  />
                  <g :transform="`rotate(${(i + 0.5) * segmentAngle - 90}) translate(60 0)`">
                    <text
                      text-anchor="middle"
                      fill="white"
                      font-size="7"
                      font-weight="700"
                      :transform="`rotate(90)`"
                    >
                      <tspan v-for="(w, wi) in seg.name.split(' ')" :key="wi" x="0" :dy="wi === 0 ? 0 : 8">{{ w }}</tspan>
                    </text>
                  </g>
                </g>
                <circle r="14" fill="#0a445c" />
                <circle r="10" fill="#ffffff" />
                <circle r="4" fill="#0a445c" />
              </svg>
            </div>
          </div>

          <!-- Action / Reveal panel -->
          <div class="text-center md:text-left">
            <div v-if="!revealed">
              <p class="text-slate-600 mb-6">
                Hi {{ profile?.name?.split(' ')[0] || 'there' }} — ready? You get one spin only.
              </p>
              <button
                :disabled="spinning || (!isPreview && !allocation)"
                @click="spin"
                class="inline-flex items-center gap-2 px-8 py-4 rounded-2xl bg-gradient-to-br from-sycamore-600 to-sycamore-800 text-white text-lg font-bold shadow-xl hover:shadow-2xl hover:scale-[1.02] transition-all disabled:opacity-60 disabled:cursor-not-allowed disabled:hover:scale-100"
              >
                <SidebarIcon name="sparkle" />
                {{ spinning ? 'Spinning...' : 'Spin the wheel' }}
              </button>
              <div v-if="!isPreview && !allocation && !spinning" class="mt-4 text-sm text-amber-700 bg-amber-50 border border-amber-200 rounded-lg p-3">
                No allocation found for your account. Please ask HR to confirm your staff record.
              </div>
            </div>

            <div v-else-if="allocation && !allocation.is_blank && allocation.prize"
              class="p-8 rounded-2xl bg-white border border-slate-200 shadow-xl">
              <div class="text-xs font-semibold uppercase tracking-wide text-leaf-700 mb-2">Congratulations</div>
              <div class="w-20 h-20 rounded-2xl flex items-center justify-center text-white shadow-lg mb-4"
                :style="{ backgroundColor: allocation.prize.color }">
                <SidebarIcon :name="allocation.prize.icon" />
              </div>
              <div class="text-2xl font-bold text-slate-900">{{ allocation.prize.name }}</div>
              <p class="text-sm text-slate-600 mt-3">Please visit HR to collect your prize. Happy Workers' Day!</p>
              <button v-if="isPreview" @click="resetPreview"
                class="mt-4 text-xs text-slate-500 underline">Reset preview</button>
            </div>

            <div v-else class="p-8 rounded-2xl bg-white border border-slate-200 shadow-xl">
              <div class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">No prize this time</div>
              <div class="text-2xl font-bold text-slate-900">Better luck next time</div>
              <p class="text-sm text-slate-600 mt-3">
                Thank you for all your hard work. Happy Workers' Day from everyone at Sycamore!
              </p>
              <button v-if="isPreview" @click="resetPreview"
                class="mt-4 text-xs text-slate-500 underline">Reset preview</button>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
@keyframes confetti-fall {
  0% { transform: translateY(0) rotate(0deg); opacity: 1; }
  100% { transform: translateY(110vh) rotate(720deg); opacity: 0.8; }
}
</style>
