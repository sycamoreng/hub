<script setup lang="ts">
import {
  usePerformance,
  APPRAISAL_STATUSES,
  APPRAISAL_STATUS_LABELS,
  type AppraisalStatus,
  type PerformanceCycle
} from '~/composables/usePerformance'

const props = defineProps<{
  cycles: PerformanceCycle[]
  staffMembers: Array<{ id: string; full_name: string; role?: string; department_id?: string | null }>
  selectedCycleId: string
}>()

const toast = useToast()
const {
  loadAppraisals, saveAppraisal, deleteAppraisal,
  recomputeAppraisal, reassignAppraiser
} = usePerformance()

const appraisals = ref<any[]>([])
const loading = ref(false)
const statusFilter = ref<AppraisalStatus | ''>('')
const ratingFilter = ref<string>('')
const searchTerm = ref('')

const reassigning = ref<Record<string, boolean>>({})
const recomputing = ref<Record<string, boolean>>({})
const editing = ref<any | null>(null)

async function reload() {
  if (!props.selectedCycleId) { appraisals.value = []; return }
  loading.value = true
  try {
    const opts: any = { cycleId: props.selectedCycleId }
    if (statusFilter.value) opts.status = statusFilter.value
    appraisals.value = await loadAppraisals(opts)
  } finally {
    loading.value = false
  }
}

watch(() => props.selectedCycleId, reload, { immediate: true })
watch(statusFilter, reload)

const filtered = computed(() => {
  const q = searchTerm.value.trim().toLowerCase()
  return appraisals.value.filter(a => {
    if (ratingFilter.value && a.rating_label !== ratingFilter.value) return false
    if (!q) return true
    const haystack = `${a.subject?.full_name ?? ''} ${a.appraiser?.full_name ?? ''} ${a.rating_label ?? ''} ${a.rating_tag ?? ''}`.toLowerCase()
    return haystack.includes(q)
  })
})

const ratingOptions = computed(() => Array.from(new Set(appraisals.value.map(a => a.rating_label).filter(Boolean))))

async function ensureAppraisalsForCycle() {
  if (!props.selectedCycleId) return
  loading.value = true
  try {
    const existingIds = new Set(appraisals.value.map(a => a.subject_staff_id))
    const missing = props.staffMembers.filter(s => !existingIds.has(s.id))
    if (missing.length === 0) {
      toast.info('Every active staff member already has an appraisal for this cycle.')
      return
    }
    for (const s of missing) {
      await saveAppraisal({
        cycle_id: props.selectedCycleId,
        subject_staff_id: s.id,
        status: 'not_started'
      })
    }
    toast.success(`Generated ${missing.length} appraisal(s).`)
    await reload()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not generate appraisals')
  } finally {
    loading.value = false
  }
}

async function recompute(a: any) {
  recomputing.value[a.id] = true
  try {
    await recomputeAppraisal(a.id)
    await reload()
    toast.success('Score recomputed')
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not recompute')
  } finally {
    recomputing.value[a.id] = false
  }
}

async function recomputeAll() {
  loading.value = true
  try {
    for (const a of appraisals.value) {
      await recomputeAppraisal(a.id)
    }
    toast.success('All scores recomputed')
    await reload()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not recompute')
  } finally {
    loading.value = false
  }
}

async function onReassign(a: any, newStaffId: string) {
  if (newStaffId === (a.appraiser_staff_id ?? '')) return
  reassigning.value[a.id] = true
  try {
    await reassignAppraiser(a.id, newStaffId || null)
    toast.success('Appraiser reassigned')
    await reload()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not reassign')
  } finally {
    reassigning.value[a.id] = false
  }
}

function openEdit(a: any) {
  editing.value = {
    id: a.id,
    status: a.status,
    rating_tag: a.rating_tag ?? '',
    nine_box_position: a.nine_box_position ?? '',
    notes: a.notes ?? '',
    objective_weight: a.objective_weight,
    behavioural_weight: a.behavioural_weight
  }
}

