<script setup lang="ts">
definePageMeta({ layout: 'admin', title: 'Service Requests' })

const supabase = useSupabase()
const { user, ready, isAdmin } = useAuth()
const { success, error: toastError } = useToast()

interface ServiceRequest {
  id: string
  requester_id: string
  category: string
  priority: string
  subject: string
  description: string
  status: string
  assigned_to: string | null
  sla_hours: number
  created_at: string
  resolved_at: string | null
  requester_name?: string
}

const requests = ref<ServiceRequest[]>([])
const admins = ref<{ id: string; name: string }[]>([])
const loading = ref(true)
const statusFilter = ref('all')
const categoryFilter = ref('all')
const editingId = ref<string | null>(null)
const editStatus = ref('')
const editAssignee = ref('')

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('service_requests')
    .select('*')
    .order('created_at', { ascending: false })

  if (data) {
    requests.value = data as ServiceRequest[]
    await loadNames()
  }

  const { data: adminData } = await supabase
    .from('staff_members')
    .select('auth_user_id, full_name')
    .eq('is_active', true)
    .order('full_name')
  admins.value = (adminData ?? []).map((a: any) => ({ id: a.auth_user_id, name: a.full_name }))

  loading.value = false
}

async function loadNames() {
  const ids = [...new Set(requests.value.map(r => r.requester_id))]
  if (ids.length === 0) return
  const { data: staff } = await supabase.from('staff_members').select('auth_user_id, full_name').in('auth_user_id', ids)
  const nameMap = new Map<string, string>()
  if (staff) staff.forEach((s: any) => nameMap.set(s.auth_user_id, s.full_name))
  requests.value = requests.value.map(r => ({ ...r, requester_name: nameMap.get(r.requester_id) ?? 'Unknown' }))
}

const filtered = computed(() => {
  let list = requests.value
  if (statusFilter.value !== 'all') list = list.filter(r => r.status === statusFilter.value)
  if (categoryFilter.value !== 'all') list = list.filter(r => r.category === categoryFilter.value)
  return list
})

const stats = computed(() => ({
  total: requests.value.length,
  open: requests.value.filter(r => r.status === 'open').length,
  in_progress: requests.value.filter(r => r.status === 'in_progress').length,
  breached: requests.value.filter(r => {
    if (r.status === 'resolved' || r.status === 'closed') return false
    return (Date.now() - new Date(r.created_at).getTime()) / 3600000 > r.sla_hours
  }).length
}))

function startEdit(req: ServiceRequest) {
  editingId.value = req.id
  editStatus.value = req.status
  editAssignee.value = req.assigned_to ?? ''
}

async function saveEdit(id: string) {
  const update: any = { status: editStatus.value }
  if (editAssignee.value) update.assigned_to = editAssignee.value
  if (editStatus.value === 'resolved') update.resolved_at = new Date().toISOString()
  const { error } = await supabase.from('service_requests').update(update).eq('id', id)
  if (error) toastError('Failed to update')
  else { success('Request updated'); editingId.value = null; await load() }
}

function slaStatus(req: ServiceRequest) {
  if (req.status === 'resolved' || req.status === 'closed') return 'resolved'
  const elapsed = (Date.now() - new Date(req.created_at).getTime()) / 3600000
  if (elapsed > req.sla_hours) return 'breached'
  if (elapsed > req.sla_hours * 0.75) return 'warning'
  return 'ok'
}

function slaClass(status: string) {
  switch (status) { case 'breached': return 'text-red-600 font-medium'; case 'warning': return 'text-amber-600'; default: return 'text-slate-500' }
}

function statusBadge(status: string) {
  switch (status) { case 'open': return 'badge-blue'; case 'in_progress': return 'badge-amber'; case 'resolved': return 'badge-green'; default: return 'badge-slate' }
}

function priorityBadge(p: string) {
  switch (p) { case 'urgent': return 'bg-red-100 text-red-700 border-red-200'; case 'high': return 'bg-orange-100 text-orange-700 border-orange-200'; case 'medium': return 'badge-amber'; default: return 'badge-slate' }
}

