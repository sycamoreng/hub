<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { useLeave, computeWorkingDays, ymd, type LeaveType, type PublicHoliday } from '~/composables/useLeave'

definePageMeta({ middleware: ['auth'] })

const supabase = useSupabase()
const { user } = useAuth()
const toast = useToast()
const { loadLeaveTypes, loadPublicHolidays, loadStaffBalances, ensureBalanceRows } = useLeave()

const staffId = ref<string | null>(null)
const staffName = ref<string>('')
const leaveTypes = ref<LeaveType[]>([])
const holidays = ref<PublicHoliday[]>([])
const balances = ref<any[]>([])
const requests = ref<any[]>([])
const reliefForMe = ref<any[]>([])
const colleagues = ref<{ id: string; full_name: string; role: string }[]>([])
const loading = ref(true)
const today = new Date()
const year = ref(today.getFullYear())

const form = ref({
  leave_type_id: '',
  start_date: ymd(today),
  end_date: ymd(today),
  half_day_start: false,
  half_day_end: false,
  reason: '',
  notify_colleagues: true,
  relief_officer_id: '',
  handover_notes: ''
})
const saving = ref(false)

const computedDays = computed(() => {
  if (!form.value.leave_type_id || !form.value.start_date || !form.value.end_date) return 0
  return computeWorkingDays(form.value.start_date, form.value.end_date, holidays.value, form.value.half_day_start, form.value.half_day_end)
})

async function load() {
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
    const [lt, ph] = await Promise.all([loadLeaveTypes(), loadPublicHolidays()])
    leaveTypes.value = lt
    holidays.value = ph
    await ensureBalanceRows(staffId.value!, year.value, lt)
    balances.value = await loadStaffBalances(staffId.value!, year.value)
    const { data: reqs } = await supabase
      .from('leave_requests')
      .select('*, leave_type:leave_types(name,color), relief:staff_members!leave_requests_relief_officer_id_fkey(id, full_name)')
      .eq('staff_id', staffId.value)
      .order('created_at', { ascending: false })
    requests.value = reqs ?? []

    const { data: reliefRows } = await supabase
      .from('leave_requests')
      .select('*, leave_type:leave_types(name,color), staff:staff_members!leave_requests_staff_id_fkey(id, full_name, role)')
      .eq('relief_officer_id', staffId.value)
      .is('relief_accepted_at', null)
      .is('relief_declined_at', null)
      .in('status', ['pending','approved'])
      .order('created_at', { ascending: false })
    reliefForMe.value = reliefRows ?? []

    const { data: colls } = await supabase
      .from('staff_members')
      .select('id, full_name, role')
      .eq('is_active', true)
      .neq('id', staffId.value)
      .order('full_name')
    colleagues.value = (colls ?? []) as any

    if (!form.value.leave_type_id && lt.length) form.value.leave_type_id = lt[0].id
  } finally {
    loading.value = false
  }
}
load()

function remainingFor(b: any): number {
  return Number(b.allocated_days) + Number(b.adjustment_days) - Number(b.used_days)
}

