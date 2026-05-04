<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'
import { useExit, type ExitUnit, type ExitChecklistItem } from '~/composables/useExit'

const supabase = useSupabase()
const toast = useToast()
const { user } = useAuth()
const { loadUnits, loadItems, notifyHods } = useExit()

const route = useRoute()

const filter = ref<'active' | 'completed' | 'cancelled' | 'all'>('active')
const cases = ref<any[]>([])
const loading = ref(true)
const units = ref<ExitUnit[]>([])
const staffOptions = ref<{ id: string; full_name: string; auth_user_id: string | null; role: string; department_name: string | null }[]>([])

const selectedCase = ref<any | null>(null)
const items = ref<ExitChecklistItem[]>([])
const selectedLoading = ref(false)

const showInitiate = ref(false)
const initiateForm = ref({
  staff_id: '',
  exit_type: 'termination' as 'resignation' | 'termination',
  reason: '',
  effective_date: new Date().toISOString().slice(0, 10),
  last_working_day: '',
  notes: ''
})
const saving = ref(false)

async function load() {
  loading.value = true
  try {
    let q = supabase
      .from('exit_cases')
      .select('*, staff:staff_members(id, full_name, email, role, auth_user_id, department:departments!staff_members_department_id_fkey(name))')
      .order('created_at', { ascending: false })
    if (filter.value === 'active') q = q.in('status', ['initiated', 'in_progress'])
    else if (filter.value === 'completed') q = q.eq('status', 'completed')
    else if (filter.value === 'cancelled') q = q.eq('status', 'cancelled')
    const { data } = await q
    cases.value = data ?? []
    if (!units.value.length) units.value = await loadUnits()
    if (!staffOptions.value.length) {
      const { data: staff, error: staffErr } = await supabase
        .from('staff_members')
        .select('id, full_name, auth_user_id, role, department:departments!staff_members_department_id_fkey(name)')
        .eq('is_active', true)
        .order('full_name')
      if (staffErr) {
        toast.error(staffErr.message)
      } else {
        staffOptions.value = ((staff as any[]) ?? []).map(s => ({
          id: s.id,
          full_name: s.full_name,
          auth_user_id: s.auth_user_id,
          role: s.role,
          department_name: s.department?.name ?? null
        }))
      }
    }
    const caseId = route.query.case as string | undefined
    if (caseId) {
      const match = cases.value.find(c => c.id === caseId)
      if (match) await openCase(match)
    }
  } finally {
    loading.value = false
  }
}
load()
watch(filter, load)

async function openCase(c: any) {
  selectedCase.value = c
  selectedLoading.value = true
  try {
    items.value = await loadItems(c.id)
  } finally {
    selectedLoading.value = false
  }
}

function closeCase() {
  selectedCase.value = null
  items.value = []
}

async function initiateExit() {
  if (!initiateForm.value.staff_id || !user.value) {
    toast.error('Pick a staff member.')
    return
  }
  if (!initiateForm.value.reason.trim()) {
    toast.error('Provide a reason.')
    return
  }
  saving.value = true
  try {
    const { data, error } = await supabase
      .from('exit_cases')
      .insert({
        staff_id: initiateForm.value.staff_id,
        exit_type: initiateForm.value.exit_type,
        reason: initiateForm.value.reason.trim(),
        effective_date: initiateForm.value.effective_date || null,
        last_working_day: initiateForm.value.last_working_day || null,
        notes: initiateForm.value.notes.trim(),
        status: 'initiated',
        initiated_by_user_id: user.value.id,
        initiated_by_kind: 'admin'
      })
      .select('*, staff:staff_members(id, full_name)')
      .maybeSingle()
    if (error) throw error
    if (data) {
      await notifyHods(data as any, (data as any).staff?.full_name ?? 'Staff member')
    }
    toast.success('Exit case opened. Unit heads have been notified.')
    showInitiate.value = false
    initiateForm.value = {
      staff_id: '',
      exit_type: 'termination',
      reason: '',
      effective_date: new Date().toISOString().slice(0, 10),
      last_working_day: '',
      notes: ''
    }
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to open exit case')
  } finally {
    saving.value = false
  }
}

async function updateItem(item: ExitChecklistItem, patch: Partial<ExitChecklistItem>) {
  if (!user.value) return
  try {
    const nextStatus = patch.status ?? item.status
    const payload: any = { ...patch }
    if (nextStatus === 'done') {
      payload.completed_at = new Date().toISOString()
      payload.completed_by = user.value.id
    } else if (nextStatus !== 'done') {
      payload.completed_at = null
      payload.completed_by = null
    }
    const { error } = await supabase.from('exit_checklist_items').update(payload).eq('id', item.id)
    if (error) throw error
    if (selectedCase.value) items.value = await loadItems(selectedCase.value.id)
    await maybeAutoComplete()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to update task')
  }
}

