<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { formatNaira } from '~/composables/usePayroll'

const supabase = useSupabase()
const { user } = useAuth()
const toast = useToast()

const items = ref<any[]>([])
const loading = ref(true)
const staffId = ref<string | null>(null)
const monthlyNetSalary = ref<number>(0)

const form = ref({
  type: 'advance' as 'advance' | 'loan',
  loan_category: 'personal' as 'personal' | 'asset',
  amount: '' as string,
  repayment_months: 1,
  reason: ''
})
const saving = ref(false)

async function load() {
  loading.value = true
  try {
    if (!user.value) return
    const { data: staff } = await supabase
      .from('staff_members')
      .select('id, monthly_net_salary')
      .eq('auth_user_id', user.value.id)
      .maybeSingle()
    staffId.value = (staff as any)?.id ?? null
    monthlyNetSalary.value = Number((staff as any)?.monthly_net_salary ?? 0)
    const { data } = await supabase
      .from('finance_requests')
      .select('*')
      .eq('requester_user_id', user.value.id)
      .order('created_at', { ascending: false })
    items.value = data ?? []
  } finally {
    loading.value = false
  }
}
load()

watch(() => form.value.type, (t) => {
  if (t === 'advance') form.value.repayment_months = 1
})

function statusLabel(r: any): string {
  if (r.status === 'pending') {
    if (r.hc_status === 'approved') return 'Awaiting Finance'
    return 'Awaiting HC'
  }
  if (r.status === 'hc_approved') return 'Awaiting Finance'
  if (r.status === 'approved') return 'Approved'
  if (r.status === 'declined') return 'Declined'
  if (r.status === 'cancelled') return 'Cancelled'
  return r.status
}

async function submit() {
  if (!user.value) return
  const amt = Number(form.value.amount)
  if (!amt || amt <= 0) { toast.error('Enter a valid amount'); return }
  if (!form.value.reason.trim()) { toast.error('Please add a reason'); return }
  saving.value = true
  try {
    const payload: any = {
      staff_id: staffId.value,
      requester_user_id: user.value.id,
      type: form.value.type,
      amount: amt,
      repayment_months: form.value.type === 'advance' ? 1 : Math.max(1, Math.min(36, Number(form.value.repayment_months) || 1)),
      reason: form.value.reason.trim(),
      status: 'pending',
      monthly_net_salary: monthlyNetSalary.value,
      loan_category: form.value.type === 'loan' ? form.value.loan_category : ''
    }
    const { error } = await supabase.from('finance_requests').insert(payload)
    if (error) throw error
    form.value = { type: 'advance', loan_category: 'personal', amount: '', repayment_months: 1, reason: '' }
    toast.success('Request submitted')
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to submit')
  } finally {
    saving.value = false
  }
}

async function cancel(row: any) {
  const ok = await toast.confirm({ title: 'Cancel request', message: 'Cancel this pending request?', confirmLabel: 'Cancel request', variant: 'danger' })
  if (!ok) return
  try {
    const { error } = await supabase
      .from('finance_requests')
      .update({ status: 'cancelled', updated_at: new Date().toISOString() })
      .eq('id', row.id)
    if (error) throw error
    toast.success('Cancelled')
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to cancel')
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
  <div class="max-w-4xl mx-auto">
    <header class="mb-6">
      <h1 class="text-2xl font-semibold text-slate-900">Salary advance &amp; loans</h1>
      <p class="text-sm text-slate-500 mt-1">Request a salary advance or a loan from the organization.</p>
    </header>

    <section class="bg-white border border-slate-200 rounded-xl p-5 mb-8">
      <h2 class="text-sm font-semibold text-slate-900 mb-4">New request</h2>
      <p class="text-xs text-slate-500 mb-3">
        Recorded monthly net salary:
        <span class="font-semibold text-slate-700">{{ monthlyNetSalary > 0 ? formatNaira(monthlyNetSalary) : 'not set — please ask HC to update' }}</span>
      </p>
      <form class="grid sm:grid-cols-2 gap-4" @submit.prevent="submit">
        <label class="block">
          <span class="text-xs font-medium text-slate-600">Type</span>
          <select v-model="form.type" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm">
            <option value="advance">Salary advance</option>
            <option value="loan">Loan</option>
          </select>
        </label>
        <label v-if="form.type === 'loan'" class="block">
          <span class="text-xs font-medium text-slate-600">Loan category</span>
          <select v-model="form.loan_category" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm">
            <option value="personal">Personal loan</option>
            <option value="asset">Asset loan</option>
          </select>
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600">Amount (NGN)</span>
          <input v-model="form.amount" type="number" min="1" step="1000" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" />
        </label>
        <label v-if="form.type === 'loan'" class="block">
          <span class="text-xs font-medium text-slate-600">Repayment months</span>
          <input v-model.number="form.repayment_months" type="number" min="1" max="36" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" />
        </label>
        <label class="block sm:col-span-2">
          <span class="text-xs font-medium text-slate-600">Reason</span>
          <textarea v-model="form.reason" rows="3" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" placeholder="Briefly describe the purpose of this request"></textarea>
        </label>
        <div class="sm:col-span-2 flex justify-end">
          <button type="submit" :disabled="saving" class="bg-sycamore-600 hover:bg-sycamore-700 disabled:opacity-60 text-white text-sm font-semibold px-4 py-2 rounded-lg">
            {{ saving ? 'Submitting...' : 'Submit request' }}
          </button>
        </div>
      </form>
    </section>

    <section class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <header class="px-5 py-4 border-b border-slate-200">
        <h2 class="text-sm font-semibold text-slate-900">My requests</h2>
      </header>
      <div v-if="loading" class="p-5 text-sm text-slate-500">Loading...</div>
      <div v-else-if="items.length === 0" class="p-5 text-sm text-slate-500">No requests yet.</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Date</th>
            <th class="text-left px-5 py-2">Type</th>
            <th class="text-right px-5 py-2">Amount</th>
            <th class="text-right px-5 py-2">Months</th>
            <th class="text-left px-5 py-2">Status</th>
            <th class="text-right px-5 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in items" :key="r.id" class="border-t border-slate-100">
            <td class="px-5 py-3 text-slate-700">{{ new Date(r.created_at).toLocaleDateString('en-GB') }}</td>
            <td class="px-5 py-3 capitalize">
              {{ r.type }}<span v-if="r.type === 'loan' && r.loan_category" class="text-xs text-slate-500 ml-1">· {{ r.loan_category }}</span>
            </td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(r.amount) }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ r.repayment_months }}</td>
            <td class="px-5 py-3">
              <span class="text-xs font-semibold px-2 py-0.5 rounded border" :class="statusClass(r.status)">{{ statusLabel(r) }}</span>
            </td>
            <td class="px-5 py-3 text-right">
              <button v-if="r.status === 'pending'" type="button" @click="cancel(r)" class="text-rose-600 font-medium text-xs">Cancel</button>
              <span v-else-if="r.decision_notes" class="text-xs text-slate-500" :title="r.decision_notes">Has note</span>
            </td>
          </tr>
        </tbody>
      </table>
    </section>
  </div>
</template>
