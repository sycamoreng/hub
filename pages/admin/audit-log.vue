<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const { isSuperAdmin } = useAuth()
const supabase = useSupabase()

const logs = ref<any[]>([])
const loading = ref(true)
const total = ref(0)
const page = ref(1)
const perPage = 50

const filterAdmin = ref('')
const filterAction = ref('')
const filterType = ref('')

const admins = ref<string[]>([])
const actionTypes = ref<string[]>([])
const targetTypes = ref<string[]>([])

async function loadFilters() {
  const [aRes, actRes, tRes] = await Promise.all([
    supabase.from('admin_audit_log').select('admin_email').limit(500),
    supabase.from('admin_audit_log').select('action').limit(500),
    supabase.from('admin_audit_log').select('target_type').limit(500),
  ])
  admins.value = [...new Set((aRes.data ?? []).map((r: any) => r.admin_email))].sort()
  actionTypes.value = [...new Set((actRes.data ?? []).map((r: any) => r.action))].sort()
  targetTypes.value = [...new Set((tRes.data ?? []).map((r: any) => r.target_type))].sort()
}

async function load() {
  loading.value = true
  let query = supabase
    .from('admin_audit_log')
    .select('*', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range((page.value - 1) * perPage, page.value * perPage - 1)

  if (filterAdmin.value) query = query.eq('admin_email', filterAdmin.value)
  if (filterAction.value) query = query.eq('action', filterAction.value)
  if (filterType.value) query = query.eq('target_type', filterType.value)

  const { data, count } = await query
  logs.value = data ?? []
  total.value = count ?? 0
  loading.value = false
}

onMounted(async () => {
  await Promise.all([load(), loadFilters()])
})

watch([filterAdmin, filterAction, filterType], () => {
  page.value = 1
  load()
})

function nextPage() {
  if (page.value * perPage < total.value) {
    page.value++
    load()
  }
}

function prevPage() {
  if (page.value > 1) {
    page.value--
    load()
  }
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  })
}

function actionColor(action: string) {
  if (action === 'delete') return 'bg-rose-50 text-rose-700'
  if (action === 'create') return 'bg-emerald-50 text-emerald-700'
  if (action === 'update') return 'bg-sky-50 text-sky-700'
  if (action === 'login') return 'bg-slate-100 text-slate-600'
  return 'bg-slate-50 text-slate-600'
}
</script>

<template>
  <div v-if="!isSuperAdmin" class="card p-8 text-center">
    <h1 class="section-title">Restricted</h1>
    <p class="section-subtitle">Only super admins can view the audit log.</p>
  </div>
  <div v-else class="max-w-6xl">
    <div class="mb-8">
      <h1 class="section-title">Audit log</h1>
      <p class="section-subtitle">Track all admin actions across the system.</p>
    </div>

    <!-- Filters -->
    <div class="card p-4 mb-5 flex flex-wrap gap-3 items-end">
      <div>
        <label class="text-xs font-semibold text-slate-600 uppercase tracking-wide block mb-1">Admin</label>
        <select v-model="filterAdmin" class="input text-sm min-w-[180px]">
          <option value="">All admins</option>
          <option v-for="a in admins" :key="a" :value="a">{{ a }}</option>
        </select>
      </div>
      <div>
        <label class="text-xs font-semibold text-slate-600 uppercase tracking-wide block mb-1">Action</label>
        <select v-model="filterAction" class="input text-sm min-w-[120px]">
          <option value="">All actions</option>
          <option v-for="a in actionTypes" :key="a" :value="a">{{ a }}</option>
        </select>
      </div>
      <div>
        <label class="text-xs font-semibold text-slate-600 uppercase tracking-wide block mb-1">Section</label>
        <select v-model="filterType" class="input text-sm min-w-[140px]">
          <option value="">All sections</option>
          <option v-for="t in targetTypes" :key="t" :value="t">{{ t }}</option>
        </select>
      </div>
      <div class="text-xs text-slate-500 self-center ml-auto">{{ total }} entries</div>
    </div>

    <!-- Table -->
    <div class="card overflow-hidden">
      <div v-if="loading" class="p-10 text-center text-slate-500">Loading audit log...</div>
      <div v-else-if="logs.length === 0" class="p-10 text-center text-slate-500">No audit entries found.</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
          <tr>
            <th class="text-left p-4">Time</th>
            <th class="text-left p-4">Admin</th>
            <th class="text-left p-4">Action</th>
            <th class="text-left p-4">Section</th>
            <th class="text-left p-4">Target</th>
            <th class="text-left p-4">Details</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="entry in logs" :key="entry.id" class="border-t border-slate-100 align-top">
            <td class="p-4 text-xs text-slate-500 whitespace-nowrap">{{ formatDate(entry.created_at) }}</td>
            <td class="p-4 text-slate-700">{{ entry.admin_email.split('@')[0] }}</td>
            <td class="p-4">
              <span class="inline-flex px-2 py-0.5 rounded-full text-xs font-medium" :class="actionColor(entry.action)">
                {{ entry.action }}
              </span>
            </td>
            <td class="p-4 text-slate-600">{{ entry.target_type }}</td>
            <td class="p-4 text-slate-700 max-w-[200px] truncate">{{ entry.target_label || entry.target_id || '-' }}</td>
            <td class="p-4 text-xs text-slate-500 max-w-[200px] truncate">
              {{ entry.details ? JSON.stringify(entry.details).slice(0, 100) : '-' }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Pagination -->
    <div v-if="total > perPage" class="flex items-center justify-between mt-4">
      <button type="button" :disabled="page <= 1" @click="prevPage" class="btn-secondary text-sm">Previous</button>
      <span class="text-sm text-slate-500">Page {{ page }} of {{ Math.ceil(total / perPage) }}</span>
      <button type="button" :disabled="page * perPage >= total" @click="nextPage" class="btn-secondary text-sm">Next</button>
    </div>
  </div>
</template>
