<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { computePayroll, formatNaira, MONTH_NAMES } from '~/composables/usePayroll'

const supabase = useSupabase()
const toast = useToast()
const { log: auditLog } = useAuditLog()

const runs = ref<any[]>([])
const loading = ref(false)
const creating = ref(false)
const selectedRun = ref<any | null>(null)
const selectedItems = ref<any[]>([])
const loadingItems = ref(false)

const now = new Date()
const newRun = ref({ period_year: now.getFullYear(), period_month: now.getMonth() + 1, label: '', pay_date: '' })

async function loadRuns() {
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('payroll_runs')
      .select('*')
      .order('period_year', { ascending: false })
      .order('period_month', { ascending: false })
    if (error) throw error
    runs.value = data ?? []
  } finally { loading.value = false }
}

async function createRun() {
  creating.value = true
  try {
    const { data: settings } = await supabase.from('payroll_settings').select('*').eq('id', 1).maybeSingle()
    if (!settings) throw new Error('Payroll settings not found')
    const { data: employees, error: empErr } = await supabase
      .from('payroll_employees').select('*').eq('is_active', true)
    if (empErr) throw empErr
    if (!employees || employees.length === 0) throw new Error('No active payroll employees. Add employees first.')

    const { data: run, error: runErr } = await supabase.from('payroll_runs').insert({
      period_year: newRun.value.period_year,
      period_month: newRun.value.period_month,
      label: newRun.value.label || `${MONTH_NAMES[newRun.value.period_month - 1]} ${newRun.value.period_year}`,
      pay_date: newRun.value.pay_date || null,
      status: 'draft'
    }).select().maybeSingle()
    if (runErr) throw runErr

    let totals = { gross: 0, paye: 0, pension_employee: 0, pension_employer: 0, nhf: 0, net: 0 }
    const items = employees.map((emp: any) => {
      const breakdown = computePayroll({
        basic: Number(emp.pay_basic || 0),
        housing: Number(emp.pay_housing || 0),
        transport: Number(emp.pay_transport || 0),
        utility: Number(emp.pay_utility || 0),
        meal: Number(emp.pay_meal || 0),
        leave_allowance: Number(emp.pay_leave || 0),
        other_earnings: Number(emp.pay_other || 0),
        bonus: 0,
        nhf_enabled: Boolean(emp.nhf_enabled)
      }, {
        pension_employee_rate: Number(settings.pension_employee_rate),
        pension_employer_rate: Number(settings.pension_employer_rate),
        nhf_rate: Number(settings.nhf_rate),
        nhis_rate: Number(settings.nhis_rate),
        nhis_enabled: Boolean(settings.nhis_enabled)
      })
      totals.gross += breakdown.gross
      totals.paye += breakdown.paye
      totals.pension_employee += breakdown.pension_employee
      totals.pension_employer += breakdown.pension_employer
      totals.nhf += breakdown.nhf
      totals.net += breakdown.net
      return {
        run_id: run!.id,
        employee_id: emp.id,
        staff_id: emp.staff_id,
        full_name: emp.full_name,
        email: emp.email,
        grade: emp.grade || '',
        basic: emp.pay_basic || 0,
        housing: emp.pay_housing || 0,
        transport: emp.pay_transport || 0,
        utility: emp.pay_utility || 0,
        meal: emp.pay_meal || 0,
        leave_allowance: emp.pay_leave || 0,
        other_earnings: emp.pay_other || 0,
        bonus: 0,
        gross: breakdown.gross,
        pension_employee: breakdown.pension_employee,
        pension_employer: breakdown.pension_employer,
        nhf: breakdown.nhf,
        nhis: breakdown.nhis,
        cra: breakdown.cra,
        taxable_income: breakdown.taxable_income,
        paye: breakdown.paye,
        other_deductions: 0,
        net: breakdown.net
      }
    })

    const { error: itemsErr } = await supabase.from('payroll_items').insert(items)
    if (itemsErr) throw itemsErr

    await supabase.from('payroll_runs').update({
      total_gross: totals.gross,
      total_paye: totals.paye,
      total_pension_employee: totals.pension_employee,
      total_pension_employer: totals.pension_employer,
      total_nhf: totals.nhf,
      total_net: totals.net,
      updated_at: new Date().toISOString()
    }).eq('id', run!.id)

    auditLog({ action: 'create', target_type: 'payroll_run', target_id: run!.id, target_label: newRun.value.label || `${MONTH_NAMES[newRun.value.period_month - 1]} ${newRun.value.period_year}` })
    toast.success(`Created run for ${MONTH_NAMES[newRun.value.period_month - 1]} with ${employees.length} employees`)
    newRun.value.label = ''
    newRun.value.pay_date = ''
    await loadRuns()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to create run')
  } finally { creating.value = false }
}

