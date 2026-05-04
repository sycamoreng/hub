<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { useGamification, colorClasses } from '~/composables/useGamification'
import type { LeaderRow, KudosValue, Badge } from '~/composables/useGamification'

definePageMeta({ middleware: ['auth'] })

const { user } = useAuth()
const supabase = useSupabase()
const toast = useToast()
const { getLeaderboard, giveKudos, loadRecentKudos, loadKudosValues, loadBadges, loadUserBadges, getUserPoints } = useGamification()

const scope = ref<'week' | 'month' | 'all'>('month')
const leaders = ref<LeaderRow[]>([])
const loadingLeaders = ref(true)

const recentKudos = ref<any[]>([])
const kudosUserMap = ref<Record<string, any>>({})
const loadingKudos = ref(true)

const values = ref<KudosValue[]>([])
const badges = ref<Badge[]>([])
const myBadgeIds = ref<Set<string>>(new Set())
const myPoints = ref(0)
const myRank = ref<number | null>(null)

const colleagues = ref<Array<{ id: string; full_name: string; auth_user_id: string; role: string }>>([])

const modal = ref<{ open: boolean; toUserId: string; valueCode: string; message: string }>({
  open: false,
  toUserId: '',
  valueCode: 'teamwork',
  message: ''
})
const saving = ref(false)

async function loadLeaders() {
  loadingLeaders.value = true
  try {
    leaders.value = await getLeaderboard(scope.value, 25)
    if (user.value) {
      const idx = leaders.value.findIndex(l => l.user_id === user.value!.id)
      myRank.value = idx === -1 ? null : idx + 1
    }
  } finally {
    loadingLeaders.value = false
  }
}

async function loadAll() {
  const tasks: Promise<any>[] = [
    loadLeaders(),
    (async () => {
      loadingKudos.value = true
      try {
        const { rows, userMap } = await loadRecentKudos(30)
        recentKudos.value = rows
        kudosUserMap.value = userMap
      } finally {
        loadingKudos.value = false
      }
    })(),
    loadKudosValues().then(v => { values.value = v }),
    loadBadges().then(b => { badges.value = b }),
    (async () => {
      if (!user.value) return
      const [points, owned] = await Promise.all([
        getUserPoints(user.value.id),
        loadUserBadges(user.value.id)
      ])
      myPoints.value = points
      myBadgeIds.value = new Set(owned.map((r: any) => r.badge_id))
    })(),
    (async () => {
      const { data } = await supabase
        .from('staff_members')
        .select('id, full_name, auth_user_id, role')
        .eq('is_active', true)
        .not('auth_user_id', 'is', null)
        .order('full_name')
      colleagues.value = (data ?? []).filter((c: any) => c.auth_user_id !== user.value?.id) as any
    })()
  ]
  await Promise.all(tasks)
}

watch(scope, () => { loadLeaders() })

onMounted(loadAll)

function openKudos(toUserId = '') {
  modal.value = {
    open: true,
    toUserId,
    valueCode: values.value[0]?.code ?? 'teamwork',
    message: ''
  }
}

async function submitKudos() {
  if (!modal.value.toUserId) { toast.error('Pick a colleague'); return }
  if (!modal.value.message.trim()) { toast.error('Write a quick note'); return }
  saving.value = true
  try {
    await giveKudos({
      toUserId: modal.value.toUserId,
      valueCode: modal.value.valueCode,
      message: modal.value.message.trim()
    })
    toast.success('Kudos sent!')
    modal.value.open = false
    await loadAll()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to send kudos')
  } finally {
    saving.value = false
  }
}

function initials(name: string) {
  return (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]?.toUpperCase() ?? '').join('') || '?'
}

function relativeTime(iso: string) {
  const diff = Date.now() - new Date(iso).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  const days = Math.floor(hrs / 24)
  if (days < 7) return `${days}d ago`
  return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
}

function valueByCode(code: string): KudosValue | undefined {
  return values.value.find(v => v.code === code)
}