async function maybeAutoComplete() {
  if (!selectedCase.value) return
  if (!items.value.length) return
  const allDone = items.value.every(i => i.status === 'done' || i.status === 'not_applicable')
  if (allDone && selectedCase.value.status !== 'completed') {
    await supabase.from('exit_cases').update({ status: 'completed', completed_at: new Date().toISOString() }).eq('id', selectedCase.value.id)
    toast.success('All tasks completed — case marked completed.')
    await load()
    const refreshed = cases.value.find(c => c.id === selectedCase.value.id)
    if (refreshed) selectedCase.value = refreshed
  } else if (!allDone && selectedCase.value.status === 'initiated') {
    await supabase.from('exit_cases').update({ status: 'in_progress' }).eq('id', selectedCase.value.id)
    await load()
    const refreshed = cases.value.find(c => c.id === selectedCase.value.id)
    if (refreshed) selectedCase.value = refreshed
  }
}

async function assignItem(item: ExitChecklistItem, newAssignee: string) {
  await updateItem(item, { assignee_user_id: newAssignee || null })
}

async function setCaseStatus(status: 'in_progress' | 'completed' | 'cancelled') {
  if (!selectedCase.value) return
  try {
    const payload: any = { status }
    if (status === 'completed') payload.completed_at = new Date().toISOString()
    const { error } = await supabase.from('exit_cases').update(payload).eq('id', selectedCase.value.id)
    if (error) throw error
    toast.success('Case updated.')
    await load()
    const refreshed = cases.value.find(c => c.id === selectedCase.value!.id)
    if (refreshed) selectedCase.value = refreshed
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

function unit(code: string) { return units.value.find(u => u.code === code) }
function progressOf(c: any) {
  if (!selectedCase.value || selectedCase.value.id !== c.id || !items.value.length) return null
  const done = items.value.filter(i => i.status === 'done' || i.status === 'not_applicable').length
  return Math.round((done / items.value.length) * 100)
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
  <div class="max-w-7xl">
    <header class="mb-6 flex items-center justify-between flex-wrap gap-3">
      <div>
        <h1 class="text-2xl font-semibold text-slate-900">Exit workflow</h1>
        <p class="text-sm text-slate-500 mt-1">Resignations and terminations with an end-to-end clearance checklist.</p>
      </div>
      <div class="flex items-center gap-2">
        <div class="flex gap-1 bg-slate-100 rounded-lg p-1">
          <button v-for="f in ['active','completed','cancelled','all']" :key="f"
            type="button" @click="filter = (f as any)"
            class="text-xs font-semibold px-3 py-1.5 rounded-md capitalize"
            :class="filter === f ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
            {{ f }}
          </button>
        </div>
        <button type="button" @click="showInitiate = true" class="px-4 py-2 rounded-lg bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800">
          Initiate termination
        </button>
      </div>
    </header>

    <div v-if="loading" class="text-sm text-slate-500">Loading...</div>

    <div v-else class="grid lg:grid-cols-[1fr_1.3fr] gap-6">
      <section class="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <header class="px-5 py-3 border-b border-slate-200 flex items-center justify-between">
          <span class="text-sm font-semibold text-slate-700">Cases ({{ cases.length }})</span>
        </header>
        <ul v-if="cases.length" class="divide-y divide-slate-100 max-h-[70vh] overflow-y-auto">
          <li v-for="c in cases" :key="c.id">
            <button
              type="button"
              @click="openCase(c)"
              class="w-full text-left px-5 py-4 hover:bg-slate-50 transition-colors"
              :class="selectedCase?.id === c.id ? 'bg-sycamore-50/50' : ''"
            >
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <div class="text-sm font-semibold text-slate-900 truncate">{{ c.staff?.full_name }}</div>
                  <div class="text-xs text-slate-500 truncate">{{ c.staff?.role }} &middot; {{ c.staff?.department?.name || '—' }}</div>
                </div>
                <span class="text-xs px-2 py-0.5 rounded-full border font-semibold capitalize shrink-0" :class="statusChip(c.status)">
                  {{ c.status.replace('_',' ') }}
                </span>
              </div>
              <div class="mt-2 flex items-center justify-between text-xs text-slate-500">
                <span class="capitalize">{{ c.exit_type }}</span>
                <span>{{ new Date(c.created_at).toLocaleDateString() }}</span>
              </div>
              <div v-if="progressOf(c) !== null" class="mt-2 h-1 bg-slate-100 rounded-full overflow-hidden">
                <div class="h-full bg-emerald-500" :style="{ width: progressOf(c) + '%' }"></div>
              </div>
            </button>
          </li>
        </ul>
        <div v-else class="p-6 text-sm text-slate-500">No cases in this filter.</div>
      </section>

      <section v-if="selectedCase" class="bg-white border border-slate-200 rounded-xl">
        <header class="px-5 py-4 border-b border-slate-200 flex items-start justify-between gap-4 flex-wrap">
          <div>
            <div class="flex items-center gap-2 mb-1">
              <span class="text-xs font-semibold uppercase tracking-wider text-slate-500">{{ selectedCase.exit_type }}</span>
              <span class="text-xs px-2 py-0.5 rounded-full border font-semibold capitalize" :class="statusChip(selectedCase.status)">
                {{ selectedCase.status.replace('_',' ') }}
              </span>
            </div>
            <h2 class="text-lg font-semibold text-slate-900">{{ selectedCase.staff?.full_name }}</h2>
            <div class="text-xs text-slate-500">{{ selectedCase.staff?.email }}</div>
            <div class="text-xs text-slate-500 mt-1">
              Effective {{ selectedCase.effective_date || '—' }} &middot; last working day {{ selectedCase.last_working_day || 'TBC' }}
            </div>
          </div>
          <div class="flex items-center gap-2">
            <button type="button" @click="closeCase" class="text-slate-400 hover:text-slate-700 text-xs">Close</button>
          </div>
        </header>

        <div class="px-5 py-3 bg-slate-50 border-b border-slate-200 flex items-center justify-between gap-4 flex-wrap">
          <div class="flex-1 min-w-[200px]">
            <div class="text-xs font-semibold text-slate-500 mb-1">Progress</div>
            <div class="flex items-center gap-3">
              <div class="flex-1 h-2 bg-white rounded-full overflow-hidden border border-slate-200">
                <div class="h-full bg-emerald-500 transition-all" :style="{ width: progress() + '%' }"></div>
              </div>
              <span class="text-sm font-semibold text-slate-900">{{ progress() }}%</span>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <button v-if="selectedCase.status !== 'completed'" type="button" @click="setCaseStatus('completed')" class="px-3 py-1.5 text-xs font-semibold rounded-lg bg-emerald-600 text-white hover:bg-emerald-700">
              Mark completed
            </button>
            <button v-if="selectedCase.status !== 'cancelled'" type="button" @click="setCaseStatus('cancelled')" class="px-3 py-1.5 text-xs font-semibold rounded-lg bg-rose-50 text-rose-700 border border-rose-200 hover:bg-rose-100">
              Cancel case
            </button>
          </div>
        </div>

        <div v-if="selectedCase.reason" class="px-5 py-3 border-b border-slate-100 text-sm text-slate-700">
          <div class="text-xs font-semibold text-slate-500 mb-1">Reason</div>
          {{ selectedCase.reason }}
        </div>

        <div v-if="selectedLoading" class="p-6 text-sm text-slate-500">Loading checklist...</div>

        <div v-else class="p-5 space-y-4 max-h-[65vh] overflow-y-auto">
          <div v-for="u in units" :key="u.code">
            <div v-if="itemsByUnit.get(u.code)?.length" class="border border-slate-200 rounded-xl overflow-hidden">
              <header class="px-4 py-2.5 bg-slate-50 border-b border-slate-200 flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <SidebarIcon :name="u.icon" />
                  <span class="font-semibold text-slate-900 text-sm">{{ u.name }}</span>
                </div>
                <span class="text-xs text-slate-500">
                  {{ itemsByUnit.get(u.code)!.filter(i => i.status === 'done').length }}/{{ itemsByUnit.get(u.code)!.length }}
                </span>
              </header>
              <ul class="divide-y divide-slate-100">
                <li v-for="it in itemsByUnit.get(u.code)" :key="it.id" class="px-4 py-3">
                  <div class="flex items-start gap-3">
                    <input
                      type="checkbox"
                      :checked="it.status === 'done'"
                      @change="updateItem(it, { status: (($event.target as HTMLInputElement).checked ? 'done' : 'pending') })"
                      class="mt-1 w-4 h-4 rounded border-slate-300 text-emerald-600 focus:ring-emerald-500"
                    />
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center justify-between gap-2 flex-wrap">
                        <div class="text-sm font-medium text-slate-900" :class="it.status === 'done' ? 'line-through text-slate-500' : ''">{{ it.title }}</div>
                        <div class="flex items-center gap-2">
                          <select
                            :value="it.assignee_user_id ?? ''"
                            @change="assignItem(it, ($event.target as HTMLSelectElement).value)"
                            class="text-xs border border-slate-300 rounded-md px-2 py-1 bg-white"
                          >
                            <option value="">Unassigned</option>
                            <option v-for="s in staffOptions" :key="s.id" :value="s.auth_user_id ?? ''" :disabled="!s.auth_user_id">
                              {{ s.full_name }}
                            </option>
                          </select>
                          <button
                            type="button"
                            @click="updateItem(it, { status: it.status === 'not_applicable' ? 'pending' : 'not_applicable' })"
                            class="text-xs px-2 py-1 rounded-md border"
                            :class="it.status === 'not_applicable' ? 'bg-slate-800 text-white border-slate-800' : 'border-slate-300 text-slate-600 hover:bg-slate-50'"
                          >
                            N/A
                          </button>
                        </div>
                      </div>
                      <div v-if="it.detail" class="text-xs text-slate-500 mt-0.5">{{ it.detail }}</div>
                      <input
                        :value="it.notes"
                        @change="updateItem(it, { notes: ($event.target as HTMLInputElement).value })"
                        placeholder="Notes (optional)"
                        class="mt-2 w-full text-xs border border-slate-200 rounded-md px-2 py-1 bg-slate-50 focus:bg-white focus:border-slate-300"
                      />
                    </div>
                  </div>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      <section v-else class="bg-white border border-slate-200 border-dashed rounded-xl p-12 text-center text-sm text-slate-500">
        Select a case on the left to review and action the checklist.
      </section>
    </div>

    <!-- Initiate modal -->
    <div v-if="showInitiate" class="fixed inset-0 z-50 bg-slate-900/40 flex items-center justify-center p-4" @click.self="showInitiate = false">
      <div class="bg-white rounded-2xl shadow-xl w-full max-w-lg p-6">
        <h2 class="text-lg font-semibold text-slate-900">Initiate exit</h2>
        <p class="text-xs text-slate-500 mt-1 mb-4">This opens a case and notifies all unit HoDs.</p>
        <div class="space-y-3">
          <div>
            <label class="block text-xs font-semibold text-slate-600 mb-1">Exit type</label>
            <div class="flex gap-2">
              <label class="flex-1 flex items-center gap-2 border rounded-lg px-3 py-2 cursor-pointer" :class="initiateForm.exit_type === 'resignation' ? 'border-sycamore-600 bg-sycamore-50' : 'border-slate-300'">
                <input type="radio" v-model="initiateForm.exit_type" value="resignation" class="sr-only" />
                <span class="text-sm font-medium text-slate-900">Resignation</span>
              </label>
              <label class="flex-1 flex items-center gap-2 border rounded-lg px-3 py-2 cursor-pointer" :class="initiateForm.exit_type === 'termination' ? 'border-sycamore-600 bg-sycamore-50' : 'border-slate-300'">
                <input type="radio" v-model="initiateForm.exit_type" value="termination" class="sr-only" />
                <span class="text-sm font-medium text-slate-900">Termination</span>
              </label>
            </div>
          </div>
          <div>
            <label class="block text-xs font-semibold text-slate-600 mb-1">Staff member</label>
            <select v-model="initiateForm.staff_id" class="input">
              <option value="">Select staff...</option>
              <option v-for="s in staffOptions" :key="s.id" :value="s.id">{{ s.full_name }} &middot; {{ s.role }}</option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-semibold text-slate-600 mb-1">Reason / grounds</label>
            <textarea v-model="initiateForm.reason" rows="3" class="input" placeholder="Document the reason or grounds for the exit." />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-semibold text-slate-600 mb-1">Effective date</label>
              <input v-model="initiateForm.effective_date" type="date" class="input" />
            </div>
            <div>
              <label class="block text-xs font-semibold text-slate-600 mb-1">Last working day</label>
              <input v-model="initiateForm.last_working_day" type="date" class="input" />
            </div>
          </div>
          <div>
            <label class="block text-xs font-semibold text-slate-600 mb-1">Notes (optional)</label>
            <textarea v-model="initiateForm.notes" rows="2" class="input" />
          </div>
        </div>
        <div class="flex items-center justify-end gap-2 mt-5">
          <button type="button" @click="showInitiate = false" class="px-4 py-2 rounded-lg border border-slate-300 text-sm text-slate-700 hover:bg-slate-50">Cancel</button>
          <button type="button" :disabled="saving" @click="initiateExit" class="px-4 py-2 rounded-lg bg-slate-900 text-white text-sm font-semibold hover:bg-slate-800 disabled:opacity-60">
            {{ saving ? 'Opening...' : 'Open case' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