async function openRun(run: any) {
  selectedRun.value = run
  loadingItems.value = true
  try {
    const { data } = await supabase
      .from('payroll_items').select('*').eq('run_id', run.id)
      .order('full_name')
    selectedItems.value = data ?? []
  } finally { loadingItems.value = false }
}

async function approve(run: any) {
  const ok = await toast.confirm({ title: 'Approve run', message: `Approve ${run.label}? Locked after approval.`, confirmLabel: 'Approve' })
  if (!ok) return
  try {
    const { data: user } = await supabase.auth.getUser()
    const { error } = await supabase.from('payroll_runs').update({
      status: 'approved', approved_at: new Date().toISOString(), approved_by: user.user?.id
    }).eq('id', run.id)
    if (error) throw error
    auditLog({ action: 'approve', target_type: 'payroll_run', target_id: run.id, target_label: run.label })
    toast.success('Approved')
    await loadRuns()
    if (selectedRun.value?.id === run.id) selectedRun.value = { ...run, status: 'approved' }
  } catch (e: any) { toast.error(e.message ?? 'Failed to approve') }
}

async function markPaid(run: any) {
  try {
    const { error } = await supabase.from('payroll_runs').update({ status: 'paid' }).eq('id', run.id)
    if (error) throw error
    auditLog({ action: 'mark_paid', target_type: 'payroll_run', target_id: run.id, target_label: run.label })
    toast.success('Marked as paid')
    await loadRuns()
    if (selectedRun.value?.id === run.id) selectedRun.value = { ...run, status: 'paid' }
  } catch (e: any) { toast.error(e.message ?? 'Failed to update') }
}