async function saveEdit() {
  if (!editing.value) return
  try {
    const payload: any = {
      id: editing.value.id,
      status: editing.value.status,
      rating_tag: editing.value.rating_tag,
      nine_box_position: editing.value.nine_box_position,
      notes: editing.value.notes,
      objective_weight: Number(editing.value.objective_weight) || 0,
      behavioural_weight: Number(editing.value.behavioural_weight) || 0
    }
    if (payload.status === 'submitted') payload.submitted_at = new Date().toISOString()
    if (payload.status === 'finalized') payload.finalized_at = new Date().toISOString()
    await saveAppraisal(payload)
    await recomputeAppraisal(editing.value.id)
    toast.success('Appraisal saved')
    editing.value = null
    await reload()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not save')
  }
}

async function remove(a: any) {
  if (!confirm(`Delete the appraisal for ${a.subject?.full_name ?? 'this staff member'}?`)) return
  try {
    await deleteAppraisal(a.id)
    await reload()
    toast.success('Appraisal removed')
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not delete')
  }
}

function csvEscape(value: any): string {
  const s = value == null ? '' : String(value)
  if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`
  return s
}

function exportCsv() {
  const rows = [
    ['Staff', 'Email', 'Role', 'Appraiser', 'Status', 'Objective score', 'Behavioural score', 'Final score', 'Rating', 'Tag', '9-Box', 'Submitted', 'Finalized'],
    ...filtered.value.map(a => [
      a.subject?.full_name ?? '',
      a.subject?.email ?? '',
      a.subject?.role ?? '',
      a.appraiser?.full_name ?? '',
      APPRAISAL_STATUS_LABELS[a.status as AppraisalStatus] ?? a.status,
      a.objective_score,
      a.behavioural_score,
      a.final_score,
      a.rating_label,
      a.rating_tag,
      a.nine_box_position,
      a.submitted_at ?? '',
      a.finalized_at ?? ''
    ])
  ]
  const csv = rows.map(r => r.map(csvEscape).join(',')).join('\n')
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `appraisals-${props.selectedCycleId.slice(0, 8)}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

function statusBadgeClass(s: AppraisalStatus | string): string {
  switch (s) {
    case 'finalized': return 'bg-emerald-100 text-emerald-800 border-emerald-200'
    case 'submitted': return 'bg-sky-100 text-sky-800 border-sky-200'
    case 'in_progress': return 'bg-amber-100 text-amber-800 border-amber-200'
    case 'reopened': return 'bg-rose-100 text-rose-800 border-rose-200'
    default: return 'bg-slate-100 text-slate-700 border-slate-200'
  }
}

function ratingClass(label: string): string {
  if (!label) return 'text-slate-500'
  if (label === 'Outstanding' || label === 'Exceeds expectation') return 'text-emerald-700 font-semibold'
  if (label === 'Meets expectation') return 'text-sycamore-700 font-semibold'
  if (label === 'Below expectation') return 'text-amber-700 font-semibold'
  return 'text-rose-700 font-semibold'
}
</script>

<template>
  <section class="space-y-4">
    <header class="card p-5 flex flex-wrap items-end gap-3 justify-between">
      <div>
        <h2 class="text-lg font-bold text-slate-900">Appraisals</h2>
        <p class="text-sm text-slate-500">Track scores, rating tags, 9-box positions and reassign appraisers across the cycle.</p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button type="button" class="btn-secondary" :disabled="!selectedCycleId || loading" @click="ensureAppraisalsForCycle">Generate for active staff</button>
        <button type="button" class="btn-secondary" :disabled="!selectedCycleId || loading || appraisals.length === 0" @click="recomputeAll">Recompute all</button>
        <button type="button" class="btn-secondary" :disabled="filtered.length === 0" @click="exportCsv">Export CSV</button>
      </div>
    </header>

    <div class="card p-4 grid gap-3 sm:grid-cols-4">
      <label class="block text-xs font-medium text-slate-600">
        <span class="block mb-1 uppercase tracking-wide">Search</span>
        <input v-model="searchTerm" type="search" placeholder="Staff, appraiser, tag..." class="input" />
      </label>
      <label class="block text-xs font-medium text-slate-600">
        <span class="block mb-1 uppercase tracking-wide">Status</span>
        <select v-model="statusFilter" class="input">
          <option value="">All</option>
          <option v-for="s in APPRAISAL_STATUSES" :key="s" :value="s">{{ APPRAISAL_STATUS_LABELS[s] }}</option>
        </select>
      </label>
      <label class="block text-xs font-medium text-slate-600">
        <span class="block mb-1 uppercase tracking-wide">Rating</span>
        <select v-model="ratingFilter" class="input">
          <option value="">All</option>
          <option v-for="r in ratingOptions" :key="r" :value="r">{{ r }}</option>
        </select>
      </label>
      <div class="text-xs text-slate-500 self-end">
        <div>Showing <strong class="text-slate-700">{{ filtered.length }}</strong> of {{ appraisals.length }}</div>
      </div>
    </div>

    <div v-if="loading" class="card p-8 text-center text-sm text-slate-500">Loading appraisals...</div>
    <div v-else-if="!selectedCycleId" class="card p-8 text-center text-sm text-slate-500">Pick a cycle to view appraisals.</div>
    <div v-else-if="appraisals.length === 0" class="card p-8 text-center">
      <p class="text-sm text-slate-600 mb-3">No appraisals yet for this cycle.</p>
      <button class="btn-primary" @click="ensureAppraisalsForCycle">Generate for active staff</button>
    </div>
    <div v-else class="card overflow-hidden">
      <div class="overflow-x-auto">
        <table class="min-w-full text-sm">
          <thead class="bg-slate-50 text-slate-600 text-xs uppercase tracking-wide">
            <tr>
              <th class="text-left py-3 px-4">Staff</th>
              <th class="text-left py-3 px-4">Status</th>
              <th class="text-left py-3 px-4">9-Box</th>
              <th class="text-left py-3 px-4">Tag</th>
              <th class="text-right py-3 px-4">Final</th>
              <th class="text-left py-3 px-4">Rating</th>
              <th class="text-left py-3 px-4">Appraiser</th>
              <th class="text-right py-3 px-4">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="a in filtered" :key="a.id" class="hover:bg-slate-50/50">
              <td class="py-3 px-4">
                <div class="font-semibold text-slate-900">{{ a.subject?.full_name ?? '—' }}</div>
                <div class="text-xs text-slate-500">{{ a.subject?.role ?? '' }}</div>
              </td>
              <td class="py-3 px-4">
                <span :class="['inline-block px-2 py-0.5 rounded-full text-xs font-medium border', statusBadgeClass(a.status)]">
                  {{ APPRAISAL_STATUS_LABELS[a.status as AppraisalStatus] ?? a.status }}
                </span>
              </td>
              <td class="py-3 px-4 text-xs text-slate-600">{{ a.nine_box_position || '—' }}</td>
              <td class="py-3 px-4 text-xs text-slate-600">{{ a.rating_tag || '—' }}</td>
              <td class="py-3 px-4 text-right font-bold text-slate-900">{{ Number(a.final_score).toFixed(2) }}</td>
              <td class="py-3 px-4">
                <span :class="ratingClass(a.rating_label)">{{ a.rating_label || '—' }}</span>
                <div class="text-[11px] text-slate-400">Obj {{ Number(a.objective_score).toFixed(1) }} · Beh {{ Number(a.behavioural_score).toFixed(1) }}</div>
              </td>
              <td class="py-3 px-4">
                <select
                  class="form-input text-xs !py-1 !px-2 max-w-[200px]"
                  :value="a.appraiser_staff_id ?? ''"
                  :disabled="!!reassigning[a.id]"
                  @change="onReassign(a, ($event.target as HTMLSelectElement).value)"
                >
                  <option value="">Unassigned</option>
                  <option v-for="s in staffMembers" :key="s.id" :value="s.id">{{ s.full_name }}</option>
                </select>
              </td>
              <td class="py-3 px-4 text-right whitespace-nowrap">
                <button class="text-xs font-medium text-sycamore-700 hover:underline mr-3" :disabled="!!recomputing[a.id]" @click="recompute(a)">
                  {{ recomputing[a.id] ? '...' : 'Recompute' }}
                </button>
                <button class="text-xs font-medium text-slate-700 hover:underline mr-3" @click="openEdit(a)">Edit</button>
                <button class="text-xs font-medium text-rose-600 hover:underline" @click="remove(a)">Delete</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div
      v-if="editing"
      class="fixed inset-0 z-50 bg-slate-900/50 backdrop-blur-sm flex items-start sm:items-center justify-center p-4"
      @click.self="editing = null"
    >
      <div class="card w-full max-w-xl max-h-[90vh] overflow-y-auto">
        <header class="p-5 border-b border-slate-100 flex items-center justify-between">
          <h3 class="text-base font-semibold text-slate-900">Edit appraisal</h3>
          <button class="text-slate-400 hover:text-slate-700 text-xl leading-none" @click="editing = null">&times;</button>
        </header>
        <div class="p-5 space-y-4">
          <label class="block text-xs font-medium text-slate-600">
            <span class="block mb-1 uppercase tracking-wide">Status</span>
            <select v-model="editing.status" class="input">
              <option v-for="s in APPRAISAL_STATUSES" :key="s" :value="s">{{ APPRAISAL_STATUS_LABELS[s] }}</option>
            </select>
          </label>
          <div class="grid grid-cols-2 gap-3">
            <label class="block text-xs font-medium text-slate-600">
              <span class="block mb-1 uppercase tracking-wide">Objective weight (%)</span>
              <input v-model.number="editing.objective_weight" type="number" min="0" max="100" class="input" />
            </label>
            <label class="block text-xs font-medium text-slate-600">
              <span class="block mb-1 uppercase tracking-wide">Behavioural weight (%)</span>
              <input v-model.number="editing.behavioural_weight" type="number" min="0" max="100" class="input" />
            </label>
          </div>
          <label class="block text-xs font-medium text-slate-600">
            <span class="block mb-1 uppercase tracking-wide">Rating tag</span>
            <input v-model="editing.rating_tag" placeholder="e.g. Consistent Star" class="input" />
          </label>
          <label class="block text-xs font-medium text-slate-600">
            <span class="block mb-1 uppercase tracking-wide">9-Box position</span>
            <select v-model="editing.nine_box_position" class="input">
              <option value="">Not set</option>
              <option value="Low Performer / Low Potential">Low Performer / Low Potential</option>
              <option value="Solid Performer / Low Potential">Solid Performer / Low Potential</option>
              <option value="High Performer / Low Potential">High Performer / Low Potential</option>
              <option value="Low Performer / Medium Potential">Low Performer / Medium Potential</option>
              <option value="Core Player">Core Player</option>
              <option value="High Performer / Medium Potential">High Performer / Medium Potential</option>
              <option value="Enigma">Enigma</option>
              <option value="Growth Employee">Growth Employee</option>
              <option value="Future Leader">Future Leader</option>
            </select>
          </label>
          <label class="block text-xs font-medium text-slate-600">
            <span class="block mb-1 uppercase tracking-wide">Notes</span>
            <textarea v-model="editing.notes" rows="3" class="input"></textarea>
          </label>
        </div>
        <footer class="p-5 border-t border-slate-100 flex justify-end gap-2">
          <button class="btn-secondary" @click="editing = null">Cancel</button>
          <button class="btn-primary" @click="saveEdit">Save & recompute</button>
        </footer>
      </div>
    </div>
  </section>
</template>
