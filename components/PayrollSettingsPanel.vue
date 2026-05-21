<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const toast = useToast()
const { log: auditLog } = useAuditLog()
const loading = ref(true)
const saving = ref(false)
const s = ref<any>({})

async function load() {
  loading.value = true
  const { data } = await supabase.from('payroll_settings').select('*').eq('id', 1).maybeSingle()
  s.value = data ?? {}
  loading.value = false
}

async function save() {
  saving.value = true
  try {
    const payload = {
      company_name: s.value.company_name || '',
      company_tin: s.value.company_tin || '',
      pension_employee_rate: Number(s.value.pension_employee_rate) || 0,
      pension_employer_rate: Number(s.value.pension_employer_rate) || 0,
      nhf_rate: Number(s.value.nhf_rate) || 0,
      nhis_rate: Number(s.value.nhis_rate) || 0,
      nsitf_rate: Number(s.value.nsitf_rate) || 0,
      itf_rate: Number(s.value.itf_rate) || 0,
      nhis_enabled: Boolean(s.value.nhis_enabled),
      nsitf_enabled: Boolean(s.value.nsitf_enabled),
      itf_enabled: Boolean(s.value.itf_enabled),
      updated_at: new Date().toISOString()
    }
    const { error } = await supabase.from('payroll_settings').update(payload).eq('id', 1)
    if (error) throw error
    auditLog({ action: 'update', target_type: 'payroll_settings', target_label: 'Payroll settings' })
    toast.success('Settings saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

load()

function pct(n: number) { return (Number(n || 0) * 100).toFixed(2) + '%' }
</script>

<template>
  <div v-if="loading" class="text-sm text-slate-500">Loading settings...</div>
  <form v-else @submit.prevent="save" class="max-w-3xl space-y-6">
    <section class="bg-white border border-slate-200 rounded-xl p-5">
      <h3 class="text-sm font-semibold text-slate-900 mb-4">Company</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">Company name</span>
          <input v-model="s.company_name" type="text" class="w-full border border-slate-300 rounded-md px-3 py-2" />
        </label>
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">Company TIN</span>
          <input v-model="s.company_tin" type="text" class="w-full border border-slate-300 rounded-md px-3 py-2" />
        </label>
      </div>
    </section>

    <section class="bg-white border border-slate-200 rounded-xl p-5">
      <h3 class="text-sm font-semibold text-slate-900 mb-1">Pension (PRA 2014)</h3>
      <p class="text-xs text-slate-500 mb-4">Applied to basic + housing + transport.</p>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">Employee rate ({{ pct(s.pension_employee_rate) }})</span>
          <input v-model.number="s.pension_employee_rate" type="number" step="0.001" min="0" max="1" class="w-full border border-slate-300 rounded-md px-3 py-2" />
        </label>
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">Employer rate ({{ pct(s.pension_employer_rate) }})</span>
          <input v-model.number="s.pension_employer_rate" type="number" step="0.001" min="0" max="1" class="w-full border border-slate-300 rounded-md px-3 py-2" />
        </label>
      </div>
    </section>

    <section class="bg-white border border-slate-200 rounded-xl p-5">
      <h3 class="text-sm font-semibold text-slate-900 mb-1">NHF &middot; NHIS</h3>
      <p class="text-xs text-slate-500 mb-4">NHF is opted in per-employee. NHIS is org-wide.</p>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">NHF rate ({{ pct(s.nhf_rate) }})</span>
          <input v-model.number="s.nhf_rate" type="number" step="0.001" min="0" max="1" class="w-full border border-slate-300 rounded-md px-3 py-2" />
        </label>
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">NHIS rate ({{ pct(s.nhis_rate) }})</span>
          <input v-model.number="s.nhis_rate" type="number" step="0.001" min="0" max="1" class="w-full border border-slate-300 rounded-md px-3 py-2" />
        </label>
        <label class="flex items-center gap-2 text-sm sm:col-span-2">
          <input v-model="s.nhis_enabled" type="checkbox" class="rounded" />
          <span>Enable NHIS deduction org-wide</span>
        </label>
      </div>
    </section>

    <section class="bg-white border border-slate-200 rounded-xl p-5">
      <h3 class="text-sm font-semibold text-slate-900 mb-1">Employer-side statutory (NSITF &middot; ITF)</h3>
      <p class="text-xs text-slate-500 mb-4">These are employer contributions; they do not reduce employee net pay.</p>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">NSITF rate ({{ pct(s.nsitf_rate) }})</span>
          <input v-model.number="s.nsitf_rate" type="number" step="0.001" min="0" max="1" class="w-full border border-slate-300 rounded-md px-3 py-2" />
        </label>
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">ITF rate ({{ pct(s.itf_rate) }})</span>
          <input v-model.number="s.itf_rate" type="number" step="0.001" min="0" max="1" class="w-full border border-slate-300 rounded-md px-3 py-2" />
        </label>
        <label class="flex items-center gap-2 text-sm">
          <input v-model="s.nsitf_enabled" type="checkbox" class="rounded" />
          <span>Enable NSITF</span>
        </label>
        <label class="flex items-center gap-2 text-sm">
          <input v-model="s.itf_enabled" type="checkbox" class="rounded" />
          <span>Enable ITF</span>
        </label>
      </div>
    </section>

    <div class="flex justify-end">
      <button type="submit" :disabled="saving" class="px-4 py-2 bg-sycamore-600 text-white rounded-md text-sm font-medium hover:bg-sycamore-700 disabled:opacity-50">
        {{ saving ? 'Saving...' : 'Save settings' }}
      </button>
    </div>
  </form>
</template>