async function deleteRun(run: any) {
  const ok = await toast.confirm({ title: 'Delete run', message: `Delete ${run.label} and its payslips? Cannot be undone.`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try {
    const { error } = await supabase.from('payroll_runs').delete().eq('id', run.id)
    if (error) throw error
    auditLog({ action: 'delete', target_type: 'payroll_run', target_id: run.id, target_label: run.label })
    toast.success('Deleted')
    if (selectedRun.value?.id === run.id) selectedRun.value = null
    await loadRuns()
  } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}

function exportCsv() {
  if (!selectedRun.value) return
  const rows = selectedItems.value
  const header = ['Name','Email','Grade','Gross','Pension (Employee)','NHF','PAYE','Net','Bank','Account']
  const csv = [header.join(',')]
  for (const r of rows) {
    csv.push([
      JSON.stringify(r.full_name), JSON.stringify(r.email), JSON.stringify(r.grade || ''),
      r.gross, r.pension_employee, r.nhf, r.paye, r.net, '', ''
    ].join(','))
  }
  const blob = new Blob([csv.join('\n')], { type: 'text/csv' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `payroll-${selectedRun.value.period_year}-${String(selectedRun.value.period_month).padStart(2,'0')}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

loadRuns()

const monthOptions = MONTH_NAMES.map((m, i) => ({ value: i + 1, label: m }))
const yearOptions = computed(() => {
  const y = now.getFullYear()
  return [y - 1, y, y + 1]
})

function statusClass(s: string) {
  if (s === 'paid') return 'bg-emerald-50 text-emerald-700 border-emerald-200'
  if (s === 'approved') return 'bg-sky-50 text-sky-700 border-sky-200'
  return 'bg-slate-50 text-slate-600 border-slate-200'
}
</script>

<template>
  <div class="space-y-6">
    <section class="bg-white border border-slate-200 rounded-xl p-5">
      <h3 class="text-sm font-semibold text-slate-900 mb-4">Create new run</h3>
      <div class="grid grid-cols-1 sm:grid-cols-4 gap-3">
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">Month</span>
          <select v-model.number="newRun.period_month" class="w-full border border-slate-300 rounded-md px-3 py-2">
            <option v-for="m in monthOptions" :key="m.value" :value="m.value">{{ m.label }}</option>
          </select>
        </label>
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">Year</span>
          <select v-model.number="newRun.period_year" class="w-full border border-slate-300 rounded-md px-3 py-2">
            <option v-for="y in yearOptions" :key="y" :value="y">{{ y }}</option>
          </select>
        </label>
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">Pay date</span>
          <input v-model="newRun.pay_date" type="date" class="w-full border border-slate-300 rounded-md px-3 py-2" />
        </label>
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">Label (optional)</span>
          <input v-model="newRun.label" type="text" placeholder="e.g. March 2026" class="w-full border border-slate-300 rounded-md px-3 py-2" />
        </label>
      </div>
      <div class="mt-4 flex justify-end">
        <button
          type="button"
          @click="createRun"
          :disabled="creating"
          class="px-4 py-2 bg-sycamore-600 text-white rounded-md text-sm font-medium hover:bg-sycamore-700 disabled:opacity-50"
        >
          {{ creating ? 'Computing...' : 'Compute payroll' }}
        </button>
      </div>
    </section>

    <section class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <header class="px-5 py-4 border-b border-slate-200">
        <h3 class="text-sm font-semibold text-slate-900">Runs</h3>
      </header>
      <div v-if="loading" class="p-5 text-sm text-slate-500">Loading...</div>
      <div v-else-if="runs.length === 0" class="p-5 text-sm text-slate-500">No runs yet.</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Period</th>
            <th class="text-left px-5 py-2">Status</th>
            <th class="text-right px-5 py-2">Gross</th>
            <th class="text-right px-5 py-2">PAYE</th>
            <th class="text-right px-5 py-2">Net</th>
            <th class="text-right px-5 py-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in runs" :key="r.id" class="border-t border-slate-100 hover:bg-slate-50">
            <td class="px-5 py-3">
              <button type="button" @click="openRun(r)" class="font-medium text-slate-900 hover:text-sycamore-700">
                {{ r.label || (MONTH_NAMES[r.period_month - 1] + ' ' + r.period_year) }}
              </button>
            </td>
            <td class="px-5 py-3">
              <span class="inline-block text-xs font-semibold px-2 py-0.5 rounded border capitalize" :class="statusClass(r.status)">{{ r.status }}</span>
            </td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(r.total_gross) }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(r.total_paye) }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(r.total_net) }}</td>
            <td class="px-5 py-3 text-right space-x-2">
              <button type="button" @click="openRun(r)" class="text-sycamore-700 font-medium">View</button>
              <button v-if="r.status === 'draft'" type="button" @click="approve(r)" class="text-sky-700 font-medium">Approve</button>
              <button v-if="r.status === 'approved'" type="button" @click="markPaid(r)" class="text-emerald-700 font-medium">Mark paid</button>
              <button v-if="r.status === 'draft'" type="button" @click="deleteRun(r)" class="text-rose-600 font-medium">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <section v-if="selectedRun" class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <header class="px-5 py-4 border-b border-slate-200 flex items-center justify-between gap-3">
        <div>
          <h3 class="text-sm font-semibold text-slate-900">
            {{ selectedRun.label || (MONTH_NAMES[selectedRun.period_month - 1] + ' ' + selectedRun.period_year) }}
          </h3>
          <p class="text-xs text-slate-500 mt-0.5">{{ selectedItems.length }} employees</p>
        </div>
        <div class="flex items-center gap-2">
          <button type="button" @click="exportCsv" class="px-3 py-1.5 text-xs border border-slate-300 rounded-md hover:bg-slate-50">
            Export CSV
          </button>
          <button type="button" @click="selectedRun = null" class="text-slate-400 hover:text-slate-600" aria-label="Close">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5"><path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z"/></svg>
          </button>
        </div>
      </header>
      <div v-if="loadingItems" class="p-5 text-sm text-slate-500">Loading items...</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Employee</th>
            <th class="text-right px-5 py-2">Gross</th>
            <th class="text-right px-5 py-2">Pension</th>
            <th class="text-right px-5 py-2">NHF</th>
            <th class="text-right px-5 py-2">PAYE</th>
            <th class="text-right px-5 py-2">Net</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="it in selectedItems" :key="it.id" class="border-t border-slate-100">
            <td class="px-5 py-3">
              <div class="font-medium text-slate-900">{{ it.full_name }}</div>
              <div class="text-xs text-slate-500">{{ it.email }} <span v-if="it.grade">&middot; {{ it.grade }}</span></div>
            </td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(it.gross) }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(it.pension_employee) }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(it.nhf) }}</td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(it.paye) }}</td>
            <td class="px-5 py-3 text-right tabular-nums font-semibold">{{ formatNaira(it.net) }}</td>
          </tr>
        </tbody>
      </table>
    </section>
  </div>
</template>