async function submit() {
  if (!staffId.value || !user.value) return
  if (!form.value.leave_type_id) { toast.error('Select a leave type'); return }
  if (form.value.end_date < form.value.start_date) { toast.error('End date must be after start'); return }
  const days = computedDays.value
  if (days <= 0) { toast.error('Select at least one working day'); return }
  saving.value = true
  try {
    const payload = {
      staff_id: staffId.value,
      requester_user_id: user.value.id,
      leave_type_id: form.value.leave_type_id,
      start_date: form.value.start_date,
      end_date: form.value.end_date,
      half_day_start: form.value.half_day_start,
      half_day_end: form.value.half_day_end,
      working_days: days,
      reason: form.value.reason.trim(),
      notify_colleagues: form.value.notify_colleagues,
      relief_officer_id: form.value.relief_officer_id || null,
      handover_notes: form.value.handover_notes.trim(),
      status: 'pending'
    }
    const { data: inserted, error } = await supabase
      .from('leave_requests')
      .insert(payload)
      .select('id')
      .maybeSingle()
    if (error) throw error

    try {
      const { data: subj } = await supabase
        .from('staff_members')
        .select('manager_id, full_name')
        .eq('id', staffId.value)
        .maybeSingle()
      const managerId = (subj as any)?.manager_id
      if (managerId) {
        const { data: mgr } = await supabase
          .from('staff_members')
          .select('auth_user_id')
          .eq('id', managerId)
          .maybeSingle()
        if ((mgr as any)?.auth_user_id) {
          await supabase.from('notifications').insert({
            recipient_id: (mgr as any).auth_user_id,
            actor_id: user.value.id,
            type: 'leave_request',
            title: `Leave request from ${staffName.value}`,
            body: `${days} day(s) of leave from ${form.value.start_date} to ${form.value.end_date}`,
            link: '/admin/leave'
          })
        }
      }
    } catch { /* non-fatal */ }

    if (payload.relief_officer_id) {
      try {
        const { data: relief } = await supabase
          .from('staff_members')
          .select('auth_user_id, full_name')
          .eq('id', payload.relief_officer_id)
          .maybeSingle()
        if ((relief as any)?.auth_user_id) {
          await supabase.from('notifications').insert({
            recipient_id: (relief as any).auth_user_id,
            actor_id: user.value.id,
            type: 'leave_relief_request',
            title: `${staffName.value} nominated you as relief officer`,
            body: `${payload.start_date} - ${payload.end_date} (${days} day(s))`,
            link: '/leave'
          })
        }
      } catch { /* non-fatal */ }
    }

    toast.success('Leave request submitted')
    form.value = {
      leave_type_id: leaveTypes.value[0]?.id ?? '',
      start_date: ymd(today),
      end_date: ymd(today),
      half_day_start: false,
      half_day_end: false,
      reason: '',
      notify_colleagues: true,
      relief_officer_id: '',
      handover_notes: ''
    }
    await load()
    void inserted
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to submit')
  } finally {
    saving.value = false
  }
}

async function cancel(row: any) {
  const ok = await toast.confirm({ title: 'Cancel request', message: 'Cancel this request?', variant: 'danger', confirmLabel: 'Cancel' })
  if (!ok) return
  try {
    const { error } = await supabase
      .from('leave_requests')
      .update({ status: 'cancelled', updated_at: new Date().toISOString() })
      .eq('id', row.id)
    if (error) throw error
    toast.success('Cancelled')
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  }
}

const reliefModal = ref<{ row: any; action: 'accept' | 'decline' } | null>(null)
const reliefNotes = ref('')
const savingRelief = ref(false)

function openReliefResponse(row: any, action: 'accept' | 'decline') {
  reliefModal.value = { row, action }
  reliefNotes.value = ''
}

async function submitReliefResponse() {
  if (!reliefModal.value || !user.value) return
  savingRelief.value = true
  try {
    const { row, action } = reliefModal.value
    const patch: any = { relief_response_notes: reliefNotes.value.trim(), updated_at: new Date().toISOString() }
    if (action === 'accept') { patch.relief_accepted_at = new Date().toISOString(); patch.relief_declined_at = null }
    else { patch.relief_declined_at = new Date().toISOString(); patch.relief_accepted_at = null }
    const { error } = await supabase.from('leave_requests').update(patch).eq('id', row.id)
    if (error) throw error
    try {
      await supabase.from('notifications').insert({
        recipient_id: row.requester_user_id,
        actor_id: user.value.id,
        type: 'leave_relief_response',
        title: `${staffName.value} ${action === 'accept' ? 'accepted' : 'declined'} relief cover`,
        body: reliefNotes.value.trim() || `${row.start_date} - ${row.end_date}`,
        link: '/leave'
      })
    } catch { /* non-fatal */ }
    toast.success('Response recorded')
    reliefModal.value = null
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  } finally {
    savingRelief.value = false
  }
}

function reliefStatus(r: any): 'accepted' | 'declined' | 'pending' | 'none' {
  if (!r.relief_officer_id) return 'none'
  if (r.relief_accepted_at) return 'accepted'
  if (r.relief_declined_at) return 'declined'
  return 'pending'
}

function reliefBadgeClass(s: string) {
  if (s === 'accepted') return 'bg-emerald-50 text-emerald-700 border-emerald-200'
  if (s === 'declined') return 'bg-rose-50 text-rose-700 border-rose-200'
  if (s === 'pending') return 'bg-amber-50 text-amber-700 border-amber-200'
  return 'bg-slate-100 text-slate-600 border-slate-200'
}

const expanded = ref<Record<string, boolean>>({})
function toggleExpand(id: string) { expanded.value[id] = !expanded.value[id] }

