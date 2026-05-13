<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'
import { formatNaira } from '~/composables/usePayroll'
import { emailUserNotification } from '~/composables/useNotifications'

const supabase = useSupabase()
const toast = useToast()
const { user } = useAuth()

const items = ref<any[]>([])
const loading = ref(true)
const filter = ref<'pending' | 'hc_approved' | 'approved' | 'rejected' | 'cancelled' | 'all'>('pending')

const myPerms = ref<{ hc: boolean; finance: boolean }>({ hc: false, finance: false })

async function loadPerms() {
  if (!user.value) return
  const { data } = await supabase
    .from('admin_users')
    .select('role, permissions, is_active')
    .eq('user_id', user.value.id)
    .eq('is_active', true)
    .maybeSingle()
  const role = (data as any)?.role ?? ''
  const perms = ((data as any)?.permissions as any) ?? {}
  const isSuper = role === 'super_admin'
  myPerms.value = {
    hc: isSuper || role === 'admin' || !!perms?.staff?.manage || !!perms?.leave?.manage,
    finance: isSuper || role === 'admin' || !!perms?.payroll?.manage || !!perms?.finance?.manage
  }
}

async function load() {
  loading.value = true
  try {
    let q = supabase
      .from('finance_requests')
      .select('*, staff:staff_members(id, full_name, email, role, monthly_net_salary)')
      .order('created_at', { ascending: false })
    if (filter.value !== 'all') q = q.eq('status', filter.value)
    const { data } = await q
    items.value = data ?? []
  } finally {
    loading.value = false
  }
}
loadPerms()
load()
watch(filter, load)

type Stage = 'hc' | 'finance'
const selected = ref<any | null>(null)
const decision = ref({ stage: 'hc' as Stage, status: 'approved' as 'approved' | 'rejected', notes: '' })
const saving = ref(false)

function openDecide(row: any, stage: Stage, status: 'approved' | 'rejected') {
  selected.value = row
  decision.value = { stage, status, notes: '' }
}

async function decide() {
  if (!selected.value || !user.value) return
  saving.value = true
  try {
    const now = new Date().toISOString()
    const update: any = { decision_notes: decision.value.notes.trim() }
    if (decision.value.stage === 'hc') {
      update.hc_status = decision.value.status
      update.hc_reviewer_id = user.value.id
      update.hc_decided_at = now
      update.hc_notes = decision.value.notes.trim()
    } else {
      update.finance_status = decision.value.status
      update.finance_reviewer_id = user.value.id
      update.finance_decided_at = now
      update.finance_notes = decision.value.notes.trim()
      update.decided_by = user.value.id
      update.decided_at = now
    }
    const { error } = await supabase.from('finance_requests').update(update).eq('id', selected.value.id)
    if (error) throw error
    const stageLabel = decision.value.stage === 'hc' ? 'HC review' : 'Finance review'
    const verb = decision.value.status === 'approved' ? 'approved' : 'rejected'
    try {
      await supabase.from('notifications').insert({
        recipient_id: selected.value.requester_user_id,
        actor_id: user.value.id,
        type: 'finance_request',
        title: `${stageLabel} ${verb}: ${selected.value.type}`,
        body: decision.value.notes.trim() || `Amount: ${formatNaira(selected.value.amount)}`,
        link: '/finance'
      })
      void emailUserNotification({
        user_id: selected.value.requester_user_id,
        title: `${stageLabel} ${verb}: ${selected.value.type}`,
        body_html: `<p>${decision.value.notes.trim() || `Amount: ${formatNaira(selected.value.amount)}`}</p>`,
        link_path: '/finance',
        link_label: 'View finance request',
        trigger: 'finance_decision'
      })
    } catch { /* non-fatal */ }
    toast.success('Decision saved')
    selected.value = null
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  } finally {
    saving.value = false
  }
}

function statusClass(s: string) {
  if (s === 'approved') return 'bg-emerald-50 text-emerald-700 border-emerald-200'
  if (s === 'hc_approved') return 'bg-sky-50 text-sky-700 border-sky-200'
  if (s === 'rejected') return 'bg-rose-50 text-rose-700 border-rose-200'
  if (s === 'cancelled') return 'bg-slate-100 text-slate-600 border-slate-200'
  return 'bg-amber-50 text-amber-700 border-amber-200'
}

function statusLabel(s: string) {
  if (s === 'pending') return 'Awaiting HC'
  if (s === 'hc_approved') return 'Awaiting Finance'
  if (s === 'approved') return 'Approved'
  if (s === 'rejected') return 'Rejected'
  if (s === 'cancelled') return 'Cancelled'
  return s
}
</script>

