<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { formatNaira, MONTH_NAMES } from '~/composables/usePayroll'

const supabase = useSupabase()
const { user } = useAuth()
const items = ref<any[]>([])
const loading = ref(true)
const selected = ref<any | null>(null)

async function load() {
  loading.value = true
  try {
    if (!user.value) return
    const { data: staff } = await supabase.from('staff_members').select('id').eq('auth_user_id', user.value.id).maybeSingle()
    if (!staff) { items.value = []; return }
    const { data } = await supabase
      .from('payroll_items')
      .select('*, run:payroll_runs(period_year,period_month,status,pay_date,label)')
      .eq('staff_id', (staff as any).id)
      .order('created_at', { ascending: false })
    items.value = (data ?? []).filter((it: any) => ['approved','paid'].includes(it.run?.status))
  } finally { loading.value = false }
}

load()

const ytd = computed(() => {
  const curYear = new Date().getFullYear()
  const rows = items.value.filter(it => it.run?.period_year === curYear)
  const sum = (key: string) => rows.reduce((a, r) => a + Number(r[key] || 0), 0)
  return {
    gross: sum('gross'), paye: sum('paye'), pension: sum('pension_employee'), nhf: sum('nhf'), net: sum('net')
  }
})

function periodLabel(it: any) {
  if (!it.run) return ''
  return it.run.label || `${MONTH_NAMES[it.run.period_month - 1]} ${it.run.period_year}`
}
</script>

