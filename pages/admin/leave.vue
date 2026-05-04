<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'
import { useLeave, type LeaveType, type PublicHoliday } from '~/composables/useLeave'

const supabase = useSupabase()
const toast = useToast()
const { user, canPerform } = useAuth()
const { loadLeaveTypes, loadPublicHolidays } = useLeave()

const tab = ref<'requests' | 'balances' | 'types' | 'holidays'>('requests')
const loading = ref(true)

const requests = ref<any[]>([])
const requestFilter = ref<'pending' | 'approved' | 'declined' | 'cancelled' | 'all'>('pending')
const selected = ref<any | null>(null)
const decision = ref({ status: 'approved' as 'approved' | 'declined', notes: '' })
const savingDecision = ref(false)

const types = ref<LeaveType[]>([])
const holidays = ref<PublicHoliday[]>([])
const balances = ref<any[]>([])
const year = ref(new Date().getFullYear())

const editingType = ref<any | null>(null)
const editingHoliday = ref<any | null>(null)
const editingBalance = ref<any | null>(null)

async function loadRequests() {
  let q = supabase
    .from('leave_requests')
    .select('*, leave_type:leave_types(name,color,paid), staff:staff_members!leave_requests_staff_id_fkey(id, full_name, email, role, manager_id, auth_user_id), relief:staff_members!leave_requests_relief_officer_id_fkey(id, full_name, role)')
    .order('created_at', { ascending: false })
  if (requestFilter.value !== 'all') q = q.eq('status', requestFilter.value)
  const { data } = await q
  requests.value = data ?? []
}

async function loadBalances() {
  const { data } = await supabase
    .from('leave_balances')
    .select('*, leave_type:leave_types(name,color), staff:staff_members(full_name, email, role)')
    .eq('year', year.value)
    .order('created_at', { ascending: false })
  balances.value = data ?? []
}

async function loadAll() {
  loading.value = true
  try {
    const [ts, hs] = await Promise.all([loadLeaveTypes(), loadPublicHolidays()])
    types.value = ts
    holidays.value = hs
    await Promise.all([loadRequests(), loadBalances()])
  } finally {
    loading.value = false
  }
}
loadAll()

watch(requestFilter, loadRequests)
watch(year, loadBalances)

function statusClass(s: string) {
  if (s === 'approved') return 'bg-emerald-50 text-emerald-700 border-emerald-200'
  if (s === 'declined') return 'bg-rose-50 text-rose-700 border-rose-200'
  if (s === 'cancelled') return 'bg-slate-100 text-slate-600 border-slate-200'
  return 'bg-amber-50 text-amber-700 border-amber-200'
}

function openDecide(row: any, status: 'approved' | 'declined') {
  selected.value = row
  decision.value = { status, notes: '' }
}

async function applyDecision() {
  if (!selected.value || !user.value) return
  savingDecision.value = true
  try {
    const req = selected.value
    const next = decision.value.status
    const { error } = await supabase
      .from('leave_requests')
      .update({
        status: next,
        decision_notes: decision.value.notes.trim(),
        approver_id: user.value.id,
        decided_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      })
      .eq('id', req.id)
    if (error) throw error

    if (next === 'approved') {
      const { data: bal } = await supabase
        .from('leave_balances')
        .select('id, used_days')
        .eq('staff_id', req.staff_id)
        .eq('leave_type_id', req.leave_type_id)
        .eq('year', new Date(req.start_date).getFullYear())
        .maybeSingle()
      if (bal) {
        await supabase
          .from('leave_balances')
          .update({
            used_days: Number((bal as any).used_days) + Number(req.working_days),
            updated_at: new Date().toISOString()
          })
          .eq('id', (bal as any).id)
      }

      const dates: { day: string; staff_id: string; kind: string; label: string }[] = []
      const start = new Date(req.start_date + 'T00:00:00')
      const end = new Date(req.end_date + 'T00:00:00')
      for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
        const dow = d.getDay()
        if (dow === 0 || dow === 6) continue
        dates.push({
          day: d.toISOString().slice(0, 10),
          staff_id: req.staff_id,
          kind: 'leave',
          label: req.leave_type?.name ?? 'Leave'
        })
      }
      if (dates.length) {
        await supabase.from('attendance_days').upsert(dates, { onConflict: 'day,staff_id' })
      }
    }

    try {
      await supabase.from('notifications').insert({
        recipient_id: req.requester_user_id,
        actor_id: user.value.id,
        type: 'leave_decision',
        title: `Your leave request was ${next}`,
        body: decision.value.notes.trim() || `${req.working_days} day(s) of ${req.leave_type?.name ?? 'leave'}`,
        link: '/leave'
      })
    } catch { /* non-fatal */ }

    toast.success('Decision saved')
    selected.value = null
    await loadRequests()
    await loadBalances()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  } finally {
    savingDecision.value = false
  }
}

