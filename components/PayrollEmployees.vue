<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { formatNaira } from '~/composables/usePayroll'

const supabase = useSupabase()
const { items, loading, load, create, update, remove } = useCrud('payroll_employees')
const toast = useToast()
const { log: auditLog } = useAuditLog()
const staff = ref<any[]>([])

const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)
const bulkOpen = ref(false)

const fields = computed(() => [
  { key: 'full_name', label: 'Full name', required: true },
  { key: 'email', label: 'Email', type: 'email', required: true },
  {
    key: 'staff_id', label: 'Linked staff record', type: 'select',
    options: [{ value: '', label: 'Not linked' }, ...staff.value.map(s => ({ value: s.id, label: `${s.full_name} (${s.email})` }))]
  },
  { key: 'grade', label: 'Grade / level' },
  { key: 'job_title', label: 'Job title' },
  { key: 'tin', label: 'Tax ID (TIN)' },
  { key: 'bank_name', label: 'Bank name' },
  { key: 'bank_account', label: 'Bank account no.' },
  { key: 'pfa_name', label: 'Pension PFA' },
  { key: 'pfa_pin', label: 'RSA PIN' },
  { key: 'pay_basic', label: 'Basic (monthly)', type: 'number' },
  { key: 'pay_housing', label: 'Housing allowance', type: 'number' },
  { key: 'pay_transport', label: 'Transport allowance', type: 'number' },
  { key: 'pay_utility', label: 'Utility allowance', type: 'number' },
  { key: 'pay_meal', label: 'Meal allowance', type: 'number' },
  { key: 'pay_leave', label: 'Leave allowance', type: 'number' },
  { key: 'pay_other', label: 'Other earnings', type: 'number' },
  { key: 'nhf_enabled', label: 'Enrol in NHF (2.5% of basic)', type: 'checkbox' },
  { key: 'is_active', label: 'Active on payroll', type: 'checkbox' },
  { key: 'notes', label: 'Notes', type: 'textarea' }
])

const columns = [
  { key: 'full_name', label: 'Name' },
  { key: 'grade', label: 'Grade' },
  { key: 'pay_basic', label: 'Basic', render: (r: any) => formatNaira(r.pay_basic) },
  {
    key: 'gross', label: 'Gross',
    render: (r: any) => formatNaira(
      Number(r.pay_basic || 0) + Number(r.pay_housing || 0) + Number(r.pay_transport || 0) +
      Number(r.pay_utility || 0) + Number(r.pay_meal || 0) + Number(r.pay_leave || 0) + Number(r.pay_other || 0)
    )
  },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' }
]

await Promise.all([
  load([{ column: 'full_name', ascending: true }]),
  (async () => { const { data } = await supabase.from('staff_members').select('id, full_name, email').order('full_name'); staff.value = data ?? [] })()
])

function openNew() { editing.value = { is_active: true, nhf_enabled: false }; editorOpen.value = true }
function openEdit(row: any) {
  editing.value = { ...row, staff_id: row.staff_id ?? '' }
  editorOpen.value = true
}

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data: any = {
      full_name: payload.full_name,
      email: payload.email,
      staff_id: payload.staff_id || null,
      grade: payload.grade || '',
      job_title: payload.job_title || '',
      tin: payload.tin || '',
      bank_name: payload.bank_name || '',
      bank_account: payload.bank_account || '',
      pfa_name: payload.pfa_name || '',
      pfa_pin: payload.pfa_pin || '',
      pay_basic: Number(payload.pay_basic) || 0,
      pay_housing: Number(payload.pay_housing) || 0,
      pay_transport: Number(payload.pay_transport) || 0,
      pay_utility: Number(payload.pay_utility) || 0,
      pay_meal: Number(payload.pay_meal) || 0,
      pay_leave: Number(payload.pay_leave) || 0,
      pay_other: Number(payload.pay_other) || 0,
      nhf_enabled: Boolean(payload.nhf_enabled),
      is_active: Boolean(payload.is_active),
      notes: payload.notes || ''
    }
    if (editing.value?.id) await update(editing.value.id, { ...data, updated_at: new Date().toISOString() })
    else await create(data)
    auditLog({ action: editing.value?.id ? 'update' : 'create', target_type: 'payroll_employee', target_label: data.full_name })
    editorOpen.value = false
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Remove from payroll', message: `Remove "${row.full_name}" from payroll?`, variant: 'danger', confirmLabel: 'Remove' })
  if (!ok) return
  try {
    await remove(row.id)
    auditLog({ action: 'delete', target_type: 'payroll_employee', target_id: row.id, target_label: row.full_name })
    toast.success('Removed')
  } catch (e: any) { toast.error(e.message ?? 'Failed to remove') }
}
</script>

<template>
  <div>
    <div class="flex justify-end mb-3">
      <button type="button" @click="bulkOpen = true" class="px-4 py-2 border border-slate-300 rounded-md text-sm font-medium hover:bg-slate-50">
        Bulk upload
      </button>
    </div>
    <AdminList
      title="Payroll employees"
      description="Each employee's salary structure used to compute monthly payroll."
      :columns="columns"
      :rows="items"
      :loading="loading"
      new-label="Add employee"
      @new="openNew"
      @edit="openEdit"
      @delete="del"
    />
    <AdminEditor
      :open="editorOpen"
      :title="editing?.id ? 'Edit payroll employee' : 'New payroll employee'"
      :fields="(fields as any)"
      :initial="editing"
      :saving="saving"
      @close="editorOpen = false"
      @save="save"
    />
    <LazyPayrollBulkUpload
      :open="bulkOpen"
      @close="bulkOpen = false"
      @imported="load([{ column: 'full_name', ascending: true }])"
    />
  </div>
</template>
