<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { useExit, type ExitCase, type ExitChecklistItem, type ExitUnit } from '~/composables/useExit'

const supabase = useSupabase()
const { user } = useAuth()
const toast = useToast()
const { loadUnits, loadItems, createCase, updateCase, notifyHods } = useExit()

const staffId = ref<string | null>(null)
const staffName = ref<string>('')
const units = ref<ExitUnit[]>([])
const cases = ref<ExitCase[]>([])
const activeCase = ref<ExitCase | null>(null)
const items = ref<ExitChecklistItem[]>([])
const loading = ref(true)

const today = new Date().toISOString().slice(0, 10)
const form = ref({
  reason: '',
  effective_date: today,
  last_working_day: '',
  notes: ''
})
const saving = ref(false)
const showForm = ref(false)

async function loadMine() {
  loading.value = true
  try {
    if (!user.value) return
    const { data: staff } = await supabase
      .from('staff_members')
      .select('id, full_name')
      .eq('auth_user_id', user.value.id)
      .maybeSingle()
    if (!staff) { loading.value = false; return }
    staffId.value = (staff as any).id
    staffName.value = (staff as any).full_name
    const { data: cs } = await supabase
      .from('exit_cases')
      .select('*')
      .eq('staff_id', staffId.value)
      .order('created_at', { ascending: false })
    cases.value = (cs as ExitCase[]) ?? []
    units.value = await loadUnits()
    const open = cases.value.find(c => c.status === 'initiated' || c.status === 'in_progress')
    if (open) {
      activeCase.value = open
      items.value = await loadItems(open.id)
    }
  } finally {
    loading.value = false
  }
}
loadMine()

async function submitResignation() {
  if (!staffId.value || !user.value) return
  if (!form.value.reason.trim()) {
    toast.error('Please share a brief reason.')
    return
  }
  saving.value = true
  try {
    const created = await createCase({
      staff_id: staffId.value,
      exit_type: 'resignation',
      reason: form.value.reason.trim(),
      effective_date: form.value.effective_date || null,
      last_working_day: form.value.last_working_day || null,
      notes: form.value.notes.trim(),
      status: 'initiated',
      initiated_by_user_id: user.value.id,
      initiated_by_kind: 'self'
    })
    if (created) {
      await notifyHods(created, staffName.value)
      toast.success('Resignation submitted. HoDs have been notified.')
      showForm.value = false
      form.value = { reason: '', effective_date: today, last_working_day: '', notes: '' }
      await loadMine()
    }
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to submit resignation')
  } finally {
    saving.value = false
  }
}

async function cancelResignation() {
  if (!activeCase.value) return
  if (!confirm('Withdraw your resignation?')) return
  try {
    await updateCase(activeCase.value.id, { status: 'cancelled' })
    toast.success('Resignation withdrawn.')
    activeCase.value = null
    items.value = []
    await loadMine()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  }
}

const itemsByUnit = computed(() => {
  const map = new Map<string, ExitChecklistItem[]>()
  for (const it of items.value) {
    if (!map.has(it.unit_code)) map.set(it.unit_code, [])
    map.get(it.unit_code)!.push(it)
  }
  return map
})

function unitName(code: string) {
  return units.value.find(u => u.code === code)?.name ?? code
}

function progress() {
  if (!items.value.length) return 0
  const done = items.value.filter(i => i.status === 'done' || i.status === 'not_applicable').length
  return Math.round((done / items.value.length) * 100)
}

function statusChip(s: string) {
  if (s === 'completed') return 'bg-emerald-50 text-emerald-700 border-emerald-200'
  if (s === 'cancelled') return 'bg-slate-100 text-slate-600 border-slate-200'
  if (s === 'in_progress') return 'bg-sky-50 text-sky-700 border-sky-200'
  return 'bg-amber-50 text-amber-700 border-amber-200'
}
</script>