function statusClass(s: string) {
  if (s === 'approved') return 'bg-emerald-50 text-emerald-700 border-emerald-200'
  if (s === 'declined') return 'bg-rose-50 text-rose-700 border-rose-200'
  if (s === 'cancelled') return 'bg-slate-100 text-slate-600 border-slate-200'
  return 'bg-amber-50 text-amber-700 border-amber-200'
}

const upcomingHolidays = computed(() => {
  const todayISO = ymd(today)
  return holidays.value
    .map(h => {
      if (h.recurring_yearly) {
        const md = h.day.slice(5)
        const thisYr = `${year.value}-${md}`
        const nextYr = `${year.value + 1}-${md}`
        return { ...h, day: thisYr < todayISO ? nextYr : thisYr }
      }
      return h
    })
    .filter(h => h.day >= todayISO)
    .sort((a, b) => a.day.localeCompare(b.day))
    .slice(0, 5)
})
</script>

<template>
  <div class="max-w-6xl mx-auto">
    <header class="mb-6">
      <h1 class="text-2xl font-semibold text-slate-900">My Leave</h1>
      <p class="text-sm text-slate-500 mt-1">Plan time off, submit requests, and track your balances.</p>
    </header>

    <section v-if="!loading && balances.length" class="grid grid-cols-2 md:grid-cols-4 gap-3 mb-8">
      <div v-for="b in balances" :key="b.id" class="bg-white border border-slate-200 rounded-xl p-4">
        <div class="flex items-center gap-2 mb-1">
          <span class="w-2.5 h-2.5 rounded-full" :style="{ backgroundColor: b.leave_type?.color }"></span>
          <span class="text-xs font-semibold text-slate-600">{{ b.leave_type?.name }}</span>
        </div>
        <div class="text-xl font-bold text-slate-900 tabular-nums">{{ remainingFor(b) }}<span class="text-xs font-normal text-slate-500"> / {{ (Number(b.allocated_days) + Number(b.adjustment_days)).toFixed(0) }} days</span></div>
        <div class="text-xs text-slate-500 mt-0.5">{{ Number(b.used_days).toFixed(1) }} used</div>
      </div>
    </section>

    <div class="grid lg:grid-cols-3 gap-6">
      <section class="lg:col-span-2 bg-white border border-slate-200 rounded-xl p-5">
        <h2 class="text-sm font-semibold text-slate-900 mb-4">Request leave</h2>
        <form class="grid sm:grid-cols-2 gap-4" @submit.prevent="submit">
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600">Leave type</span>
            <select v-model="form.leave_type_id" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm">
              <option v-for="t in leaveTypes" :key="t.id" :value="t.id">{{ t.name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600">Start date</span>
            <input v-model="form.start_date" type="date" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600">End date</span>
            <input v-model="form.end_date" type="date" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" />
          </label>
          <label class="inline-flex items-center gap-2 text-sm">
            <input v-model="form.half_day_start" type="checkbox" class="w-4 h-4 rounded border-slate-300 text-sycamore-600" />
            Half day on start
          </label>
          <label class="inline-flex items-center gap-2 text-sm">
            <input v-model="form.half_day_end" type="checkbox" class="w-4 h-4 rounded border-slate-300 text-sycamore-600" />
            Half day on end
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600">Reason (optional)</span>
            <textarea v-model="form.reason" rows="3" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"></textarea>
          </label>

          <div class="sm:col-span-2 border-t border-slate-100 pt-4">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-3">Handover &amp; cover</h3>
            <div class="grid sm:grid-cols-2 gap-4">
              <label class="block">
                <span class="text-xs font-medium text-slate-600">Relief officer</span>
                <select v-model="form.relief_officer_id" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm">
                  <option value="">— No relief nominated —</option>
                  <option v-for="c in colleagues" :key="c.id" :value="c.id">{{ c.full_name }}<span v-if="c.role"> &middot; {{ c.role }}</span></option>
                </select>
                <span class="text-xs text-slate-500 mt-1 block">They will be notified and asked to accept cover.</span>
              </label>
              <div class="block"></div>
              <label class="block sm:col-span-2">
                <span class="text-xs font-medium text-slate-600">Handover notes</span>
                <textarea v-model="form.handover_notes" rows="4" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" placeholder="Outstanding tasks, deadlines, key contacts, where files live, recurring check-ins, etc."></textarea>
              </label>
            </div>
          </div>

          <label class="inline-flex items-center gap-2 text-sm sm:col-span-2">
            <input v-model="form.notify_colleagues" type="checkbox" class="w-4 h-4 rounded border-slate-300 text-sycamore-600" />
            Notify my team when approved
          </label>
          <div class="sm:col-span-2 flex items-center justify-between pt-2 border-t border-slate-100">
            <div class="text-sm text-slate-600">
              <span class="font-semibold text-slate-900 tabular-nums">{{ computedDays }}</span> working day(s) &middot; weekends &amp; holidays excluded
            </div>
            <button type="submit" :disabled="saving" class="bg-sycamore-600 hover:bg-sycamore-700 disabled:opacity-60 text-white text-sm font-semibold px-4 py-2 rounded-lg">
              {{ saving ? 'Submitting...' : 'Submit request' }}
            </button>
          </div>
        </form>
      </section>

      <aside class="bg-white border border-slate-200 rounded-xl p-5">
        <h2 class="text-sm font-semibold text-slate-900 mb-3">Upcoming holidays</h2>
        <ul v-if="upcomingHolidays.length" class="space-y-2">
          <li v-for="h in upcomingHolidays" :key="h.id" class="flex items-start justify-between gap-3">
            <div>
              <div class="text-sm font-medium text-slate-900">{{ h.name }}</div>
              <div class="text-xs text-slate-500">{{ new Date(h.day + 'T00:00:00').toLocaleDateString('en-GB', { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric' }) }}</div>
            </div>
            <span class="text-xs font-semibold text-emerald-700 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded">Off</span>
          </li>
        </ul>
        <p v-else class="text-sm text-slate-500">No upcoming holidays.</p>
      </aside>
    </div>

    <section v-if="reliefForMe.length" class="bg-white border border-amber-200 rounded-xl overflow-hidden mt-8">
      <header class="px-5 py-4 border-b border-amber-100 bg-amber-50/60 flex items-center justify-between">
        <div>
          <h2 class="text-sm font-semibold text-slate-900">Cover requested for you</h2>
          <p class="text-xs text-slate-500 mt-0.5">Colleagues have nominated you as their relief officer. Accept or decline so their leave can be planned.</p>
        </div>
        <span class="text-xs font-semibold px-2 py-0.5 rounded border bg-amber-100 text-amber-800 border-amber-200">{{ reliefForMe.length }} pending</span>
      </header>
      <ul class="divide-y divide-slate-100">
        <li v-for="r in reliefForMe" :key="r.id" class="p-5">
          <div class="flex items-start justify-between gap-4 flex-wrap">
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="font-medium text-slate-900">{{ r.staff?.full_name }}</span>
                <span class="text-xs text-slate-500">&middot; {{ r.staff?.role }}</span>
                <span class="inline-flex items-center gap-2 text-xs font-semibold text-slate-700 bg-slate-100 border border-slate-200 px-2 py-0.5 rounded">
                  <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: r.leave_type?.color }"></span>
                  {{ r.leave_type?.name }}
                </span>
              </div>
              <div class="text-sm text-slate-700 mt-1">
                {{ r.start_date }} &rarr; {{ r.end_date }} &middot; <span class="tabular-nums">{{ r.working_days }}</span> day(s)
              </div>
              <p v-if="r.handover_notes" class="text-sm text-slate-600 mt-2 whitespace-pre-wrap"><span class="text-xs font-semibold text-slate-500 uppercase tracking-wide">Handover</span><br>{{ r.handover_notes }}</p>
              <p v-if="r.reason" class="text-xs text-slate-500 mt-2">Reason: {{ r.reason }}</p>
            </div>
            <div class="flex gap-2 shrink-0">
              <button type="button" @click="openReliefResponse(r, 'accept')" class="text-xs font-semibold px-3 py-1.5 rounded bg-emerald-600 hover:bg-emerald-700 text-white">Accept cover</button>
              <button type="button" @click="openReliefResponse(r, 'decline')" class="text-xs font-semibold px-3 py-1.5 rounded bg-white border border-slate-300 hover:bg-slate-50 text-slate-700">Decline</button>
            </div>
          </div>
        </li>
      </ul>
    </section>

    <section class="bg-white border border-slate-200 rounded-xl overflow-hidden mt-8">
      <header class="px-5 py-4 border-b border-slate-200">
        <h2 class="text-sm font-semibold text-slate-900">My requests</h2>
      </header>
      <div v-if="loading" class="p-5 text-sm text-slate-500">Loading...</div>
      <div v-else-if="requests.length === 0" class="p-5 text-sm text-slate-500">No requests yet.</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Type</th>
            <th class="text-left px-5 py-2">From</th>
            <th class="text-left px-5 py-2">To</th>
            <th class="text-right px-5 py-2">Days</th>
            <th class="text-left px-5 py-2">Status</th>
            <th class="text-left px-5 py-2">Relief</th>
            <th class="text-right px-5 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <template v-for="r in requests" :key="r.id">
            <tr class="border-t border-slate-100">
              <td class="px-5 py-3">
                <span class="inline-flex items-center gap-2">
                  <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: r.leave_type?.color }"></span>
                  {{ r.leave_type?.name }}
                </span>
              </td>
              <td class="px-5 py-3">{{ r.start_date }}</td>
              <td class="px-5 py-3">{{ r.end_date }}</td>
              <td class="px-5 py-3 text-right tabular-nums">{{ r.working_days }}</td>
              <td class="px-5 py-3"><span class="text-xs font-semibold px-2 py-0.5 rounded border capitalize" :class="statusClass(r.status)">{{ r.status }}</span></td>
              <td class="px-5 py-3">
                <div v-if="r.relief_officer_id" class="flex flex-col gap-0.5">
                  <span class="text-xs text-slate-700">{{ r.relief?.full_name }}</span>
                  <span class="text-xs font-semibold px-2 py-0.5 rounded border self-start capitalize" :class="reliefBadgeClass(reliefStatus(r))">{{ reliefStatus(r) }}</span>
                </div>
                <span v-else class="text-xs text-slate-400">—</span>
              </td>
              <td class="px-5 py-3 text-right whitespace-nowrap space-x-3">
                <button v-if="r.handover_notes || r.relief_officer_id" type="button" @click="toggleExpand(r.id)" class="text-xs font-semibold text-sycamore-700">{{ expanded[r.id] ? 'Hide' : 'Details' }}</button>
                <button v-if="r.status === 'pending'" type="button" @click="cancel(r)" class="text-rose-600 font-medium text-xs">Cancel</button>
              </td>
            </tr>
            <tr v-if="expanded[r.id]" class="bg-slate-50">
              <td colspan="7" class="px-5 py-4 text-sm text-slate-700 space-y-2">
                <div v-if="r.handover_notes">
                  <div class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-1">Handover notes</div>
                  <p class="whitespace-pre-wrap">{{ r.handover_notes }}</p>
                </div>
                <div v-if="r.relief_response_notes">
                  <div class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-1">Relief response</div>
                  <p class="whitespace-pre-wrap">{{ r.relief_response_notes }}</p>
                </div>
                <div v-if="r.decision_notes">
                  <div class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-1">Manager note</div>
                  <p class="whitespace-pre-wrap">{{ r.decision_notes }}</p>
                </div>
              </td>
            </tr>
          </template>
        </tbody>
      </table>
    </section>

    <div v-if="reliefModal" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="reliefModal = null">
      <div class="bg-white rounded-2xl max-w-md w-full shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200">
          <h3 class="text-base font-semibold text-slate-900">{{ reliefModal.action === 'accept' ? 'Accept cover' : 'Decline cover' }}</h3>
          <p class="text-xs text-slate-500 mt-1">{{ reliefModal.row.staff?.full_name }} &middot; {{ reliefModal.row.start_date }} &rarr; {{ reliefModal.row.end_date }}</p>
        </header>
        <div class="p-6">
          <label class="block">
            <span class="text-xs font-medium text-slate-600">Note (optional)</span>
            <textarea v-model="reliefNotes" rows="4" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" :placeholder="reliefModal.action === 'accept' ? 'Any caveats, e.g. busy dates, boundaries...' : 'Reason for declining'"></textarea>
          </label>
        </div>
        <footer class="px-6 py-4 border-t border-slate-200 flex justify-end gap-2">
          <button type="button" @click="reliefModal = null" class="text-sm px-3 py-2 rounded-lg hover:bg-slate-100">Cancel</button>
          <button type="button" @click="submitReliefResponse" :disabled="savingRelief"
            class="text-sm font-semibold px-4 py-2 rounded-lg text-white"
            :class="reliefModal.action === 'accept' ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-rose-600 hover:bg-rose-700'">
            {{ savingRelief ? 'Saving...' : (reliefModal.action === 'accept' ? 'Accept cover' : 'Decline') }}
          </button>
        </footer>
      </div>
    </div>
  </div>
</template>