// Types CRUD
function newType() {
  editingType.value = { name: '', code: '', color: '#16a34a', default_days_per_year: 0, paid: true, requires_approval: true, is_active: true, sort_order: 0, description: '' }
}
function editType(t: any) { editingType.value = { ...t } }

async function saveType() {
  const t = editingType.value
  if (!t) return
  try {
    const payload: any = {
      name: t.name?.trim(),
      code: t.code?.trim().toLowerCase(),
      color: t.color || '#16a34a',
      default_days_per_year: Number(t.default_days_per_year) || 0,
      paid: !!t.paid,
      requires_approval: !!t.requires_approval,
      is_active: !!t.is_active,
      sort_order: Number(t.sort_order) || 0,
      description: t.description || '',
      updated_at: new Date().toISOString()
    }
    if (t.id) await supabase.from('leave_types').update(payload).eq('id', t.id)
    else await supabase.from('leave_types').insert(payload)
    toast.success('Saved')
    editingType.value = null
    types.value = await loadLeaveTypes()
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

async function deleteType(t: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${t.name}"?`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try {
    const { error } = await supabase.from('leave_types').delete().eq('id', t.id)
    if (error) throw error
    toast.success('Deleted')
    types.value = await loadLeaveTypes()
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

// Holidays CRUD
function newHoliday() { editingHoliday.value = { day: '', name: '', country: 'NG', recurring_yearly: false, is_active: true } }
function editHoliday(h: any) { editingHoliday.value = { ...h } }

async function saveHoliday() {
  const h = editingHoliday.value
  if (!h) return
  try {
    const payload: any = {
      day: h.day,
      name: h.name?.trim(),
      country: h.country || 'NG',
      recurring_yearly: !!h.recurring_yearly,
      is_active: !!h.is_active
    }
    if (h.id) await supabase.from('public_holidays').update(payload).eq('id', h.id)
    else await supabase.from('public_holidays').insert(payload)
    toast.success('Saved')
    editingHoliday.value = null
    holidays.value = await loadPublicHolidays()
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

async function deleteHoliday(h: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${h.name}"?`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try {
    const { error } = await supabase.from('public_holidays').delete().eq('id', h.id)
    if (error) throw error
    toast.success('Deleted')
    holidays.value = await loadPublicHolidays()
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

// Balances adjustment
function editBalance(b: any) { editingBalance.value = { ...b } }

async function saveBalance() {
  const b = editingBalance.value
  if (!b) return
  try {
    await supabase
      .from('leave_balances')
      .update({
        allocated_days: Number(b.allocated_days) || 0,
        adjustment_days: Number(b.adjustment_days) || 0,
        used_days: Number(b.used_days) || 0,
        updated_at: new Date().toISOString()
      })
      .eq('id', b.id)
    toast.success('Saved')
    editingBalance.value = null
    await loadBalances()
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

const canManage = computed(() => canPerform('attendance', 'update'))
</script>

<template>
  <div class="max-w-7xl">
    <header class="mb-6">
      <h1 class="text-2xl font-semibold text-slate-900">Leave management</h1>
      <p class="text-sm text-slate-500 mt-1">Approve requests, manage balances, leave types, and public holidays.</p>
    </header>

    <nav class="flex gap-1 bg-slate-100 rounded-lg p-1 mb-6 w-max">
      <button v-for="t in ['requests','balances','types','holidays']" :key="t"
        type="button" @click="tab = (t as any)"
        class="text-xs font-semibold px-3 py-1.5 rounded-md capitalize"
        :class="tab === t ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
        {{ t }}
      </button>
    </nav>

    <!-- REQUESTS -->
    <section v-if="tab === 'requests'" class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <header class="px-5 py-4 border-b border-slate-200 flex items-center justify-between flex-wrap gap-3">
        <h2 class="text-sm font-semibold text-slate-900">Requests</h2>
        <div class="flex gap-1 bg-slate-100 rounded-lg p-1">
          <button v-for="f in ['pending','approved','declined','cancelled','all']" :key="f"
            type="button" @click="requestFilter = (f as any)"
            class="text-xs font-semibold px-3 py-1 rounded-md capitalize"
            :class="requestFilter === f ? 'bg-white shadow text-slate-900' : 'text-slate-500'">
            {{ f }}
          </button>
        </div>
      </header>
      <div v-if="loading" class="p-5 text-sm text-slate-500">Loading...</div>
      <div v-else-if="requests.length === 0" class="p-5 text-sm text-slate-500">No requests.</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Staff</th>
            <th class="text-left px-5 py-2">Type</th>
            <th class="text-left px-5 py-2">From</th>
            <th class="text-left px-5 py-2">To</th>
            <th class="text-right px-5 py-2">Days</th>
            <th class="text-left px-5 py-2">Status</th>
            <th class="text-right px-5 py-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in requests" :key="r.id" class="border-t border-slate-100 align-top">
            <td class="px-5 py-3">
              <div class="font-medium text-slate-900">{{ r.staff?.full_name }}</div>
              <div class="text-xs text-slate-500">{{ r.staff?.role }}</div>
            </td>
            <td class="px-5 py-3">
              <span class="inline-flex items-center gap-2">
                <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: r.leave_type?.color }"></span>
                {{ r.leave_type?.name }}
              </span>
            </td>
            <td class="px-5 py-3">{{ r.start_date }}</td>
            <td class="px-5 py-3">{{ r.end_date }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ r.working_days }}</td>
            <td class="px-5 py-3">
              <span class="text-xs font-semibold px-2 py-0.5 rounded border capitalize" :class="statusClass(r.status)">{{ r.status }}</span>
              <p v-if="r.reason" class="text-xs text-slate-500 mt-1 max-w-xs">{{ r.reason }}</p>
              <div v-if="r.relief_officer_id" class="mt-2 text-xs text-slate-600">
                <span class="font-semibold">Relief:</span> {{ r.relief?.full_name ?? '—' }}
                <span class="inline-block ml-1 px-1.5 py-0.5 rounded border text-[10px] font-semibold capitalize"
                  :class="r.relief_accepted_at ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : (r.relief_declined_at ? 'bg-rose-50 text-rose-700 border-rose-200' : 'bg-amber-50 text-amber-700 border-amber-200')">
                  {{ r.relief_accepted_at ? 'accepted' : (r.relief_declined_at ? 'declined' : 'pending') }}
                </span>
              </div>
              <details v-if="r.handover_notes" class="mt-2 text-xs text-slate-600">
                <summary class="cursor-pointer text-sycamore-700 font-semibold">Handover notes</summary>
                <p class="whitespace-pre-wrap mt-1 max-w-md">{{ r.handover_notes }}</p>
              </details>
            </td>
            <td class="px-5 py-3 text-right whitespace-nowrap space-x-2">
              <template v-if="r.status === 'pending'">
                <button type="button" @click="openDecide(r, 'approved')" class="text-xs font-semibold px-2.5 py-1 rounded bg-emerald-600 text-white hover:bg-emerald-700">Approve</button>
                <button type="button" @click="openDecide(r, 'declined')" class="text-xs font-semibold px-2.5 py-1 rounded bg-rose-600 text-white hover:bg-rose-700">Decline</button>
              </template>
              <span v-else-if="r.decision_notes" class="text-xs text-slate-500" :title="r.decision_notes">Note</span>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <!-- BALANCES -->
    <section v-else-if="tab === 'balances'" class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <header class="px-5 py-4 border-b border-slate-200 flex items-center justify-between">
        <h2 class="text-sm font-semibold text-slate-900">Balances &middot; {{ year }}</h2>
        <label class="text-xs text-slate-500">Year
          <input v-model.number="year" type="number" class="ml-2 w-24 border border-slate-300 rounded px-2 py-1 text-sm" />
        </label>
      </header>
      <div v-if="loading" class="p-5 text-sm text-slate-500">Loading...</div>
      <div v-else-if="balances.length === 0" class="p-5 text-sm text-slate-500">No balances yet. Balances are created automatically when staff visit the Leave page.</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Staff</th>
            <th class="text-left px-5 py-2">Type</th>
            <th class="text-right px-5 py-2">Allocated</th>
            <th class="text-right px-5 py-2">Adjustment</th>
            <th class="text-right px-5 py-2">Used</th>
            <th class="text-right px-5 py-2">Remaining</th>
            <th class="text-right px-5 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="b in balances" :key="b.id" class="border-t border-slate-100">
            <td class="px-5 py-3">
              <div class="font-medium text-slate-900">{{ b.staff?.full_name }}</div>
              <div class="text-xs text-slate-500">{{ b.staff?.role }}</div>
            </td>
            <td class="px-5 py-3">
              <span class="inline-flex items-center gap-2">
                <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: b.leave_type?.color }"></span>
                {{ b.leave_type?.name }}
              </span>
            </td>
            <td class="px-5 py-3 text-right tabular-nums">{{ b.allocated_days }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ b.adjustment_days }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ b.used_days }}</td>
            <td class="px-5 py-3 text-right tabular-nums font-semibold">{{ (Number(b.allocated_days) + Number(b.adjustment_days) - Number(b.used_days)).toFixed(1) }}</td>
            <td class="px-5 py-3 text-right">
              <button v-if="canManage" type="button" @click="editBalance(b)" class="text-xs font-semibold text-sycamore-700">Edit</button>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <!-- TYPES -->
    <section v-else-if="tab === 'types'" class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <header class="px-5 py-4 border-b border-slate-200 flex items-center justify-between">
        <h2 class="text-sm font-semibold text-slate-900">Leave types</h2>
        <button v-if="canManage" type="button" @click="newType" class="text-xs font-semibold px-3 py-1.5 rounded bg-sycamore-600 hover:bg-sycamore-700 text-white">New type</button>
      </header>
      <table class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Name</th>
            <th class="text-left px-5 py-2">Code</th>
            <th class="text-right px-5 py-2">Default days</th>
            <th class="text-left px-5 py-2">Paid</th>
            <th class="text-left px-5 py-2">Active</th>
            <th class="text-right px-5 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="t in types" :key="t.id" class="border-t border-slate-100">
            <td class="px-5 py-3">
              <span class="inline-flex items-center gap-2">
                <span class="w-2.5 h-2.5 rounded-full" :style="{ backgroundColor: t.color }"></span>
                <span class="font-medium text-slate-900">{{ t.name }}</span>
              </span>
            </td>
            <td class="px-5 py-3 text-slate-500">{{ t.code }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ t.default_days_per_year }}</td>
            <td class="px-5 py-3">{{ t.paid ? 'Yes' : 'No' }}</td>
            <td class="px-5 py-3">{{ t.is_active ? 'Yes' : 'No' }}</td>
            <td class="px-5 py-3 text-right space-x-3">
              <button v-if="canManage" type="button" @click="editType(t)" class="text-xs font-semibold text-sycamore-700">Edit</button>
              <button v-if="canManage" type="button" @click="deleteType(t)" class="text-xs font-semibold text-rose-600">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <!-- HOLIDAYS -->
    <section v-else-if="tab === 'holidays'" class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <header class="px-5 py-4 border-b border-slate-200 flex items-center justify-between">
        <h2 class="text-sm font-semibold text-slate-900">Public holidays</h2>
        <button v-if="canManage" type="button" @click="newHoliday" class="text-xs font-semibold px-3 py-1.5 rounded bg-sycamore-600 hover:bg-sycamore-700 text-white">New holiday</button>
      </header>
      <table class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Date</th>
            <th class="text-left px-5 py-2">Name</th>
            <th class="text-left px-5 py-2">Country</th>
            <th class="text-left px-5 py-2">Recurring</th>
            <th class="text-left px-5 py-2">Active</th>
            <th class="text-right px-5 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="h in holidays" :key="h.id" class="border-t border-slate-100">
            <td class="px-5 py-3">{{ h.day }}</td>
            <td class="px-5 py-3 font-medium text-slate-900">{{ h.name }}</td>
            <td class="px-5 py-3">{{ h.country }}</td>
            <td class="px-5 py-3">{{ h.recurring_yearly ? 'Yes' : 'No' }}</td>
            <td class="px-5 py-3">{{ h.is_active ? 'Yes' : 'No' }}</td>
            <td class="px-5 py-3 text-right space-x-3">
              <button v-if="canManage" type="button" @click="editHoliday(h)" class="text-xs font-semibold text-sycamore-700">Edit</button>
              <button v-if="canManage" type="button" @click="deleteHoliday(h)" class="text-xs font-semibold text-rose-600">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <!-- Decision modal -->
    <div v-if="selected" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="selected = null">
      <div class="bg-white rounded-2xl max-w-md w-full shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200">
          <h3 class="text-base font-semibold text-slate-900">{{ decision.status === 'approved' ? 'Approve' : 'Decline' }} leave</h3>
          <p class="text-xs text-slate-500 mt-1">{{ selected.staff?.full_name }} &middot; {{ selected.working_days }} day(s) &middot; {{ selected.leave_type?.name }}</p>
        </header>
        <div class="p-6">
          <label class="block">
            <span class="text-xs font-medium text-slate-600">Note to staff (optional)</span>
            <textarea v-model="decision.notes" rows="4" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"></textarea>
          </label>
        </div>
        <footer class="px-6 py-4 border-t border-slate-200 flex justify-end gap-2">
          <button type="button" @click="selected = null" class="text-sm px-3 py-2 rounded-lg hover:bg-slate-100">Cancel</button>
          <button type="button" @click="applyDecision" :disabled="savingDecision"
            class="text-sm font-semibold px-4 py-2 rounded-lg text-white"
            :class="decision.status === 'approved' ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-rose-600 hover:bg-rose-700'">
            {{ savingDecision ? 'Saving...' : (decision.status === 'approved' ? 'Approve' : 'Decline') }}
          </button>
        </footer>
      </div>
    </div>

    <!-- Type modal -->
    <div v-if="editingType" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="editingType = null">
      <div class="bg-white rounded-2xl max-w-lg w-full shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200">
          <h3 class="text-base font-semibold text-slate-900">{{ editingType.id ? 'Edit' : 'New' }} leave type</h3>
        </header>
        <div class="p-6 grid grid-cols-2 gap-4">
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Name</span>
            <input v-model="editingType.name" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Code</span>
            <input v-model="editingType.code" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Color</span>
            <input v-model="editingType.color" type="color" class="mt-1 w-full h-10 border border-slate-300 rounded-lg px-1 py-1 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Default days / year</span>
            <input v-model.number="editingType.default_days_per_year" type="number" step="0.5" min="0" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Sort order</span>
            <input v-model.number="editingType.sort_order" type="number" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="inline-flex items-center gap-2 text-sm"><input v-model="editingType.paid" type="checkbox" class="w-4 h-4 rounded border-slate-300 text-sycamore-600" /> Paid</label>
          <label class="inline-flex items-center gap-2 text-sm"><input v-model="editingType.requires_approval" type="checkbox" class="w-4 h-4 rounded border-slate-300 text-sycamore-600" /> Requires approval</label>
          <label class="inline-flex items-center gap-2 text-sm col-span-2"><input v-model="editingType.is_active" type="checkbox" class="w-4 h-4 rounded border-slate-300 text-sycamore-600" /> Active</label>
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Description</span>
            <textarea v-model="editingType.description" rows="2" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"></textarea></label>
        </div>
        <footer class="px-6 py-4 border-t border-slate-200 flex justify-end gap-2">
          <button type="button" @click="editingType = null" class="text-sm px-3 py-2 rounded-lg hover:bg-slate-100">Cancel</button>
          <button type="button" @click="saveType" class="text-sm font-semibold px-4 py-2 rounded-lg bg-sycamore-600 hover:bg-sycamore-700 text-white">Save</button>
        </footer>
      </div>
    </div>

    <!-- Holiday modal -->
    <div v-if="editingHoliday" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="editingHoliday = null">
      <div class="bg-white rounded-2xl max-w-md w-full shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200">
          <h3 class="text-base font-semibold text-slate-900">{{ editingHoliday.id ? 'Edit' : 'New' }} holiday</h3>
        </header>
        <div class="p-6 grid grid-cols-2 gap-4">
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Name</span>
            <input v-model="editingHoliday.name" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Date</span>
            <input v-model="editingHoliday.day" type="date" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Country</span>
            <input v-model="editingHoliday.country" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="inline-flex items-center gap-2 text-sm"><input v-model="editingHoliday.recurring_yearly" type="checkbox" class="w-4 h-4 rounded border-slate-300 text-sycamore-600" /> Repeats every year</label>
          <label class="inline-flex items-center gap-2 text-sm"><input v-model="editingHoliday.is_active" type="checkbox" class="w-4 h-4 rounded border-slate-300 text-sycamore-600" /> Active</label>
        </div>
        <footer class="px-6 py-4 border-t border-slate-200 flex justify-end gap-2">
          <button type="button" @click="editingHoliday = null" class="text-sm px-3 py-2 rounded-lg hover:bg-slate-100">Cancel</button>
          <button type="button" @click="saveHoliday" class="text-sm font-semibold px-4 py-2 rounded-lg bg-sycamore-600 hover:bg-sycamore-700 text-white">Save</button>
        </footer>
      </div>
    </div>

    <!-- Balance modal -->
    <div v-if="editingBalance" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="editingBalance = null">
      <div class="bg-white rounded-2xl max-w-md w-full shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200">
          <h3 class="text-base font-semibold text-slate-900">Edit balance</h3>
          <p class="text-xs text-slate-500 mt-1">{{ editingBalance.staff?.full_name }} &middot; {{ editingBalance.leave_type?.name }} &middot; {{ editingBalance.year }}</p>
        </header>
        <div class="p-6 grid grid-cols-3 gap-4">
          <label class="block"><span class="text-xs font-medium text-slate-600">Allocated</span>
            <input v-model.number="editingBalance.allocated_days" type="number" step="0.5" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Adjustment</span>
            <input v-model.number="editingBalance.adjustment_days" type="number" step="0.5" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Used</span>
            <input v-model.number="editingBalance.used_days" type="number" step="0.5" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
        </div>
        <footer class="px-6 py-4 border-t border-slate-200 flex justify-end gap-2">
          <button type="button" @click="editingBalance = null" class="text-sm px-3 py-2 rounded-lg hover:bg-slate-100">Cancel</button>
          <button type="button" @click="saveBalance" class="text-sm font-semibold px-4 py-2 rounded-lg bg-sycamore-600 hover:bg-sycamore-700 text-white">Save</button>
        </footer>
      </div>
    </div>
  </div>
</template>
