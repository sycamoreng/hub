<script setup lang="ts">
definePageMeta({ title: 'Burnout Risk Dashboard' })

const supabase = useSupabase()
const { user, ready, isAdmin } = useAuth()
const { success, error: toastError } = useToast()

interface BurnoutFlag {
  id: string
  staff_id: string
  risk_level: 'low' | 'medium' | 'high' | 'critical'
  indicators: {
    overtime_hours?: number
    days_since_leave?: number
    engagement_score?: number
    missed_deadlines?: number
    late_clockins?: number
  }
  flagged_at: string
  resolved_at: string | null
  notes: string
  staff_name?: string
  department?: string
}

const flags = ref<BurnoutFlag[]>([])
const loading = ref(true)
const filter = ref<'all' | 'active' | 'resolved'>('active')
const riskFilter = ref<string>('all')

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('burnout_risk_flags')
    .select('*, staff_members!burnout_risk_flags_staff_id_fkey(full_name, department_id, departments!staff_members_department_id_fkey(name))')
    .order('flagged_at', { ascending: false })

  if (data) {
    flags.value = data.map((f: any) => ({
      ...f,
      staff_name: f.staff_members?.full_name ?? 'Unknown',
      department: f.staff_members?.departments?.name ?? ''
    }))
  }
  loading.value = false
}

const filtered = computed(() => {
  let list = flags.value
  if (filter.value === 'active') list = list.filter(f => !f.resolved_at)
  else if (filter.value === 'resolved') list = list.filter(f => f.resolved_at)
  if (riskFilter.value !== 'all') list = list.filter(f => f.risk_level === riskFilter.value)
  return list
})

const stats = computed(() => {
  const active = flags.value.filter(f => !f.resolved_at)
  return {
    total: active.length,
    critical: active.filter(f => f.risk_level === 'critical').length,
    high: active.filter(f => f.risk_level === 'high').length,
    medium: active.filter(f => f.risk_level === 'medium').length,
    low: active.filter(f => f.risk_level === 'low').length
  }
})

async function resolve(id: string) {
  const { error } = await supabase
    .from('burnout_risk_flags')
    .update({ resolved_at: new Date().toISOString() })
    .eq('id', id)
  if (error) toastError('Failed to resolve flag')
  else { success('Flag resolved'); await load() }
}

function riskColor(level: string) {
  switch (level) {
    case 'critical': return 'bg-red-100 text-red-800 border-red-200'
    case 'high': return 'bg-orange-100 text-orange-800 border-orange-200'
    case 'medium': return 'bg-amber-100 text-amber-700 border-amber-200'
    default: return 'bg-slate-100 text-slate-700 border-slate-200'
  }
}

watch(ready, (r) => { if (r && isAdmin.value) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-6xl mx-auto px-4 py-8">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="section-title">Burnout Risk Dashboard</h1>
        <p class="section-subtitle">Monitor team wellbeing and identify burnout risks early</p>
      </div>
    </div>

    <div v-if="!isAdmin" class="card p-8 text-center text-slate-500">
      This dashboard is only accessible to administrators.
    </div>

    <template v-else>
      <div class="grid grid-cols-2 sm:grid-cols-5 gap-3 sm:gap-4 mb-6">
        <div class="card p-3 sm:p-4 text-center">
          <div class="text-lg sm:text-2xl font-bold text-slate-900">{{ stats.total }}</div>
          <div class="text-[10px] sm:text-xs text-slate-500 mt-0.5 sm:mt-1">Active Flags</div>
        </div>
        <div class="card p-3 sm:p-4 text-center border-red-200">
          <div class="text-lg sm:text-2xl font-bold text-red-600">{{ stats.critical }}</div>
          <div class="text-[10px] sm:text-xs text-slate-500 mt-0.5 sm:mt-1">Critical</div>
        </div>
        <div class="card p-3 sm:p-4 text-center border-orange-200">
          <div class="text-lg sm:text-2xl font-bold text-orange-600">{{ stats.high }}</div>
          <div class="text-[10px] sm:text-xs text-slate-500 mt-0.5 sm:mt-1">High</div>
        </div>
        <div class="card p-3 sm:p-4 text-center border-amber-200">
          <div class="text-lg sm:text-2xl font-bold text-amber-600">{{ stats.medium }}</div>
          <div class="text-[10px] sm:text-xs text-slate-500 mt-0.5 sm:mt-1">Medium</div>
        </div>
        <div class="card p-3 sm:p-4 text-center">
          <div class="text-lg sm:text-2xl font-bold text-slate-600">{{ stats.low }}</div>
          <div class="text-[10px] sm:text-xs text-slate-500 mt-0.5 sm:mt-1">Low</div>
        </div>
      </div>

      <div class="flex flex-wrap gap-2 mb-4">
        <button
          v-for="f in ['active', 'resolved', 'all']"
          :key="f"
          @click="filter = f as any"
          class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
          :class="filter === f ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'"
        >{{ f === 'all' ? 'All' : f.charAt(0).toUpperCase() + f.slice(1) }}</button>
        <select v-model="riskFilter" class="input w-auto">
          <option value="all">All Risk Levels</option>
          <option value="critical">Critical</option>
          <option value="high">High</option>
          <option value="medium">Medium</option>
          <option value="low">Low</option>
        </select>
      </div>

      <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
      <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-400">
        No burnout flags found.
      </div>
      <div v-else class="space-y-3">
        <div v-for="flag in filtered" :key="flag.id" class="card p-4">
          <div class="flex items-start justify-between gap-4">
            <div class="flex-1">
              <div class="flex items-center gap-2 mb-1">
                <span class="font-semibold text-slate-900">{{ flag.staff_name }}</span>
                <span class="badge border" :class="riskColor(flag.risk_level)">{{ flag.risk_level }}</span>
                <span v-if="flag.resolved_at" class="badge badge-green">Resolved</span>
              </div>
              <div class="text-xs text-slate-500 mb-2">{{ flag.department }} - Flagged {{ new Date(flag.flagged_at).toLocaleDateString() }}</div>
              <div class="flex flex-wrap gap-3 text-xs text-slate-600">
                <span v-if="flag.indicators.overtime_hours">Overtime: {{ flag.indicators.overtime_hours }}h</span>
                <span v-if="flag.indicators.days_since_leave">Days since leave: {{ flag.indicators.days_since_leave }}</span>
                <span v-if="flag.indicators.engagement_score != null">Engagement: {{ flag.indicators.engagement_score }}/10</span>
                <span v-if="flag.indicators.missed_deadlines">Missed deadlines: {{ flag.indicators.missed_deadlines }}</span>
                <span v-if="flag.indicators.late_clockins">Late clock-ins: {{ flag.indicators.late_clockins }}</span>
              </div>
              <p v-if="flag.notes" class="text-sm text-slate-600 mt-2">{{ flag.notes }}</p>
            </div>
            <button
              v-if="!flag.resolved_at"
              @click="resolve(flag.id)"
              class="btn-secondary text-xs"
            >Resolve</button>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