watch(ready, (r) => { if (r && isAdmin.value) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-6xl mx-auto px-4 py-8">
    <div class="mb-6">
      <h1 class="section-title">Service Requests</h1>
      <p class="section-subtitle">Manage and assign incoming service requests</p>
    </div>

    <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-slate-900">{{ stats.total }}</div>
        <div class="text-xs text-slate-500 mt-1">Total</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-blue-600">{{ stats.open }}</div>
        <div class="text-xs text-slate-500 mt-1">Open</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-amber-600">{{ stats.in_progress }}</div>
        <div class="text-xs text-slate-500 mt-1">In Progress</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-red-600">{{ stats.breached }}</div>
        <div class="text-xs text-slate-500 mt-1">SLA Breached</div>
      </div>
    </div>

    <div class="flex flex-wrap gap-2 mb-4">
      <select v-model="statusFilter" class="input w-auto">
        <option value="all">All Statuses</option>
        <option value="open">Open</option>
        <option value="in_progress">In Progress</option>
        <option value="waiting">Waiting</option>
        <option value="resolved">Resolved</option>
        <option value="closed">Closed</option>
      </select>
      <select v-model="categoryFilter" class="input w-auto">
        <option value="all">All Categories</option>
        <option value="it">IT</option>
        <option value="facilities">Facilities</option>
        <option value="hr">HR</option>
        <option value="finance">Finance</option>
        <option value="other">Other</option>
      </select>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-400">No requests found.</div>
    <div v-else class="space-y-3">
      <div v-for="req in filtered" :key="req.id" class="card p-4">
        <div class="flex items-start justify-between gap-3">
          <div class="flex-1">
            <div class="flex items-center gap-2 mb-1 flex-wrap">
              <h3 class="font-semibold text-slate-900">{{ req.subject }}</h3>
              <span class="badge border" :class="statusBadge(req.status)">{{ req.status.replace('_', ' ') }}</span>
              <span class="badge border" :class="priorityBadge(req.priority)">{{ req.priority }}</span>
              <span class="badge badge-slate capitalize">{{ req.category }}</span>
            </div>
            <p v-if="req.description" class="text-sm text-slate-600 line-clamp-2 mb-1">{{ req.description }}</p>
            <div class="flex items-center gap-3 text-xs text-slate-500">
              <span>From: {{ req.requester_name }}</span>
              <span>{{ new Date(req.created_at).toLocaleDateString() }}</span>
              <span :class="slaClass(slaStatus(req))">
                SLA: {{ req.sla_hours }}h
                <template v-if="slaStatus(req) === 'breached'"> BREACHED</template>
              </span>
            </div>

            <!-- Edit panel -->
            <div v-if="editingId === req.id" class="mt-3 p-3 bg-slate-50 rounded-lg flex flex-wrap gap-3 items-end">
              <div>
                <label class="block text-xs text-slate-500 mb-1">Status</label>
                <select v-model="editStatus" class="input w-auto text-xs">
                  <option value="open">Open</option>
                  <option value="in_progress">In Progress</option>
                  <option value="waiting">Waiting</option>
                  <option value="resolved">Resolved</option>
                  <option value="closed">Closed</option>
                </select>
              </div>
              <div>
                <label class="block text-xs text-slate-500 mb-1">Assign to</label>
                <select v-model="editAssignee" class="input w-auto text-xs">
                  <option value="">Unassigned</option>
                  <option v-for="a in admins" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
              </div>
              <button @click="saveEdit(req.id)" class="btn-primary text-xs">Save</button>
              <button @click="editingId = null" class="btn-secondary text-xs">Cancel</button>
            </div>
          </div>
          <button v-if="editingId !== req.id" @click="startEdit(req)" class="btn-secondary text-xs">Manage</button>
        </div>
      </div>
    </div>
  </div>
</template>
