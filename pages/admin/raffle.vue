<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

definePageMeta({ layout: 'admin' })

const supabase = useSupabase()
const { isAdmin, isSuperAdmin, ready } = useAuth()
const toast = useToast()

interface Prize {
  id: string
  name: string
  icon: string
  color: string
  quantity: number
  display_order: number
}
interface Settings {
  id: number
  status: 'draft' | 'sealed' | 'live' | 'closed'
  blanks_count: number
  sealed_at: string | null
  live_at: string | null
  closed_at: string | null
  visible_on_sidebar: boolean
}
interface AllocationRow {
  staff_id: string
  full_name: string
  email: string
  is_blank: boolean | null
  prize_id: string | null
  prize_name: string | null
  prize_color: string | null
  prize_icon: string | null
  revealed_at: string | null
}
interface SimulationRow {
  staff_id: string
  full_name: string
  email: string
  prize_name: string | null
  is_blank: boolean
}
interface Stats {
  total: number
  revealed: number
  pending: number
  blanks_total: number
  blanks_revealed: number
  by_prize: { prize_id: string; name: string; quantity: number; revealed: number }[]
}

const prizes = ref<Prize[]>([])
const settings = ref<Settings | null>(null)
const staffCount = ref(0)
const simulation = ref<SimulationRow[]>([])
const stats = ref<Stats | null>(null)
const allocations = ref<AllocationRow[]>([])
const allocationsFilter = ref<'all' | 'revealed' | 'pending'>('all')
const loading = ref(false)
const busy = ref(false)

const prizeTotal = computed(() => prizes.value.reduce((s, p) => s + (p.quantity || 0), 0))
const grandTotal = computed(() => prizeTotal.value + (settings.value?.blanks_count || 0))
const slotMismatch = computed(() => grandTotal.value !== staffCount.value)

async function loadAll() {
  loading.value = true
  try {
    const [pRes, sRes, cntRes] = await Promise.all([
      supabase.from('raffle_prizes').select('*').order('display_order'),
      supabase.from('raffle_settings').select('*').eq('id', 1).maybeSingle(),
      supabase.from('staff_members').select('id', { count: 'exact', head: true }).neq('is_active', false)
    ])
    prizes.value = (pRes.data as Prize[]) || []
    settings.value = (sRes.data as Settings) || null
    staffCount.value = cntRes.count || 0
    if (settings.value && settings.value.status !== 'draft') {
      await Promise.all([loadStats(), loadAllocations()])
    }
  } finally {
    loading.value = false
  }
}

async function loadAllocations() {
  const { data, error } = await supabase.rpc('raffle_allocations_admin')
  if (error) { toast.error(error.message); return }
  allocations.value = (data as AllocationRow[]) || []
}

async function toggleSidebarVisibility() {
  if (!settings.value) return
  const next = !settings.value.visible_on_sidebar
  const { error } = await supabase
    .from('raffle_settings')
    .update({ visible_on_sidebar: next })
    .eq('id', 1)
  if (error) { toast.error(error.message); return }
  settings.value.visible_on_sidebar = next
  toast.success(next ? 'Raffle link visible in sidebar' : 'Raffle link hidden from sidebar')
}

async function loadStats() {
  const { data, error } = await supabase.rpc('raffle_stats')
  if (error) { toast.error(error.message); return }
  stats.value = data as Stats
}

async function savePrize(p: Prize) {
  const { error } = await supabase
    .from('raffle_prizes')
    .update({ quantity: p.quantity })
    .eq('id', p.id)
  if (error) { toast.error(error.message); return }
  toast.success(`${p.name} saved`)
}

async function saveBlanks() {
  if (!settings.value) return
  const { error } = await supabase
    .from('raffle_settings')
    .update({ blanks_count: settings.value.blanks_count })
    .eq('id', 1)
  if (error) { toast.error(error.message); return }
  toast.success('Blanks updated')
}

async function runSimulation() {
  busy.value = true
  try {
    const { data, error } = await supabase.rpc('raffle_simulate')
    if (error) { toast.error(error.message); return }
    simulation.value = (data as SimulationRow[]) || []
    toast.success(`Simulated ${simulation.value.length} allocations`)
  } finally {
    busy.value = false
  }
}

