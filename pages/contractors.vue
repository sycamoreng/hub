<script setup lang="ts">
definePageMeta({ title: 'Contractors & Vendors' })

const supabase = useSupabase()
const { ready, isAdmin } = useAuth()
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
const filter = ref<'all' | 'active' | 'expired' | 'terminated'>('active')
const search = ref('')
const showForm = ref(false)
const editing = ref<Contractor | null>(null)
const form = ref({
  name: '', company: '', email: '', phone: '', role: '', department: '',
  contract_start: '', contract_end: '', status: 'active' as string,
  billing_type: 'monthly' as string, rate: '' as string | number, notes: ''
})

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('contractors')
    .select('*')
    .order('created_at', { ascending: false })
  contractors.value = (data ?? []) as Contractor[]
  loading.value = false
}

const filtered = computed(() => {
  let list = contractors.value
  if (filter.value !== 'all') list = list.filter(c => c.status === filter.value)
  if (search.value) {
    const s = search.value.toLowerCase()
    list = list.filter(c => c.name.toLowerCase().includes(s) || c.company.toLowerCase().includes(s) || c.role.toLowerCase().includes(s))
  }
  return list
})

const stats = computed(() => ({
  active: contractors.value.filter(c => c.status === 'active').length,
  expiringSoon: contractors.value.filter(c => {
    if (c.status !== 'active' || !c.contract_end) return false
    const days = (new Date(c.contract_end).getTime() - Date.now()) / 86400000
    return days <= 30 && days > 0
  }).length,
  expired: contractors.value.filter(c => c.status === 'expired').length,
  total: contractors.value.length
}))

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
    if (error) toastError('Failed to update'); else success('Contractor updated')
  } else {
    const { error } = await supabase.from('contractors').insert(payload)
    if (error) toastError('Failed to add'); else success('Contractor added')
  }
  showForm.value = false
  await load()
}

function daysUntilExpiry(end: string | null) {
  if (!end) return null
  return Math.ceil((new Date(end).getTime() - Date.now()) / 86400000)
}

watch(ready, (r) => { if (r && isAdmin.value) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-6xl mx-auto px-4 py-8">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="section-title">Contractors & Vendors</h1>
        <p class="section-subtitle">Manage external contractors, vendors, and their contracts</p>
      </div>
      <button v-if="isAdmin" @click="openAdd" class="btn-primary">Add Contractor</button>
    </div>

    <div v-if="!isAdmin" class="card p-8 text-center text-slate-500">
      This page is only accessible to administrators.
    </div>

    <template v-else>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
        <div class="card p-4 text-center">
          <div class="text-2xl font-bold text-slate-900">{{ stats.total }}</div>
          <div class="text-xs text-slate-500 mt-1">Total</div>
        </div>
        <div class="card p-4 text-center">
          <div class="text-2xl font-bold text-leaf-600">{{ stats.active }}</div>
          <div class="text-xs text-slate-500 mt-1">Active</div>
        </div>
        <div class="card p-4 text-center">
          <div class="text-2xl font-bold text-amber-600">{{ stats.expiringSoon }}</div>
          <div class="text-xs text-slate-500 mt-1">Expiring Soon</div>
        </div>
        <div class="card p-4 text-center">
          <div class="text-2xl font-bold text-red-600">{{ stats.expired }}</div>
          <div class="text-xs text-slate-500 mt-1">Expired</div>
        </div>
      </div>

      <div class="flex flex-wrap gap-2 mb-4">
        <input v-model="search" class="input w-auto flex-1 min-w-[200px]" placeholder="Search contractors...">
        <select v-model="filter" class="input w-auto">
          <option value="all">All</option>
          <option value="active">Active</option>
          <option value="expired">Expired</option>
          <option value="terminated">Terminated</option>
        </select>
      </div>

      <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
      <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-400">No contractors found.</div>
      <div v-else class="grid gap-3">
        <div v-for="c in filtered" :key="c.id" class="card p-4 card-hover cursor-pointer" @click="openEdit(c)">
          <div class="flex items-start justify-between gap-3">
            <div>
              <div class="flex items-center gap-2 mb-1">
                <span class="font-semibold text-slate-900">{{ c.name }}</span>
                <span v-if="c.company" class="text-sm text-slate-500">@ {{ c.company }}</span>
                <span class="badge border" :class="c.status === 'active' ? 'badge-green' : c.status === 'expired' ? 'badge-amber' : 'badge-rose'">{{ c.status }}</span>
              </div>
              <div class="text-sm text-slate-600">{{ c.role }}<span v-if="c.department"> - {{ c.department }}</span></div>
              <div class="flex items-center gap-3 mt-2 text-xs text-slate-500">
                <span v-if="c.contract_start">Start: {{ c.contract_start }}</span>
                <span v-if="c.contract_end" :class="{ 'text-amber-600 font-medium': daysUntilExpiry(c.contract_end) !== null && daysUntilExpiry(c.contract_end)! <= 30 && daysUntilExpiry(c.contract_end)! > 0 }">
                  End: {{ c.contract_end }}
                  <template v-if="daysUntilExpiry(c.contract_end) !== null && daysUntilExpiry(c.contract_end)! > 0 && daysUntilExpiry(c.contract_end)! <= 30">
                    ({{ daysUntilExpiry(c.contract_end) }}d left)
                  </template>
                </span>
                <span v-if="c.rate" class="capitalize">{{ c.billing_type === 'one_time' ? 'One-time' : 'Monthly' }}: {{ c.rate.toLocaleString() }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>

    <!-- Add/Edit Modal -->
    <div v-if="showForm" class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" @click.self="showForm = false">
      <div class="bg-white rounded-xl shadow-xl w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto">
        <h2 class="text-lg font-bold text-slate-900 mb-4">{{ editing ? 'Edit' : 'Add' }} Contractor</h2>
        <div class="space-y-3">
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Name</label>
              <input v-model="form.name" class="input" placeholder="Full name">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Company</label>
              <input v-model="form.company" class="input" placeholder="Company name">
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Email</label>
              <input v-model="form.email" type="email" class="input">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Phone</label>
              <input v-model="form.phone" class="input">
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Role</label>
              <input v-model="form.role" class="input" placeholder="e.g. Security Guard">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Department (optional)</label>
              <input v-model="form.department" class="input" placeholder="Leave blank if not tied to one">
            </div>
          </div>
          <div class="grid grid-cols-3 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Contract Start</label>
              <input v-model="form.contract_start" type="date" class="input">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Contract End</label>
              <input v-model="form.contract_end" type="date" class="input">
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Status</label>
              <select v-model="form.status" class="input">
                <option value="active">Active</option>
                <option value="expired">Expired</option>
                <option value="terminated">Terminated</option>
              </select>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Billing Type</label>
              <select v-model="form.billing_type" class="input">
                <option value="monthly">Monthly</option>
                <option value="one_time">One-time Fee</option>
              </select>
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Amount</label>
              <input v-model="form.rate" type="number" step="0.01" class="input" placeholder="Optional">
            </div>
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Notes</label>
            <textarea v-model="form.notes" class="input min-h-[80px]" placeholder="Additional notes..." />
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <button @click="showForm = false" class="btn-secondary">Cancel</button>
          <button @click="save" :disabled="!form.name.trim()" class="btn-primary">{{ editing ? 'Update' : 'Add' }}</button>
        </div>
      </div>
    </div>
  </div>
</template>
