<script setup lang="ts">
definePageMeta({ layout: 'admin', title: 'Headcount Planning' })

const supabase = useSupabase()
const { user, ready, isAdmin } = useAuth()
const { success, error: toastError } = useToast()

interface HeadcountPlan {
  id: string
  department: string
  role_title: string
  quarter: string
  planned_hires: number
  actual_hires: number
  status: string
  justification: string
  created_at: string
}

const plans = ref<HeadcountPlan[]>([])
const loading = ref(true)
const quarterFilter = ref('')
const showForm = ref(false)
const editing = ref<HeadcountPlan | null>(null)
const form = ref({
  department: '', role_title: '', quarter: 'Q3 2026',
  planned_hires: 1, actual_hires: 0, status: 'planned', justification: ''
})

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('headcount_plans')
    .select('*')
    .order('created_at', { ascending: false })
  plans.value = (data ?? []) as HeadcountPlan[]
  loading.value = false
}

const quarters = computed(() => [...new Set(plans.value.map(p => p.quarter))].sort().reverse())

const filtered = computed(() => {
  if (!quarterFilter.value) return plans.value
  return plans.value.filter(p => p.quarter === quarterFilter.value)
})

const stats = computed(() => {
  const list = filtered.value
  return {
    totalPlanned: list.reduce((sum, p) => sum + p.planned_hires, 0),
    totalActual: list.reduce((sum, p) => sum + p.actual_hires, 0),
    filled: list.filter(p => p.status === 'filled').length,
    inProgress: list.filter(p => p.status === 'in_progress' || p.status === 'approved').length,
    planned: list.filter(p => p.status === 'planned').length
  }
})

function openAdd() {
  editing.value = null
  form.value = { department: '', role_title: '', quarter: 'Q3 2026', planned_hires: 1, actual_hires: 0, status: 'planned', justification: '' }
  showForm.value = true
}

function openEdit(p: HeadcountPlan) {
  editing.value = p
  form.value = {
    department: p.department, role_title: p.role_title, quarter: p.quarter,
    planned_hires: p.planned_hires, actual_hires: p.actual_hires,
    status: p.status, justification: p.justification
  }
  showForm.value = true
}

async function save() {
  const payload: any = {
    department: form.value.department.trim(),
    role_title: form.value.role_title.trim(),
    quarter: form.value.quarter.trim(),
    planned_hires: Number(form.value.planned_hires),
    actual_hires: Number(form.value.actual_hires),
    status: form.value.status,
    justification: form.value.justification.trim()
  }
  if (editing.value) {
    const { error } = await supabase.from('headcount_plans').update(payload).eq('id', editing.value.id)
    if (error) toastError('Failed to update'); else success('Plan updated')
  } else {
    payload.created_by = user.value?.id
    const { error } = await supabase.from('headcount_plans').insert(payload)
    if (error) toastError('Failed to create'); else success('Plan created')
  }
  showForm.value = false
  await load()
}

function statusBadge(status: string) {
  switch (status) {
    case 'filled': return 'badge-green'
    case 'in_progress': return 'badge-amber'
    case 'approved': return 'badge-blue'
    case 'cancelled': return 'badge-rose'
    default: return 'badge-slate'
  }
}

function fillRate(p: HeadcountPlan) {
  if (p.planned_hires === 0) return 100
  return Math.round((p.actual_hires / p.planned_hires) * 100)
}

watch(ready, (r) => { if (r && isAdmin.value) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-6xl mx-auto px-4 py-8">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="section-title">Headcount Planning</h1>
        <p class="section-subtitle">Track planned vs actual hiring across departments and quarters</p>
      </div>
      <button @click="openAdd" class="btn-primary">Add Plan</button>
    </div>

    <div class="grid grid-cols-2 sm:grid-cols-5 gap-4 mb-6">
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-slate-900">{{ stats.totalPlanned }}</div>
        <div class="text-xs text-slate-500 mt-1">Planned Hires</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-leaf-600">{{ stats.totalActual }}</div>
        <div class="text-xs text-slate-500 mt-1">Actual Hires</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-leaf-600">{{ stats.filled }}</div>
        <div class="text-xs text-slate-500 mt-1">Filled</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-amber-600">{{ stats.inProgress }}</div>
        <div class="text-xs text-slate-500 mt-1">In Progress</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-slate-500">{{ stats.planned }}</div>
        <div class="text-xs text-slate-500 mt-1">Planned</div>
      </div>
    </div>

    <div v-if="quarters.length" class="flex flex-wrap gap-2 mb-4">
      <button
        @click="quarterFilter = ''"
        class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
        :class="!quarterFilter ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'"
      >All Quarters</button>
      <button
        v-for="q in quarters"
        :key="q"
        @click="quarterFilter = q"
        class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
        :class="quarterFilter === q ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'"
      >{{ q }}</button>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-400">No headcount plans yet.</div>
    <div v-else class="space-y-3">
      <div v-for="p in filtered" :key="p.id" class="card p-4 card-hover cursor-pointer" @click="openEdit(p)">
        <div class="flex items-start justify-between gap-3">
          <div class="flex-1">
            <div class="flex items-center gap-2 mb-1">
              <span class="font-semibold text-slate-900">{{ p.role_title }}</span>
              <span class="badge border" :class="statusBadge(p.status)">{{ p.status.replace('_', ' ') }}</span>
            </div>
            <div class="text-sm text-slate-600">{{ p.department }} - {{ p.quarter }}</div>
            <p v-if="p.justification" class="text-xs text-slate-500 mt-1 line-clamp-1">{{ p.justification }}</p>
          </div>
          <div class="text-right">
            <div class="text-lg font-bold" :class="fillRate(p) >= 100 ? 'text-leaf-600' : fillRate(p) >= 50 ? 'text-amber-600' : 'text-slate-500'">
              {{ p.actual_hires }}/{{ p.planned_hires }}
            </div>
            <div class="text-xs text-slate-500">{{ fillRate(p) }}% filled</div>
          </div>
        </div>
      </div>
    </div>

    <!-- Form Modal -->
    <div v-if="showForm" class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" @click.self="showForm = false">
      <div class="bg-white rounded-xl shadow-xl w-full max-w-lg p-6">
        <h2 class="text-lg font-bold text-slate-900 mb-4">{{ editing ? 'Edit' : 'New' }} Headcount Plan</h2>
        <div class="space-y-3">
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Department</label>
              <input v-model="form.department" class="input" placeholder="e.g. Engineering">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Role Title</label>
              <input v-model="form.role_title" class="input" placeholder="e.g. Senior Developer">
            </div>
          </div>
          <div class="grid grid-cols-3 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Quarter</label>
              <input v-model="form.quarter" class="input" placeholder="Q3 2026">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Planned Hires</label>
              <input v-model.number="form.planned_hires" type="number" min="1" class="input">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Actual Hires</label>
              <input v-model.number="form.actual_hires" type="number" min="0" class="input">
            </div>
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Status</label>
            <select v-model="form.status" class="input">
              <option value="planned">Planned</option>
              <option value="approved">Approved</option>
              <option value="in_progress">In Progress</option>
              <option value="filled">Filled</option>
              <option value="cancelled">Cancelled</option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Justification</label>
            <textarea v-model="form.justification" class="input min-h-[80px]" placeholder="Why is this hire needed?" />
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <button @click="showForm = false" class="btn-secondary">Cancel</button>
          <button @click="save" :disabled="!form.department.trim() || !form.role_title.trim()" class="btn-primary">
            {{ editing ? 'Update' : 'Create' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
