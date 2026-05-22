<script setup lang="ts">
definePageMeta({ layout: 'admin', title: 'Burnout Risk Management' })

const supabase = useSupabase()
const { user, ready, isAdmin } = useAuth()
const { success, error: toastError } = useToast()

interface StaffMember {
  id: string
  name: string
  department: string
}

interface BurnoutFlag {
  id: string
  staff_id: string
  risk_level: string
  indicators: Record<string, number>
  flagged_at: string
  resolved_at: string | null
  notes: string
  staff_name?: string
  department?: string
}

const flags = ref<BurnoutFlag[]>([])
const staffList = ref<StaffMember[]>([])
const loading = ref(true)
const showForm = ref(false)
const form = ref({
  staff_id: '',
  risk_level: 'medium',
  notes: '',
  overtime_hours: '',
  days_since_leave: '',
  engagement_score: '',
  missed_deadlines: '',
  late_clockins: ''
})

async function load() {
  loading.value = true

  const staffRes = await supabase
    .from('staff_members')
    .select('id, full_name, department_id, departments!staff_members_department_id_fkey(name)')
    .eq('is_active', true)
    .order('full_name')
  staffList.value = (staffRes.data ?? []).map((s: any) => ({ id: s.id, name: s.full_name, department: s.departments?.name ?? '' }))

  const flagsRes = await supabase
    .from('burnout_risk_flags')
    .select('*, staff_members!burnout_risk_flags_staff_id_fkey(full_name, department_id, departments!staff_members_department_id_fkey(name))')
    .order('flagged_at', { ascending: false })

  if (flagsRes.data) {
    flags.value = flagsRes.data.map((f: any) => ({
      ...f,
      staff_name: f.staff_members?.full_name ?? 'Unknown',
      department: f.staff_members?.departments?.name ?? ''
    }))
  }
  loading.value = false
}

async function createFlag() {
  if (!form.value.staff_id || !user.value) return
  const indicators: Record<string, number> = {}
  if (form.value.overtime_hours) indicators.overtime_hours = Number(form.value.overtime_hours)
  if (form.value.days_since_leave) indicators.days_since_leave = Number(form.value.days_since_leave)
  if (form.value.engagement_score) indicators.engagement_score = Number(form.value.engagement_score)
  if (form.value.missed_deadlines) indicators.missed_deadlines = Number(form.value.missed_deadlines)
  if (form.value.late_clockins) indicators.late_clockins = Number(form.value.late_clockins)

  const { error } = await supabase.from('burnout_risk_flags').insert({
    staff_id: form.value.staff_id,
    risk_level: form.value.risk_level,
    notes: form.value.notes.trim(),
    indicators,
    created_by: user.value.id
  })
  if (error) toastError('Failed to create flag')
  else {
    success('Burnout flag created')
    showForm.value = false
    form.value = { staff_id: '', risk_level: 'medium', notes: '', overtime_hours: '', days_since_leave: '', engagement_score: '', missed_deadlines: '', late_clockins: '' }
    await load()
  }
}

async function resolve(id: string) {
  const { error } = await supabase.from('burnout_risk_flags').update({ resolved_at: new Date().toISOString() }).eq('id', id)
  if (error) toastError('Failed to resolve')
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
  <div class="max-w-5xl mx-auto px-4 py-8">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="section-title">Burnout Risk Management</h1>
        <p class="section-subtitle">Flag and track team members showing burnout indicators</p>
      </div>
      <button @click="showForm = true" class="btn-primary">Flag Risk</button>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="flags.length === 0" class="card p-8 text-center text-slate-400">No burnout flags yet.</div>
    <div v-else class="space-y-3">
      <div v-for="flag in flags" :key="flag.id" class="card p-4">
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
          <button v-if="!flag.resolved_at" @click="resolve(flag.id)" class="btn-secondary text-xs">Resolve</button>
        </div>
      </div>
    </div>

    <!-- Create Flag Modal -->
    <div v-if="showForm" class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" @click.self="showForm = false">
      <div class="bg-white rounded-xl shadow-xl w-full max-w-lg p-6">
        <h2 class="text-lg font-bold text-slate-900 mb-4">Flag Burnout Risk</h2>
        <div class="space-y-3">
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Staff Member</label>
            <select v-model="form.staff_id" class="input">
              <option value="">Select staff...</option>
              <option v-for="s in staffList" :key="s.id" :value="s.id">{{ s.name }} ({{ s.department }})</option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Risk Level</label>
            <select v-model="form.risk_level" class="input">
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
              <option value="critical">Critical</option>
            </select>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Overtime Hours (week)</label>
              <input v-model="form.overtime_hours" type="number" class="input" placeholder="0">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Days Since Leave</label>
              <input v-model="form.days_since_leave" type="number" class="input" placeholder="0">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Engagement (1-10)</label>
              <input v-model="form.engagement_score" type="number" min="1" max="10" class="input" placeholder="5">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Late Clock-ins</label>
              <input v-model="form.late_clockins" type="number" class="input" placeholder="0">
            </div>
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Notes</label>
            <textarea v-model="form.notes" class="input min-h-[80px]" placeholder="Additional context..." />
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <button @click="showForm = false" class="btn-secondary">Cancel</button>
          <button @click="createFlag" :disabled="!form.staff_id" class="btn-primary">Create Flag</button>
        </div>
      </div>
    </div>
  </div>
</template>