<template>
  <div class="max-w-6xl">
    <header class="mb-6 flex items-center justify-between flex-wrap gap-3">
      <div>
        <h1 class="text-2xl font-semibold text-slate-900">Finance requests</h1>
        <p class="text-sm text-slate-500 mt-1">Review salary advance and loan requests from staff.</p>
      </div>
      <div class="flex gap-1 bg-slate-100 rounded-lg p-1">
        <button v-for="f in (['pending','hc_approved','approved','rejected','cancelled','all'] as const)" :key="f"
          type="button" @click="filter = f"
          class="text-xs font-semibold px-3 py-1.5 rounded-md"
          :class="filter === f ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
          {{ statusLabel(f) }}
        </button>
      </div>
    </header>

    <section class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <div v-if="loading" class="p-5 text-sm text-slate-500">Loading...</div>
      <div v-else-if="items.length === 0" class="p-5 text-sm text-slate-500">No requests.</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Date</th>
            <th class="text-left px-5 py-2">Staff</th>
            <th class="text-left px-5 py-2">Type</th>
            <th class="text-right px-5 py-2">Amount</th>
            <th class="text-right px-5 py-2">Net salary</th>
            <th class="text-right px-5 py-2">Months</th>
            <th class="text-left px-5 py-2">Status</th>
            <th class="text-right px-5 py-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in items" :key="r.id" class="border-t border-slate-100 align-top">
            <td class="px-5 py-3 text-slate-700">{{ new Date(r.created_at).toLocaleDateString('en-GB') }}</td>
            <td class="px-5 py-3">
              <div class="font-medium text-slate-900">{{ r.staff?.full_name || '—' }}</div>
              <div class="text-xs text-slate-500">{{ r.staff?.role }}</div>
            </td>
            <td class="px-5 py-3 capitalize">
              {{ r.type }}<span v-if="r.type === 'loan' && r.loan_category" class="text-xs text-slate-500 block">{{ r.loan_category }} loan</span>
            </td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(r.amount) }}</td>
            <td class="px-5 py-3 text-right tabular-nums text-slate-600">{{ Number(r.monthly_net_salary || r.staff?.monthly_net_salary || 0) > 0 ? formatNaira(r.monthly_net_salary || r.staff?.monthly_net_salary) : '—' }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ r.repayment_months }}</td>
            <td class="px-5 py-3">
              <span class="text-xs font-semibold px-2 py-0.5 rounded border" :class="statusClass(r.status)">{{ statusLabel(r.status) }}</span>
              <p v-if="r.reason" class="text-xs text-slate-500 mt-1 max-w-xs">{{ r.reason }}</p>
              <p v-if="r.hc_notes" class="text-[11px] text-slate-500 mt-1 max-w-xs">HC: {{ r.hc_notes }}</p>
              <p v-if="r.finance_notes" class="text-[11px] text-slate-500 mt-1 max-w-xs">Finance: {{ r.finance_notes }}</p>
            </td>
            <td class="px-5 py-3 text-right space-x-2 whitespace-nowrap">
              <template v-if="r.status === 'pending' && r.hc_status !== 'approved' && myPerms.hc">
                <button type="button" @click="openDecide(r, 'hc', 'approved')" class="text-xs font-semibold px-2.5 py-1 rounded bg-emerald-600 text-white hover:bg-emerald-700">HC approve</button>
                <button type="button" @click="openDecide(r, 'hc', 'rejected')" class="text-xs font-semibold px-2.5 py-1 rounded bg-rose-600 text-white hover:bg-rose-700">HC reject</button>
              </template>
              <template v-else-if="(r.status === 'hc_approved' || (r.status === 'pending' && r.hc_status === 'approved')) && myPerms.finance">
                <button type="button" @click="openDecide(r, 'finance', 'approved')" class="text-xs font-semibold px-2.5 py-1 rounded bg-emerald-600 text-white hover:bg-emerald-700">Finance approve</button>
                <button type="button" @click="openDecide(r, 'finance', 'rejected')" class="text-xs font-semibold px-2.5 py-1 rounded bg-rose-600 text-white hover:bg-rose-700">Finance reject</button>
              </template>
              <span v-else-if="r.decision_notes" class="text-xs text-slate-500" :title="r.decision_notes">Note</span>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <div v-if="selected" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="selected = null">
      <div class="bg-white rounded-2xl max-w-md w-full shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200">
          <h3 class="text-base font-semibold text-slate-900">{{ decision.stage === 'hc' ? 'HC' : 'Finance' }} {{ decision.status === 'approved' ? 'approval' : 'rejection' }}</h3>
          <p class="text-xs text-slate-500 mt-1">{{ selected.staff?.full_name }} &middot; {{ formatNaira(selected.amount) }} &middot; {{ selected.repayment_months }} month(s)</p>
        </header>
        <div class="p-6 space-y-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600">Note to staff (optional)</span>
            <textarea v-model="decision.notes" rows="4" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"></textarea>
          </label>
        </div>
        <footer class="px-6 py-4 border-t border-slate-200 flex justify-end gap-2">
          <button type="button" @click="selected = null" class="text-sm px-3 py-2 rounded-lg hover:bg-slate-100">Cancel</button>
          <button type="button" @click="decide" :disabled="saving"
            class="text-sm font-semibold px-4 py-2 rounded-lg text-white"
            :class="decision.status === 'approved' ? 'bg-emerald-600 hover:bg-emerald-700' : 'bg-rose-600 hover:bg-rose-700'">
            {{ saving ? 'Saving...' : (decision.status === 'approved' ? 'Approve' : 'Reject') }}
          </button>
        </footer>
      </div>
    </div>
  </div>
</template>
