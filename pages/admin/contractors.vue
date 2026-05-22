<script setup lang="ts">
definePageMeta({ layout: 'admin', title: 'Contractors & Vendors' })

const supabase = useSupabase()
const { user, ready, isAdmin } = useAuth()
const { success, error: toastError } = useToast()

interface Contractor {
  id: string
  name: string
  company: string
  email: string
  phone: string
  role: string
  department: string
  contract_start: string | null
  contract_end: string | null
  status: 'active' | 'expired' | 'terminated'
  billing_type: 'one_time' | 'monthly'
  rate: number | null
  notes: string
  created_at: string
}

const contractors = ref<Contractor[]>([])
const loading = ref(true)
const filter = ref('all')
const search = ref('')
const showForm = ref(false)
const editing = ref<Contractor | null>(null)
const form = ref({
  name: '', company: '', email: '', phone: '', role: '', department: '',
  contract_start: '', contract_end: '', status: 'active',
  billing_type: 'monthly' as string, rate: '' as string | number, notes: ''
})

async function load() {
  loading.value = true
  const { data } = await supabase.from('contractors').select('*').order('name')
  contractors.value = (data ?? []) as Contractor[]
  loading.value = false
}

const filtered = computed(() => {
  let list = contractors.value
  if (filter.value !== 'all') list = list.filter(c => c.status === filter.value)
  if (search.value) {
    const s = search.value.toLowerCase()
    list = list.filter(c => c.name.toLowerCase().includes(s) || c.company.toLowerCase().includes(s))
  }
  return list
})

function openAdd() {
  editing.value = null
  form.value = { name: '', company: '', email: '', phone: '', role: '', department: '', contract_start: '', contract_end: '', status: 'active', billing_type: 'monthly', rate: '', notes: '' }
  showForm.value = true
}

function openEdit(c: Contractor) {
  editing.value = c
  form.value = {
    name: c.name, company: c.company, email: c.email, phone: c.phone,
    role: c.role, department: c.department,
    contract_start: c.contract_start ?? '', contract_end: c.contract_end ?? '',
    status: c.status, billing_type: c.billing_type ?? 'monthly', rate: c.rate ?? '', notes: c.notes
  }
  showForm.value = true
}

async function save() {
  const payload: any = {
    name: form.value.name.trim(),
    company: form.value.company.trim(),
    email: form.value.email.trim(),
    phone: form.value.phone.trim(),
    role: form.value.role.trim(),
    department: form.value.department.trim(),
    contract_start: form.value.contract_start || null,
    contract_end: form.value.contract_end || null,
    status: form.value.status,
    billing_type: form.value.billing_type,
    rate: form.value.rate ? Number(form.value.rate) : null,
    notes: form.value.notes.trim()
  }
  if (editing.value) {
    const { error } = await supabase.from('contractors').update(payload).eq('id', editing.value.id)
    if (error) toastError('Failed to update'); else success('Updated')
  } else {
    payload.created_by = user.value?.id
    const { error } = await supabase.from('contractors').insert(payload)
    if (error) toastError('Failed to add'); else success('Contractor added')
  }
  showForm.value = false
  await load()
}

async function remove(id: string) {
  const { error } = await supabase.from('contractors').delete().eq('id', id)
  if (error) toastError('Failed to delete'); else { success('Deleted'); await load() }
}