const filteredAllocations = computed(() => {
  if (allocationsFilter.value === 'revealed') return allocations.value.filter(r => r.revealed_at)
  if (allocationsFilter.value === 'pending') return allocations.value.filter(r => !r.revealed_at)
  return allocations.value
})

function downloadCsv() {
  const rows = allocations.value
  const header = ['Staff','Email','Outcome','Revealed at']
  const lines = [header.join(',')]
  for (const r of rows) {
    const outcome = r.prize_name ? r.prize_name : (r.is_blank === true ? 'Better luck next time' : 'Not allocated')
    lines.push([
      `"${(r.full_name || '').replace(/"/g,'""')}"`,
      `"${(r.email || '').replace(/"/g,'""')}"`,
      `"${outcome.replace(/"/g,'""')}"`,
      r.revealed_at ? new Date(r.revealed_at).toISOString() : ''
    ].join(','))
  }
  const blob = new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `raffle-results-${new Date().toISOString().slice(0,10)}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

const simulationSummary = computed(() => {
  const map = new Map<string, number>()
  for (const row of simulation.value) {
    const key = row.is_blank ? 'Better luck next time' : (row.prize_name || 'Unknown')
    map.set(key, (map.get(key) || 0) + 1)
  }
  return Array.from(map.entries()).map(([name, count]) => ({ name, count }))
})

async function seal() {
  if (!confirm('Seal the raffle? This commits the shuffle and cannot be easily undone. Proceed?')) return
  busy.value = true
  try {
    const { error } = await supabase.rpc('raffle_seed')
    if (error) { toast.error(error.message); return }
    toast.success('Raffle sealed')
    await loadAll()
  } finally {
    busy.value = false
  }
}

async function goLive() {
  if (!confirm('Go live? Staff will be able to spin immediately.')) return
  busy.value = true
  try {
    const { error } = await supabase.rpc('raffle_set_status', { new_status: 'live' })
    if (error) { toast.error(error.message); return }
    toast.success('Raffle is LIVE')
    await loadAll()
  } finally {
    busy.value = false
  }
}

async function close() {
  if (!confirm('Close the raffle? No further spins will be possible.')) return
  busy.value = true
  try {
    const { error } = await supabase.rpc('raffle_set_status', { new_status: 'closed' })
    if (error) { toast.error(error.message); return }
    toast.success('Raffle closed')
    await loadAll()
  } finally {
    busy.value = false
  }
}

async function reset() {
  if (!confirm('RESET everything? This wipes all allocations and returns to draft. Super admin only.')) return
  if (!confirm('Really reset? Type OK in the next prompt.')) return
  const ack = prompt('Type OK to confirm reset:')
  if (ack !== 'OK') return
  busy.value = true
  try {
    const { error } = await supabase.rpc('raffle_reset')
    if (error) { toast.error(error.message); return }
    toast.success('Raffle reset to draft')
    simulation.value = []
    stats.value = null
    await loadAll()
  } finally {
    busy.value = false
  }
}

watch(ready, (v) => { if (v && isAdmin.value) loadAll() }, { immediate: true })
</script>

<template>
  <div class="space-y-8">
    <div class="flex items-start justify-between gap-4 flex-wrap">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">Workers' Day Raffle</h1>
        <p class="text-sm text-slate-500 mt-1">Configure, simulate, seal, and run the May 1st draw.</p>
      </div>
      <div class="flex items-center gap-2 flex-wrap">
        <label v-if="settings" class="inline-flex items-center gap-2 px-3 py-2 rounded-lg border border-slate-300 bg-white text-sm text-slate-700 cursor-pointer hover:bg-slate-50">
          <input
            type="checkbox"
            :checked="settings.visible_on_sidebar"
            @change="toggleSidebarVisibility"
            class="rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-500"
          />
          Show in sidebar
        </label>
        <NuxtLink
          to="/raffle?preview=1"
          target="_blank"
          class="px-3 py-2 rounded-lg border border-slate-300 text-slate-700 text-sm font-medium hover:bg-slate-50"
        >
          Open test spin
        </NuxtLink>
      </div>
    </div>

    <div v-if="!isAdmin" class="p-6 bg-amber-50 border border-amber-200 rounded-xl text-amber-900 text-sm">
      Admin access required.
    </div>

    <template v-else-if="settings">
      <!-- Status banner -->
      <div class="rounded-xl border p-5"
        :class="{
          'bg-slate-50 border-slate-200': settings.status === 'draft',
          'bg-sycamore-50 border-sycamore-200': settings.status === 'sealed',
          'bg-emerald-50 border-emerald-200': settings.status === 'live',
          'bg-slate-100 border-slate-300': settings.status === 'closed'
        }">
        <div class="flex items-center justify-between gap-4 flex-wrap">
          <div>
            <div class="text-xs uppercase tracking-wide font-semibold text-slate-500">Current status</div>
            <div class="text-xl font-bold mt-1"
              :class="{
                'text-slate-700': settings.status === 'draft',
                'text-sycamore-700': settings.status === 'sealed',
                'text-emerald-700': settings.status === 'live',
                'text-slate-700 grayscale': settings.status === 'closed'
              }">
              {{ settings.status.toUpperCase() }}
            </div>
            <div class="text-xs text-slate-500 mt-1">
              <span v-if="settings.sealed_at">Sealed: {{ new Date(settings.sealed_at).toLocaleString() }} · </span>
              <span v-if="settings.live_at">Live: {{ new Date(settings.live_at).toLocaleString() }} · </span>
              <span v-if="settings.closed_at">Closed: {{ new Date(settings.closed_at).toLocaleString() }}</span>
            </div>
          </div>
          <div class="flex gap-2 flex-wrap">
            <button v-if="settings.status === 'draft'"
              :disabled="busy || slotMismatch"
              @click="seal"
              class="px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-semibold hover:bg-sycamore-700 disabled:opacity-50 disabled:cursor-not-allowed">
              Seal raffle
            </button>
            <button v-if="settings.status === 'sealed'"
              :disabled="busy" @click="goLive"
              class="px-4 py-2 rounded-lg bg-emerald-600 text-white text-sm font-semibold hover:bg-emerald-700 disabled:opacity-50">
              Go live now
            </button>
            <button v-if="settings.status === 'live'"
              :disabled="busy" @click="close"
              class="px-4 py-2 rounded-lg bg-slate-800 text-white text-sm font-semibold hover:bg-slate-900 disabled:opacity-50">
              Close raffle
            </button>
            <button v-if="isSuperAdmin && settings.status !== 'draft'"
              :disabled="busy" @click="reset"
              class="px-4 py-2 rounded-lg border border-rose-300 text-rose-700 text-sm font-medium hover:bg-rose-50 disabled:opacity-50">
              Reset
            </button>
          </div>
        </div>
      </div>

      <!-- Slot math -->
      <div class="grid sm:grid-cols-4 gap-3">
        <div class="p-4 rounded-xl bg-white border border-slate-200">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Active staff</div>
          <div class="text-2xl font-bold text-slate-900 mt-1">{{ staffCount }}</div>
        </div>
        <div class="p-4 rounded-xl bg-white border border-slate-200">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Prize slots</div>
          <div class="text-2xl font-bold text-slate-900 mt-1">{{ prizeTotal }}</div>
        </div>
        <div class="p-4 rounded-xl bg-white border border-slate-200">
          <div class="text-xs text-slate-500 uppercase tracking-wide">Blanks</div>
          <div class="text-2xl font-bold text-slate-900 mt-1">{{ settings.blanks_count }}</div>
        </div>
        <div class="p-4 rounded-xl border"
          :class="slotMismatch ? 'bg-rose-50 border-rose-200' : 'bg-emerald-50 border-emerald-200'">
          <div class="text-xs uppercase tracking-wide"
            :class="slotMismatch ? 'text-rose-700' : 'text-emerald-700'">
            Total slots
          </div>
          <div class="text-2xl font-bold mt-1"
            :class="slotMismatch ? 'text-rose-700' : 'text-emerald-700'">
            {{ grandTotal }}
            <span class="text-sm font-medium">
              {{ slotMismatch ? `(off by ${grandTotal - staffCount})` : 'matches' }}
            </span>
          </div>
        </div>
      </div>

      <!-- Prize catalog -->
      <div class="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <div class="px-5 py-4 border-b border-slate-200 flex items-center justify-between">
          <h2 class="font-semibold text-slate-900">Prize catalog</h2>
          <span class="text-xs text-slate-500">Editable only while status = draft</span>
        </div>
        <div class="divide-y divide-slate-100">
          <div v-for="p in prizes" :key="p.id" class="flex items-center gap-4 px-5 py-3">
            <div class="w-10 h-10 rounded-lg flex items-center justify-center text-white font-bold"
              :style="{ backgroundColor: p.color }">
              <SidebarIcon :name="p.icon" />
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium text-slate-900 truncate">{{ p.name }}</div>
            </div>
            <input
              type="number" min="0"
              v-model.number="p.quantity"
              :disabled="settings.status !== 'draft'"
              class="w-24 px-3 py-2 rounded-lg border border-slate-300 text-sm text-right focus:outline-none focus:ring-2 focus:ring-sycamore-500 disabled:bg-slate-50"
            />
            <button
              v-if="settings.status === 'draft'"
              @click="savePrize(p)"
              class="px-3 py-2 rounded-lg bg-slate-900 text-white text-xs font-medium hover:bg-slate-800"
            >Save</button>
          </div>
          <div class="flex items-center gap-4 px-5 py-3 bg-slate-50">
            <div class="w-10 h-10 rounded-lg flex items-center justify-center bg-slate-300 text-slate-700 font-bold">
              <SidebarIcon name="close" />
            </div>
            <div class="flex-1 min-w-0">
              <div class="font-medium text-slate-900">Better luck next time</div>
              <div class="text-xs text-slate-500">Consolation / no prize</div>
            </div>
            <input
              type="number" min="0"
              v-model.number="settings.blanks_count"
              :disabled="settings.status !== 'draft'"
              class="w-24 px-3 py-2 rounded-lg border border-slate-300 text-sm text-right focus:outline-none focus:ring-2 focus:ring-sycamore-500 disabled:bg-white"
            />
            <button
              v-if="settings.status === 'draft'"
              @click="saveBlanks"
              class="px-3 py-2 rounded-lg bg-slate-900 text-white text-xs font-medium hover:bg-slate-800"
            >Save</button>
          </div>
        </div>
      </div>

      <!-- Dry run -->
      <div class="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <div class="px-5 py-4 border-b border-slate-200 flex items-center justify-between flex-wrap gap-2">
          <div>
            <h2 class="font-semibold text-slate-900">Dry-run simulation</h2>
            <p class="text-xs text-slate-500 mt-0.5">Preview a random allocation without writing to the database. Refresh as many times as you like.</p>
          </div>
          <button @click="runSimulation" :disabled="busy || slotMismatch"
            class="px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-medium hover:bg-sycamore-700 disabled:opacity-50">
            Run simulation
          </button>
        </div>
        <div v-if="simulation.length" class="p-5 space-y-4">
          <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
            <div v-for="s in simulationSummary" :key="s.name" class="px-3 py-2 rounded-lg bg-slate-50 border border-slate-200 text-sm flex justify-between">
              <span class="text-slate-700 truncate">{{ s.name }}</span>
              <span class="font-semibold text-slate-900">{{ s.count }}</span>
            </div>
          </div>
          <div class="max-h-80 overflow-y-auto border border-slate-200 rounded-lg">
            <table class="w-full text-sm">
              <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500 sticky top-0">
                <tr>
                  <th class="text-left px-3 py-2 font-medium">Staff</th>
                  <th class="text-left px-3 py-2 font-medium">Email</th>
                  <th class="text-left px-3 py-2 font-medium">Outcome</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100">
                <tr v-for="row in simulation" :key="row.staff_id">
                  <td class="px-3 py-2 text-slate-900">{{ row.full_name }}</td>
                  <td class="px-3 py-2 text-slate-500">{{ row.email }}</td>
                  <td class="px-3 py-2">
                    <span v-if="row.is_blank" class="text-slate-500">Better luck next time</span>
                    <span v-else class="font-medium text-sycamore-700">{{ row.prize_name }}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <div v-else class="px-5 py-10 text-center text-sm text-slate-500">
          Run a simulation to preview allocations.
        </div>
      </div>

      <!-- Live stats -->
      <div v-if="stats" class="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <div class="px-5 py-4 border-b border-slate-200 flex items-center justify-between">
          <h2 class="font-semibold text-slate-900">Live progress</h2>
          <button @click="() => { loadStats(); loadAllocations(); }" class="text-xs text-slate-600 hover:text-slate-900">Refresh</button>
        </div>
        <div class="p-5 space-y-4">
          <div class="flex gap-4 flex-wrap">
            <div class="px-4 py-3 rounded-lg bg-emerald-50 border border-emerald-200">
              <div class="text-xs text-emerald-700 uppercase tracking-wide">Revealed</div>
              <div class="text-2xl font-bold text-emerald-800">{{ stats.revealed }} / {{ stats.total }}</div>
            </div>
            <div class="px-4 py-3 rounded-lg bg-slate-50 border border-slate-200">
              <div class="text-xs text-slate-600 uppercase tracking-wide">Blanks drawn</div>
              <div class="text-2xl font-bold text-slate-800">{{ stats.blanks_revealed }} / {{ stats.blanks_total }}</div>
            </div>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
            <div v-for="row in stats.by_prize" :key="row.prize_id"
              class="px-3 py-2 rounded-lg bg-slate-50 border border-slate-200 flex justify-between text-sm">
              <span class="text-slate-700">{{ row.name }}</span>
              <span class="font-semibold text-slate-900">{{ row.revealed }} / {{ row.quantity }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Results / staff list -->
      <div v-if="allocations.length" class="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <div class="px-5 py-4 border-b border-slate-200 flex items-center justify-between flex-wrap gap-2">
          <div>
            <h2 class="font-semibold text-slate-900">Results</h2>
            <p class="text-xs text-slate-500 mt-0.5">Who has spun, who hasn't, and what they won.</p>
          </div>
          <div class="flex items-center gap-2 flex-wrap">
            <div class="inline-flex rounded-lg border border-slate-200 overflow-hidden text-xs">
              <button
                v-for="f in (['all','revealed','pending'] as const)"
                :key="f"
                @click="allocationsFilter = f"
                class="px-3 py-1.5 font-medium"
                :class="allocationsFilter === f ? 'bg-sycamore-600 text-white' : 'bg-white text-slate-700 hover:bg-slate-50'"
              >
                {{ f === 'all' ? 'All' : f === 'revealed' ? 'Revealed' : 'Pending' }}
              </button>
            </div>
            <button
              @click="downloadCsv"
              class="px-3 py-1.5 rounded-lg border border-slate-300 text-slate-700 text-xs font-medium hover:bg-slate-50"
            >Export CSV</button>
          </div>
        </div>
        <div class="max-h-96 overflow-y-auto">
          <table class="w-full text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500 sticky top-0">
              <tr>
                <th class="text-left px-5 py-2 font-medium">Staff</th>
                <th class="text-left px-3 py-2 font-medium">Email</th>
                <th class="text-left px-3 py-2 font-medium">Outcome</th>
                <th class="text-left px-3 py-2 font-medium">Revealed</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="row in filteredAllocations" :key="row.staff_id">
                <td class="px-5 py-2 text-slate-900">{{ row.full_name }}</td>
                <td class="px-3 py-2 text-slate-500">{{ row.email }}</td>
                <td class="px-3 py-2">
                  <span v-if="row.prize_name" class="inline-flex items-center gap-2">
                    <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: row.prize_color || '#64748b' }"></span>
                    <span class="font-medium" :style="{ color: row.prize_color || '#0f172a' }">{{ row.prize_name }}</span>
                  </span>
                  <span v-else-if="row.is_blank === true" class="text-slate-500">Better luck next time</span>
                  <span v-else class="text-amber-600">Not allocated</span>
                </td>
                <td class="px-3 py-2 text-slate-600">
                  <span v-if="row.revealed_at">{{ new Date(row.revealed_at).toLocaleString() }}</span>
                  <span v-else class="text-xs px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">Pending</span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </div>
</template>
