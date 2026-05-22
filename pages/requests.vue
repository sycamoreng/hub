<script setup lang="ts">
definePageMeta({ title: 'Service Requests' })

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
}

const requests = ref<ServiceRequest[]>([])
const loading = ref(true)
const tab = ref<'my' | 'all'>('my')
const statusFilter = ref('all')
const showNew = ref(false)
const form = ref({ category: 'it', priority: 'medium', subject: '', description: '' })
const submitting = ref(false)

async function load() {
  loading.value = true
  let query = supabase.from('service_requests').select('*').order('created_at', { ascending: false })
  if (tab.value === 'my' && user.value) {
    query = query.eq('requester_id', user.value.id)
  }
  const { data } = await query
  requests.value = (data ?? []) as ServiceRequest[]
  loading.value = false
}

const filtered = computed(() => {
  if (statusFilter.value === 'all') return requests.value
  return requests.value.filter(r => r.status === statusFilter.value)
})

const stats = computed(() => ({
  open: requests.value.filter(r => r.status === 'open').length,
  in_progress: requests.value.filter(r => r.status === 'in_progress').length,
  resolved: requests.value.filter(r => r.status === 'resolved' || r.status === 'closed').length,
  breached: requests.value.filter(r => {
    if (r.status === 'resolved' || r.status === 'closed') return false
    const elapsed = (Date.now() - new Date(r.created_at).getTime()) / 3600000
    return elapsed > r.sla_hours
  }).length
}))

async function submit() {
  if (!form.value.subject.trim() || !user.value) return
  submitting.value = true
  const slaMap: Record<string, number> = { low: 72, medium: 48, high: 24, urgent: 4 }
  const { error } = await supabase.from('service_requests').insert({
    requester_id: user.value.id,
    category: form.value.category,
    priority: form.value.priority,
    subject: form.value.subject.trim(),
    description: form.value.description.trim(),
    sla_hours: slaMap[form.value.priority] ?? 48
  })
  if (error) toastError('Failed to create request')
  else {
    success('Request submitted!')
    form.value = { category: 'it', priority: 'medium', subject: '', description: '' }
    showNew.value = false
    await load()
  }
  submitting.value = false
}

function slaStatus(req: ServiceRequest) {
  if (req.status === 'resolved' || req.status === 'closed') return 'resolved'
  const elapsed = (Date.now() - new Date(req.created_at).getTime()) / 3600000
  if (elapsed > req.sla_hours) return 'breached'
  if (elapsed > req.sla_hours * 0.75) return 'warning'
  return 'ok'
}

function slaClass(status: string) {
  switch (status) {
    case 'breached': return 'text-red-600'
    case 'warning': return 'text-amber-600'
    case 'resolved': return 'text-slate-400'
    default: return 'text-leaf-600'
  }
}

function statusBadge(status: string) {
  switch (status) {
    case 'open': return 'badge-blue'
    case 'in_progress': return 'badge-amber'
    case 'waiting': return 'badge-slate'
    case 'resolved': return 'badge-green'
    case 'closed': return 'badge-slate'
    default: return 'badge-slate'
  }
}

function priorityBadge(priority: string) {
  switch (priority) {
    case 'urgent': return 'bg-red-100 text-red-700 border-red-200'
    case 'high': return 'bg-orange-100 text-orange-700 border-orange-200'
    case 'medium': return 'bg-amber-50 text-amber-700 border-amber-200'
    default: return 'bg-slate-100 text-slate-600 border-slate-200'
  }
}

watch(ready, (r) => { if (r) load() }, { immediate: true })
watch(tab, () => load())
</script>

<template>
  <div class="max-w-5xl mx-auto px-4 py-8">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="section-title">Service Requests</h1>
        <p class="section-subtitle">Submit and track IT, facilities, HR, and finance requests</p>
      </div>
      <button @click="showNew = true" class="btn-primary">New Request</button>
    </div>

    <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-blue-600">{{ stats.open }}</div>
        <div class="text-xs text-slate-500 mt-1">Open</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-amber-600">{{ stats.in_progress }}</div>
        <div class="text-xs text-slate-500 mt-1">In Progress</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-leaf-600">{{ stats.resolved }}</div>
        <div class="text-xs text-slate-500 mt-1">Resolved</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-red-600">{{ stats.breached }}</div>
        <div class="text-xs text-slate-500 mt-1">SLA Breached</div>
      </div>
    </div>

    <div class="flex flex-wrap gap-2 mb-4">
      <button
        v-for="t in (['my', 'all'] as const)"
        :key="t"
        @click="tab = t"
        class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
        :class="tab === t ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'"
      >{{ t === 'my' ? 'My Requests' : 'All Requests' }}</button>
      <select v-model="statusFilter" class="input w-auto">
        <option value="all">All Statuses</option>
        <option value="open">Open</option>
        <option value="in_progress">In Progress</option>
        <option value="waiting">Waiting</option>
        <option value="resolved">Resolved</option>
        <option value="closed">Closed</option>
      </select>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-400">No requests found.</div>
    <div v-else class="space-y-3">
      <div v-for="req in filtered" :key="req.id" class="card p-4 card-hover">
        <div class="flex items-start justify-between gap-3">
          <div class="flex-1">
            <div class="flex items-center gap-2 mb-1">
              <h3 class="font-semibold text-slate-900">{{ req.subject }}</h3>
              <span class="badge border" :class="statusBadge(req.status)">{{ req.status.replace('_', ' ') }}</span>
              <span class="badge border" :class="priorityBadge(req.priority)">{{ req.priority }}</span>
            </div>
            <p v-if="req.description" class="text-sm text-slate-600 line-clamp-2 mb-2">{{ req.description }}</p>
            <div class="flex items-center gap-3 text-xs text-slate-500">
              <span class="capitalize">{{ req.category }}</span>
              <span>{{ new Date(req.created_at).toLocaleDateString() }}</span>
              <span :class="slaClass(slaStatus(req))">
                SLA: {{ req.sla_hours }}h
                <template v-if="slaStatus(req) === 'breached'"> (breached)</template>
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- New Request Modal -->
    <div v-if="showNew" class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" @click.self="showNew = false">
      <div class="bg-white rounded-xl shadow-xl w-full max-w-lg p-6">
        <h2 class="text-lg font-bold text-slate-900 mb-4">New Service Request</h2>
        <div class="space-y-3">
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Category</label>
              <select v-model="form.category" class="input">
                <option value="it">IT</option>
                <option value="facilities">Facilities</option>
                <option value="hr">HR</option>
                <option value="finance">Finance</option>
                <option value="other">Other</option>
              </select>
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Priority</label>
              <select v-model="form.priority" class="input">
                <option value="low">Low (72h SLA)</option>
                <option value="medium">Medium (48h SLA)</option>
                <option value="high">High (24h SLA)</option>
                <option value="urgent">Urgent (4h SLA)</option>
              </select>
            </div>
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Subject</label>
            <input v-model="form.subject" class="input" placeholder="Brief summary of the issue" maxlength="200">
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Description</label>
            <textarea v-model="form.description" class="input min-h-[100px]" placeholder="Detailed description..." maxlength="2000" />
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <button @click="showNew = false" class="btn-secondary">Cancel</button>
          <button @click="submit" :disabled="!form.subject.trim() || submitting" class="btn-primary">
            {{ submitting ? 'Submitting...' : 'Submit Request' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