function rankMedal(i: number): string {
  if (i === 0) return 'bg-amber-100 text-amber-700 border-amber-200'
  if (i === 1) return 'bg-slate-100 text-slate-700 border-slate-200'
  if (i === 2) return 'bg-orange-100 text-orange-700 border-orange-200'
  return 'bg-white text-slate-500 border-slate-200'
}
</script>

<template>
  <div class="max-w-6xl mx-auto space-y-8">
    <header class="relative overflow-hidden rounded-3xl bg-gradient-to-br from-sycamore-700 via-sycamore-600 to-leaf-600 p-8 sm:p-10 text-white">
      <div class="absolute -top-12 -right-12 w-64 h-64 rounded-full bg-white/10 blur-2xl"></div>
      <div class="absolute -bottom-16 -left-10 w-72 h-72 rounded-full bg-leaf-400/20 blur-3xl"></div>
      <div class="relative flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
        <div>
          <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/15 ring-1 ring-white/20 text-[11px] font-semibold uppercase tracking-[0.2em]">
            <span class="w-1.5 h-1.5 rounded-full bg-leaf-300"></span>
            Recognition
          </div>
          <h1 class="mt-3 text-3xl sm:text-4xl font-bold tracking-tight leading-tight">Celebrate the team</h1>
          <p class="mt-2 text-white/80 text-sm sm:text-base max-w-xl">Give kudos, earn points, climb the leaderboard, and collect badges along the way.</p>
        </div>
        <div class="flex items-center gap-3">
          <div class="text-right">
            <div class="text-[11px] uppercase tracking-wide text-white/70 font-semibold">Your points</div>
            <div class="text-3xl font-bold tabular-nums">{{ myPoints }}</div>
            <div v-if="myRank" class="text-[11px] text-white/70">Rank #{{ myRank }} this {{ scope === 'all' ? 'time' : scope }}</div>
          </div>
          <button type="button" @click="openKudos()" class="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-white text-sycamore-700 font-semibold text-sm hover:bg-slate-100 transition-colors shadow-sm">
            Give kudos
          </button>
        </div>
      </div>
    </header>

    <section class="grid lg:grid-cols-3 gap-6">
      <div class="lg:col-span-2 bg-white border border-slate-200 rounded-2xl overflow-hidden">
        <header class="px-5 py-4 border-b border-slate-100 flex items-center justify-between gap-3">
          <div>
            <h2 class="text-sm font-semibold text-slate-900">Leaderboard</h2>
            <p class="text-xs text-slate-500">Points awarded from posts, kudos, learning, and sparks.</p>
          </div>
          <div class="inline-flex p-0.5 bg-slate-100 rounded-lg text-xs font-medium">
            <button type="button" v-for="opt in (['week','month','all'] as const)" :key="opt" @click="scope = opt" :class="scope === opt ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'" class="px-3 py-1 rounded-md capitalize transition-colors">
              {{ opt === 'all' ? 'All time' : opt }}
            </button>
          </div>
        </header>
        <div v-if="loadingLeaders" class="p-6 text-sm text-slate-400">Loading leaderboard...</div>
        <div v-else-if="leaders.length === 0" class="p-8 text-center text-sm text-slate-400">
          No activity yet in this window. Kick things off with a post or some kudos.
        </div>
        <ul v-else class="divide-y divide-slate-100">
          <li v-for="(row, i) in leaders" :key="row.user_id" class="flex items-center gap-4 px-5 py-3" :class="row.user_id === user?.id ? 'bg-sycamore-50/60' : ''">
            <div class="w-8 h-8 rounded-full border text-xs font-bold flex items-center justify-center tabular-nums" :class="rankMedal(i)">{{ i + 1 }}</div>
            <NuxtLink v-if="row.staff_id" :to="`/profile/${row.staff_id}`" class="flex items-center gap-3 min-w-0 flex-1">
              <img v-if="row.avatar" :src="row.avatar" :alt="row.name" referrerpolicy="no-referrer" class="w-10 h-10 rounded-full object-cover border border-slate-200" />
              <div v-else class="w-10 h-10 rounded-full bg-sycamore-100 text-sycamore-700 flex items-center justify-center text-sm font-semibold">{{ initials(row.name) }}</div>
              <div class="min-w-0">
                <div class="font-semibold text-sm text-slate-900 truncate">{{ row.name }}</div>
                <div class="text-xs text-slate-500 truncate">{{ row.role || '' }}</div>
              </div>
            </NuxtLink>
            <div v-else class="flex items-center gap-3 min-w-0 flex-1">
              <div class="w-10 h-10 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center text-sm font-semibold">{{ initials(row.name) }}</div>
              <div class="min-w-0">
                <div class="font-semibold text-sm text-slate-900 truncate">{{ row.name }}</div>
              </div>
            </div>
            <div class="text-right">
              <div class="text-lg font-bold text-slate-900 tabular-nums">{{ row.points }}</div>
              <div class="text-[10px] uppercase tracking-wide text-slate-400 font-semibold">points</div>
            </div>
          </li>
        </ul>
      </div>

      <div class="bg-white border border-slate-200 rounded-2xl p-5">
        <h2 class="text-sm font-semibold text-slate-900">Your badges</h2>
        <p class="text-xs text-slate-500">Milestones auto-awarded as you contribute.</p>
        <div v-if="badges.length === 0" class="mt-4 text-sm text-slate-400">No badges yet.</div>
        <ul v-else class="mt-4 space-y-3">
          <li v-for="b in badges" :key="b.id" class="flex items-center gap-3" :class="myBadgeIds.has(b.id) ? '' : 'opacity-50'">
            <div class="w-11 h-11 rounded-xl flex items-center justify-center text-xl ring-2" :class="[colorClasses(b.color).bg, colorClasses(b.color).text, colorClasses(b.color).ring]">
              {{ b.emoji || '🏅' }}
            </div>
            <div class="min-w-0 flex-1">
              <div class="font-semibold text-sm text-slate-900 truncate">{{ b.name }}</div>
              <div class="text-xs text-slate-500 truncate">{{ b.description }}</div>
            </div>
            <span v-if="myBadgeIds.has(b.id)" class="text-[10px] uppercase tracking-wide text-emerald-600 font-bold">Earned</span>
            <span v-else class="text-[10px] uppercase tracking-wide text-slate-400 font-semibold">Locked</span>
          </li>
        </ul>
      </div>
    </section>

    <section>
      <div class="flex items-end justify-between mb-4">
        <div>
          <h2 class="text-xl font-bold text-slate-900 tracking-tight">Recent kudos</h2>
          <p class="text-sm text-slate-500">The wall of appreciation.</p>
        </div>
        <button type="button" @click="openKudos()" class="text-sm text-sycamore-700 font-medium hover:underline">Send one</button>
      </div>
      <div v-if="loadingKudos" class="text-sm text-slate-400">Loading...</div>
      <div v-else-if="recentKudos.length === 0" class="bg-white border border-dashed border-slate-200 rounded-2xl p-10 text-center text-sm text-slate-400">
        No kudos yet. Be the first to recognize a colleague.
      </div>
      <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <article v-for="k in recentKudos" :key="k.id" class="bg-white border border-slate-200 rounded-2xl p-5 flex flex-col gap-3 hover:border-sycamore-300 hover:shadow-sm transition-all">
          <div class="flex items-center gap-2">
            <span v-if="valueByCode(k.value_code)" class="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-0.5 rounded-full border" :class="[colorClasses(valueByCode(k.value_code)!.color).bg, colorClasses(valueByCode(k.value_code)!.color).text, colorClasses(valueByCode(k.value_code)!.color).border]">
              {{ valueByCode(k.value_code)!.emoji }} {{ valueByCode(k.value_code)!.label }}
            </span>
            <span class="text-[11px] text-slate-400 ml-auto">{{ relativeTime(k.created_at) }}</span>
          </div>
          <p class="text-sm text-slate-800 leading-relaxed">{{ k.message || '(no message)' }}</p>
          <div class="flex items-center gap-2 mt-auto pt-2 border-t border-slate-100">
            <div class="flex -space-x-2">
              <img v-if="kudosUserMap[k.from_user_id]?.avatar" :src="kudosUserMap[k.from_user_id]?.avatar" :alt="kudosUserMap[k.from_user_id]?.name" referrerpolicy="no-referrer" class="w-7 h-7 rounded-full object-cover border-2 border-white" />
              <div v-else class="w-7 h-7 rounded-full bg-slate-200 text-slate-600 flex items-center justify-center text-[10px] font-semibold border-2 border-white">{{ initials(kudosUserMap[k.from_user_id]?.name || '') }}</div>
              <img v-if="kudosUserMap[k.to_user_id]?.avatar" :src="kudosUserMap[k.to_user_id]?.avatar" :alt="kudosUserMap[k.to_user_id]?.name" referrerpolicy="no-referrer" class="w-7 h-7 rounded-full object-cover border-2 border-white" />
              <div v-else class="w-7 h-7 rounded-full bg-sycamore-100 text-sycamore-700 flex items-center justify-center text-[10px] font-semibold border-2 border-white">{{ initials(kudosUserMap[k.to_user_id]?.name || '') }}</div>
            </div>
            <div class="text-xs text-slate-600 min-w-0 truncate">
              <span class="font-semibold text-slate-900">{{ kudosUserMap[k.from_user_id]?.name || 'Someone' }}</span>
              <span class="text-slate-400"> → </span>
              <span class="font-semibold text-slate-900">{{ kudosUserMap[k.to_user_id]?.name || 'a colleague' }}</span>
            </div>
          </div>
        </article>
      </div>
    </section>

    <div v-if="modal.open" class="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4" @click.self="modal.open = false">
      <div class="bg-white rounded-2xl shadow-xl max-w-lg w-full overflow-hidden">
        <header class="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
          <div>
            <h3 class="font-semibold text-slate-900">Give kudos</h3>
            <p class="text-xs text-slate-500">Recognize a colleague with a quick shout-out.</p>
          </div>
          <button type="button" @click="modal.open = false" class="text-slate-400 hover:text-slate-700 text-xl leading-none">&times;</button>
        </header>
        <div class="p-5 space-y-4">
          <label class="block">
            <span class="text-xs font-medium text-slate-600">To</span>
            <select v-model="modal.toUserId" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm">
              <option value="">Pick a colleague...</option>
              <option v-for="c in colleagues" :key="c.id" :value="c.auth_user_id">{{ c.full_name }}<span v-if="c.role"> — {{ c.role }}</span></option>
            </select>
          </label>
          <div>
            <span class="text-xs font-medium text-slate-600">For</span>
            <div class="mt-2 flex flex-wrap gap-2">
              <button
                v-for="v in values"
                :key="v.id"
                type="button"
                @click="modal.valueCode = v.code"
                class="inline-flex items-center gap-1 px-3 py-1.5 text-xs font-semibold rounded-full border transition-colors"
                :class="modal.valueCode === v.code ? [colorClasses(v.color).bg, colorClasses(v.color).text, colorClasses(v.color).border] : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'"
              >
                {{ v.emoji }} {{ v.label }}
              </button>
            </div>
          </div>
          <label class="block">
            <span class="text-xs font-medium text-slate-600">Note</span>
            <textarea v-model="modal.message" rows="4" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" placeholder="Thanks for jumping in on the launch push..."></textarea>
          </label>
          <div class="flex justify-end gap-2 pt-2">
            <button type="button" @click="modal.open = false" class="px-4 py-2 text-sm font-medium text-slate-600 hover:bg-slate-100 rounded-lg">Cancel</button>
            <button type="button" :disabled="saving" @click="submitKudos" class="px-4 py-2 text-sm font-semibold bg-sycamore-600 hover:bg-sycamore-700 disabled:opacity-60 text-white rounded-lg">
              {{ saving ? 'Sending...' : 'Send kudos' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