<template>
  <div class="max-w-5xl mx-auto">
    <header class="mb-6">
      <h1 class="text-2xl font-semibold text-slate-900">My Payroll</h1>
      <p class="text-sm text-slate-500 mt-1">Your payslips and year-to-date earnings.</p>
    </header>

    <section class="grid grid-cols-2 sm:grid-cols-5 gap-3 mb-8">
      <div class="bg-white border border-slate-200 rounded-xl p-4">
        <div class="text-xs text-slate-500">YTD Gross</div>
        <div class="text-lg font-semibold text-slate-900 tabular-nums">{{ formatNaira(ytd.gross) }}</div>
      </div>
      <div class="bg-white border border-slate-200 rounded-xl p-4">
        <div class="text-xs text-slate-500">YTD PAYE</div>
        <div class="text-lg font-semibold text-slate-900 tabular-nums">{{ formatNaira(ytd.paye) }}</div>
      </div>
      <div class="bg-white border border-slate-200 rounded-xl p-4">
        <div class="text-xs text-slate-500">YTD Pension</div>
        <div class="text-lg font-semibold text-slate-900 tabular-nums">{{ formatNaira(ytd.pension) }}</div>
      </div>
      <div class="bg-white border border-slate-200 rounded-xl p-4">
        <div class="text-xs text-slate-500">YTD NHF</div>
        <div class="text-lg font-semibold text-slate-900 tabular-nums">{{ formatNaira(ytd.nhf) }}</div>
      </div>
      <div class="bg-white border border-slate-200 rounded-xl p-4 col-span-2 sm:col-span-1">
        <div class="text-xs text-slate-500">YTD Net</div>
        <div class="text-lg font-semibold text-emerald-700 tabular-nums">{{ formatNaira(ytd.net) }}</div>
      </div>
    </section>

    <section class="bg-white border border-slate-200 rounded-xl overflow-x-auto">
      <header class="px-5 py-4 border-b border-slate-200">
        <h2 class="text-sm font-semibold text-slate-900">Payslips</h2>
      </header>
      <div v-if="loading" class="p-5 text-sm text-slate-500">Loading...</div>
      <div v-else-if="items.length === 0" class="p-5 text-sm text-slate-500">No payslips yet.</div>
      <table v-else class="w-full text-xs sm:text-sm min-w-[640px]">
        <thead class="bg-slate-50 text-slate-500 text-[10px] sm:text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-3 sm:px-5 py-2">Period</th>
            <th class="text-left px-3 sm:px-5 py-2">Status</th>
            <th class="text-right px-3 sm:px-5 py-2">Gross</th>
            <th class="text-right px-3 sm:px-5 py-2">Tax</th>
            <th class="text-right px-3 sm:px-5 py-2">Deductions</th>
            <th class="text-right px-3 sm:px-5 py-2">Net</th>
            <th class="text-right px-3 sm:px-5 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="it in items" :key="it.id" class="border-t border-slate-100 hover:bg-slate-50">
            <td class="px-5 py-3 font-medium text-slate-900">{{ periodLabel(it) }}</td>
            <td class="px-5 py-3">
              <span class="text-xs font-semibold px-2 py-0.5 rounded border capitalize"
                :class="it.run?.status === 'paid' ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-sky-50 text-sky-700 border-sky-200'">
                {{ it.run?.status }}
              </span>
            </td>
            <td class="px-5 py-3 text-right tabular-nums">{{ formatNaira(it.gross) }}</td>
            <td class="px-5 py-3 text-right tabular-nums text-rose-700">{{ formatNaira(it.paye) }}</td>
            <td class="px-5 py-3 text-right tabular-nums text-slate-600">
              {{ formatNaira(Number(it.pension_employee || 0) + Number(it.nhf || 0) + Number(it.nhis || 0) + Number(it.other_deductions || 0)) }}
            </td>
            <td class="px-5 py-3 text-right tabular-nums font-semibold">{{ formatNaira(it.net) }}</td>
            <td class="px-5 py-3 text-right"><button type="button" @click="selected = it" class="text-sycamore-700 font-medium">View</button></td>
          </tr>
        </tbody>
      </table>
    </section>

    <div v-if="selected" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="selected = null">
      <div class="bg-white rounded-2xl max-w-lg w-full max-h-[90vh] overflow-y-auto shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200 flex items-center justify-between">
          <div>
            <h3 class="text-base font-semibold text-slate-900">Payslip &middot; {{ periodLabel(selected) }}</h3>
            <p class="text-xs text-slate-500">{{ selected.full_name }}</p>
          </div>
          <button type="button" @click="selected = null" class="text-slate-400 hover:text-slate-600">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5"><path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z"/></svg>
          </button>
        </header>
        <div class="p-6 space-y-5">
          <section>
            <h4 class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Earnings</h4>
            <dl class="space-y-1 text-sm">
              <div class="flex justify-between"><dt class="text-slate-600">Basic</dt><dd class="tabular-nums">{{ formatNaira(selected.basic) }}</dd></div>
              <div class="flex justify-between"><dt class="text-slate-600">Housing</dt><dd class="tabular-nums">{{ formatNaira(selected.housing) }}</dd></div>
              <div class="flex justify-between"><dt class="text-slate-600">Transport</dt><dd class="tabular-nums">{{ formatNaira(selected.transport) }}</dd></div>
              <div class="flex justify-between"><dt class="text-slate-600">Utility</dt><dd class="tabular-nums">{{ formatNaira(selected.utility) }}</dd></div>
              <div class="flex justify-between"><dt class="text-slate-600">Meal</dt><dd class="tabular-nums">{{ formatNaira(selected.meal) }}</dd></div>
              <div class="flex justify-between"><dt class="text-slate-600">Leave allowance</dt><dd class="tabular-nums">{{ formatNaira(selected.leave_allowance) }}</dd></div>
              <div class="flex justify-between"><dt class="text-slate-600">Other</dt><dd class="tabular-nums">{{ formatNaira(Number(selected.other_earnings) + Number(selected.bonus)) }}</dd></div>
              <div class="flex justify-between pt-2 border-t border-slate-100 font-semibold"><dt>Gross</dt><dd class="tabular-nums">{{ formatNaira(selected.gross) }}</dd></div>
            </dl>
          </section>
          <section class="bg-rose-50 border border-rose-200 rounded-lg p-4">
            <div class="flex items-center justify-between text-sm">
              <div>
                <div class="text-xs font-semibold uppercase tracking-wide text-rose-800">Tax (PAYE)</div>
                <div class="text-[11px] text-rose-700/80 mt-0.5">Effective rate {{ selected.gross > 0 ? ((Number(selected.paye) / Number(selected.gross)) * 100).toFixed(1) : '0.0' }}% of gross</div>
              </div>
              <div class="text-lg font-bold text-rose-900 tabular-nums">{{ formatNaira(selected.paye) }}</div>
            </div>
          </section>
          <section>
            <h4 class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Deductions</h4>
            <dl class="space-y-1 text-sm">
              <div class="flex justify-between"><dt class="text-slate-600">Pension (8%)</dt><dd class="tabular-nums">{{ formatNaira(selected.pension_employee) }}</dd></div>
              <div class="flex justify-between"><dt class="text-slate-600">NHF</dt><dd class="tabular-nums">{{ formatNaira(selected.nhf) }}</dd></div>
              <div class="flex justify-between"><dt class="text-slate-600">NHIS</dt><dd class="tabular-nums">{{ formatNaira(selected.nhis) }}</dd></div>
              <div class="flex justify-between"><dt class="text-slate-600">PAYE (income tax)</dt><dd class="tabular-nums">{{ formatNaira(selected.paye) }}</dd></div>
              <div class="flex justify-between"><dt class="text-slate-600">Other</dt><dd class="tabular-nums">{{ formatNaira(selected.other_deductions) }}</dd></div>
              <div class="flex justify-between pt-2 border-t border-slate-100 font-semibold">
                <dt>Total deductions</dt>
                <dd class="tabular-nums">{{ formatNaira(Number(selected.pension_employee || 0) + Number(selected.nhf || 0) + Number(selected.nhis || 0) + Number(selected.paye || 0) + Number(selected.other_deductions || 0)) }}</dd>
              </div>
            </dl>
          </section>
          <section class="bg-emerald-50 border border-emerald-200 rounded-lg p-4 flex items-center justify-between">
            <span class="text-sm font-semibold text-emerald-900">Net pay</span>
            <span class="text-xl font-bold text-emerald-900 tabular-nums">{{ formatNaira(selected.net) }}</span>
          </section>
          <p class="text-xs text-slate-500">Consolidated Relief Allowance (monthly): {{ formatNaira(selected.cra) }}. Taxable income (monthly): {{ formatNaira(selected.taxable_income) }}.</p>
        </div>
      </div>
    </div>
  </div>
</template>