watch(ready, (r) => { if (r && isAdmin.value) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-5xl mx-auto px-4 py-8">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="section-title">Contractors & Vendors</h1>
        <p class="section-subtitle">Manage external workforce and vendor contracts</p>
      </div>
      <button @click="openAdd" class="btn-primary">Add Contractor</button>
    </div>

    <div class="flex flex-wrap gap-2 mb-4">
      <input v-model="search" class="input w-auto flex-1 min-w-[200px]" placeholder="Search...">
      <select v-model="filter" class="input w-auto">
        <option value="all">All</option>
        <option value="active">Active</option>
        <option value="expired">Expired</option>
        <option value="terminated">Terminated</option>
      </select>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-400">No contractors found.</div>
    <div v-else class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-slate-200 text-left text-xs text-slate-500 uppercase">
            <th class="p-3">Name</th>
            <th class="p-3">Company</th>
            <th class="p-3">Role</th>
            <th class="p-3">Contract End</th>
            <th class="p-3">Status</th>
            <th class="p-3">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="c in filtered" :key="c.id" class="border-b border-slate-100 hover:bg-slate-50">
            <td class="p-3 font-medium text-slate-900">{{ c.name }}</td>
            <td class="p-3 text-slate-600">{{ c.company }}</td>
            <td class="p-3 text-slate-600">{{ c.role }}</td>
            <td class="p-3 text-slate-600">{{ c.contract_end ?? '-' }}</td>
            <td class="p-3">
              <span class="badge border" :class="c.status === 'active' ? 'badge-green' : c.status === 'expired' ? 'badge-amber' : 'badge-rose'">{{ c.status }}</span>
            </td>
            <td class="p-3">
              <div class="flex gap-2">
                <button @click="openEdit(c)" class="text-sycamore-600 hover:text-sycamore-800 text-xs font-medium">Edit</button>
                <button @click="remove(c.id)" class="text-red-500 hover:text-red-700 text-xs font-medium">Delete</button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Form Modal -->
    <div v-if="showForm" class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" @click.self="showForm = false">
      <div class="bg-white rounded-xl shadow-xl w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto">
        <h2 class="text-lg font-bold text-slate-900 mb-4">{{ editing ? 'Edit' : 'Add' }} Contractor</h2>
        <div class="space-y-3">
          <div class="grid grid-cols-2 gap-3">
            <div><label class="block text-xs font-medium text-slate-600 mb-1">Name</label><input v-model="form.name" class="input"></div>
            <div><label class="block text-xs font-medium text-slate-600 mb-1">Company</label><input v-model="form.company" class="input"></div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div><label class="block text-xs font-medium text-slate-600 mb-1">Email</label><input v-model="form.email" type="email" class="input"></div>
            <div><label class="block text-xs font-medium text-slate-600 mb-1">Phone</label><input v-model="form.phone" class="input"></div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div><label class="block text-xs font-medium text-slate-600 mb-1">Role</label><input v-model="form.role" class="input"></div>
            <div><label class="block text-xs font-medium text-slate-600 mb-1">Department (optional)</label><input v-model="form.department" class="input" placeholder="Leave blank if not tied to one"></div>
          </div>
          <div class="grid grid-cols-3 gap-3">
            <div><label class="block text-xs font-medium text-slate-600 mb-1">Start</label><input v-model="form.contract_start" type="date" class="input"></div>
            <div><label class="block text-xs font-medium text-slate-600 mb-1">End</label><input v-model="form.contract_end" type="date" class="input"></div>
            <div><label class="block text-xs font-medium text-slate-600 mb-1">Status</label>
              <select v-model="form.status" class="input">
                <option value="active">Active</option>
                <option value="expired">Expired</option>
                <option value="terminated">Terminated</option>
              </select>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div><label class="block text-xs font-medium text-slate-600 mb-1">Billing Type</label>
              <select v-model="form.billing_type" class="input">
                <option value="monthly">Monthly</option>
                <option value="one_time">One-time Fee</option>
              </select>
            </div>
            <div><label class="block text-xs font-medium text-slate-600 mb-1">Amount</label><input v-model="form.rate" type="number" step="0.01" class="input" placeholder="Optional"></div>
          </div>
          <div><label class="block text-xs font-medium text-slate-600 mb-1">Notes</label><textarea v-model="form.notes" class="input min-h-[60px]" /></div>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <button @click="showForm = false" class="btn-secondary">Cancel</button>
          <button @click="save" :disabled="!form.name.trim()" class="btn-primary">{{ editing ? 'Update' : 'Add' }}</button>
        </div>
      </div>
    </div>
  </div>
</template>
