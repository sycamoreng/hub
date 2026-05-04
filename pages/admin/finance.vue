<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'
import { formatNaira } from '~/composables/usePayroll'

const supabase = useSupabase()
const toast = useToast()
const { user } = useAuth()

const items = ref<any[]>([])
const loading = ref(true)
const filter = ref<'pending' | 'approved' | 'declined' | 'cancelled' | 'all'>('pending')

async function load() {
  loading.value = true
  try {
    let q = supabase
      .from('finance_requests')
      .select('*, staff:staff_members(id, full_name, email, role)')
      .order('created_at', { ascending: false })
    if (filter.value !== 'all') q = q.eq('status', filter.value)
    const { data } = await q
    items.value = data ?? []
  } finally {
    loading.value = false
  }
}
load()
watch(filter, load)

const selected = ref<any | null>(null)
const decision = ref({ status: 'approved' as 'approved' | 'declined', notes: '' })
const saving = ref(false)

function openDecide(row: any, status: 'approved' | 'declined') {
  selected.value = row
  decision.value = { status, notes: '' }
}

async function decide() {
  if (!selected.value || !user.value) return
  saving.value = true
  try {
    const { error } = await supabase
      .from('finance_requests')
      .update({
        status: decision.value.status,
        decision_notes: decision.value.notes.trim(),
        decided_by: user.value.id,
        decided_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      })
      .eq('id', selected.value.id)
    if (error) throw error
    try {
      await supabase.from('notifications').insert({
        recipient_id: selected.value.requester_user_id,
        actor_id: user.value.id,
        type: 'finance_request',
        title: `Your ${selected.value.type} request was ${decision.value.status}`,
        body: decision.value.notes.trim() || `Amount: ${formatNaira(selected.value.amount)}`,
        link: '/finance'
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
  if (s === 'declined') return 'bg-rose-50 text-rose-700 border-rose-200'
  if (s === 'cancelled') return 'bg-slate-100 text-slate-600 border-slate-200'
  return 'bg-amber-50 text-amber-700 border-amber-200'
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
        <button v-for="f in ['pending','approved','declined','cancelled','all']" :key="f"
          type="button" @click="filter = (f as any)"
          class="text-xs font-semibold px-3 py-1.5 rounded-md capitalize"
          :class="filter === f ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
          {{ f }}
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
            <td class="px-5 py-3 capitalize">{{ r.type }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(r.amount) }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ r.repayment_months }}</td>
            <td class="px-5 py-3">
              <span class="text-xs font-semibold px-2 py-0.5 rounded border capitalize" :class="statusClass(r.status)">{{ r.status }}</span>
              <p v-if="r.reason" class="text-xs text-slate-500 mt-1 max-w-xs">{{ r.reason }}</p>
            </td>
            <td class="px-5 py-3 text-right space-x-2 whitespace-nowrap">
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

    <div v-if="selected" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="selected = null">
      <div class="bg-white rounded-2xl max-w-md w-full shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200">
          <h3 class="text-base font-semibold text-slate-900">{{ decision.status === 'approved' ? 'Approve' : 'Decline' }} request</h3>
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
            {{ saving ? 'Saving...' : (decision.status === 'approved' ? 'Approve' : 'Decline') }}
          </button>
        </footer>
      </div>
    </div>
  </div>
</template>