<template>
  <div class="max-w-5xl">
    <header class="mb-6 flex items-center justify-between flex-wrap gap-3">
      <div>
        <h1 class="section-title">Exit</h1>
        <p class="section-subtitle">Submit a resignation and track your offboarding checklist.</p>
      </div>
      <button
        v-if="!activeCase && !showForm"
        type="button"
        @click="showForm = true"
        class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800"
      >
        Submit resignation
      </button>
    </header>

    <div v-if="loading" class="text-slate-500 text-sm">Loading...</div>

    <section v-else-if="showForm && !activeCase" class="bg-white border border-slate-200 rounded-2xl p-6 mb-6">
      <h2 class="text-lg font-semibold text-slate-900">Resignation details</h2>
      <p class="text-sm text-slate-500 mt-1 mb-5">
        Once submitted, Human Capital, your line manager and all relevant unit heads will be notified. A checklist will be created and tracked to completion.
      </p>
      <div class="grid md:grid-cols-2 gap-4">
        <div class="md:col-span-2">
          <label class="block text-xs font-semibold text-slate-600 mb-1">Reason</label>
          <textarea v-model="form.reason" rows="3" class="input" placeholder="Share a brief reason for leaving." />
        </div>
        <div>
          <label class="block text-xs font-semibold text-slate-600 mb-1">Notice / effective date</label>
          <input v-model="form.effective_date" type="date" class="input" />
        </div>
        <div>
          <label class="block text-xs font-semibold text-slate-600 mb-1">Proposed last working day</label>
          <input v-model="form.last_working_day" type="date" class="input" />
        </div>
        <div class="md:col-span-2">
          <label class="block text-xs font-semibold text-slate-600 mb-1">Additional notes (optional)</label>
          <textarea v-model="form.notes" rows="2" class="input" placeholder="Anything HR should know up front." />
        </div>
      </div>
      <div class="flex items-center gap-2 mt-5">
        <button type="button" @click="submitResignation" :disabled="saving" class="px-4 py-2 rounded-lg bg-sycamore-700 text-white text-sm font-semibold hover:bg-sycamore-800 disabled:opacity-60">
          {{ saving ? 'Submitting...' : 'Submit resignation' }}
        </button>
        <button type="button" @click="showForm = false" class="px-4 py-2 rounded-lg border border-slate-300 text-sm text-slate-700 hover:bg-slate-50">
          Cancel
        </button>
      </div>
    </section>

    <section v-else-if="activeCase" class="bg-white border border-slate-200 rounded-2xl p-6 mb-6">
      <div class="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <div class="flex items-center gap-2 mb-1">
            <span class="text-xs font-semibold uppercase tracking-wider text-slate-500">
              {{ activeCase.exit_type }}
            </span>
            <span class="text-xs px-2 py-0.5 rounded-full border font-semibold capitalize" :class="statusChip(activeCase.status)">
              {{ activeCase.status.replace('_',' ') }}
            </span>
          </div>
          <h2 class="text-xl font-semibold text-slate-900">Your exit is in progress</h2>
          <p class="text-sm text-slate-500 mt-1">
            Effective {{ activeCase.effective_date || '—' }} &middot; last working day {{ activeCase.last_working_day || 'TBC' }}
          </p>
        </div>
        <div class="text-right">
          <div class="text-xs font-semibold text-slate-500 mb-1">Checklist progress</div>
          <div class="text-2xl font-bold text-slate-900">{{ progress() }}%</div>
        </div>
      </div>

      <div class="mt-4 h-2 bg-slate-100 rounded-full overflow-hidden">
        <div class="h-full bg-emerald-500 transition-all" :style="{ width: progress() + '%' }"></div>
      </div>

      <div v-if="activeCase.initiated_by_kind === 'self' && activeCase.status !== 'completed' && activeCase.status !== 'cancelled'" class="mt-5">
        <button type="button" @click="cancelResignation" class="text-sm text-rose-600 hover:text-rose-700 font-semibold">
          Withdraw resignation
        </button>
      </div>
    </section>

    <section v-if="activeCase && items.length" class="space-y-4">
      <h3 class="text-lg font-semibold text-slate-900">Offboarding checklist</h3>
      <div v-for="unit in units" :key="unit.code">
        <div v-if="itemsByUnit.get(unit.code)?.length" class="bg-white border border-slate-200 rounded-2xl overflow-hidden">
          <header class="px-5 py-3 bg-slate-50 border-b border-slate-200 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <SidebarIcon :name="unit.icon" />
              <span class="font-semibold text-slate-900">{{ unit.name }}</span>
            </div>
            <span class="text-xs text-slate-500">
              {{ itemsByUnit.get(unit.code)!.filter(i => i.status === 'done').length }}
              / {{ itemsByUnit.get(unit.code)!.length }} done
            </span>
          </header>
          <ul class="divide-y divide-slate-100">
            <li v-for="it in itemsByUnit.get(unit.code)" :key="it.id" class="px-5 py-3 flex items-start gap-3">
              <div class="mt-0.5">
                <span
                  v-if="it.status === 'done'"
                  class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-emerald-500 text-white text-xs"
                >
                  &#10003;
                </span>
                <span
                  v-else-if="it.status === 'not_applicable'"
                  class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-slate-300 text-white text-xs"
                >
                  &mdash;
                </span>
                <span
                  v-else
                  class="inline-block w-5 h-5 rounded-full border-2 border-slate-300"
                ></span>
              </div>
              <div class="flex-1 min-w-0">
                <div class="text-sm font-medium text-slate-900">{{ it.title }}</div>
                <div v-if="it.detail" class="text-xs text-slate-500 mt-0.5">{{ it.detail }}</div>
                <div v-if="it.notes" class="text-xs text-slate-600 mt-1 italic">"{{ it.notes }}"</div>
              </div>
            </li>
          </ul>
        </div>
      </div>
    </section>

    <section v-if="!activeCase && cases.length" class="mt-8">
      <h3 class="text-lg font-semibold text-slate-900 mb-3">History</h3>
      <ul class="bg-white border border-slate-200 rounded-2xl divide-y divide-slate-100">
        <li v-for="c in cases" :key="c.id" class="px-5 py-3 flex items-center justify-between gap-3">
          <div>
            <div class="text-sm font-semibold text-slate-900 capitalize">{{ c.exit_type }}</div>
            <div class="text-xs text-slate-500">Submitted {{ new Date(c.created_at).toLocaleDateString() }}</div>
          </div>
          <span class="text-xs px-2 py-0.5 rounded-full border font-semibold capitalize" :class="statusChip(c.status)">
            {{ c.status.replace('_',' ') }}
          </span>
        </li>
      </ul>
    </section>

    <section v-if="!loading && !activeCase && !showForm && !cases.length" class="bg-white border border-slate-200 rounded-2xl p-10 text-center">
      <p class="text-slate-500 text-sm">No active exit in progress.</p>
    </section>
  </div>
</template>
