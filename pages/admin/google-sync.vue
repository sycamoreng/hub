<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

interface GoogleUserSlim { id: string; email: string; name: string; suspended: boolean; orgUnitPath: string; department: string }
interface RunRow { id: string; started_at: string; finished_at: string | null; mode: string; triggered_by: string; added: number; updated: number; skipped: number; excluded: number; deactivated: number; reactivated: number; errors: any[]; diff: any[] }
interface SettingsRow { id: string; domain: string; default_action: 'include'|'exclude'; auto_sync_enabled: boolean; department_source: 'organizations'|'orgUnitPath'; last_synced_at: string|null; last_sync_status: string|null; last_sync_error: string|null }
interface RuleRow { email: string; action: 'include'|'exclude'; note: string }
interface DeptMapRow { google_value: string; department_id: string | null }

const supabase = useSupabase()
const toast = useToast()
const { isSuperAdmin } = useAuth()

const activeTab = ref<'overview'|'users'|'departments'|'settings'>('overview')

const settings = ref<SettingsRow | null>(null)
const runs = ref<RunRow[]>([])
const googleUsers = ref<GoogleUserSlim[]>([])
const rules = ref<Map<string, RuleRow>>(new Map())
const deptMap = ref<DeptMapRow[]>([])
const departments = ref<{ id: string; name: string }[]>([])
const loadingUsers = ref(false)
const loadingStatus = ref(true)
const running = ref(false)
const lastDiff = ref<any[]>([])
const userFilter = ref<'all'|'included'|'excluded'|'new'|'suspended'>('all')
const userSearch = ref('')
const userPage = ref(1)
const userPageSize = 25
const runsPage = ref(1)
const runsPageSize = 10

async function callFn(action: string, method: 'GET'|'POST' = 'POST') {
  const { data: session } = await supabase.auth.getSession()
  const url = new URL(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/google-sync`)
  url.searchParams.set('action', action)
  const res = await fetch(url.toString(), {
    method,
    headers: {
      Authorization: `Bearer ${session.session?.access_token ?? ''}`,
      'Content-Type': 'application/json'
    }
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(body.error || `Request failed (${res.status})`)
  return body
}

async function loadStatus() {
  loadingStatus.value = true
  try {
    const res = await callFn('status', 'GET')
    settings.value = res.settings
    runs.value = res.runs ?? []
  } catch (e: any) {
    toast.error(e.message)
  } finally {
    loadingStatus.value = false
  }
}

async function loadRules() {
  const { data } = await supabase.from('google_sync_rules').select('*')
  const m = new Map<string, RuleRow>()
  for (const r of data ?? []) m.set((r.email as string).toLowerCase(), r as RuleRow)
  rules.value = m
}

async function loadDeptMap() {
  const [{ data: map }, { data: deps }] = await Promise.all([
    supabase.from('google_department_map').select('*'),
    supabase.from('departments').select('id, name').order('name')
  ])
  deptMap.value = (map ?? []) as DeptMapRow[]
  departments.value = deps ?? []
}

async function loadUsers() {
  loadingUsers.value = true
  try {
    const res = await callFn('fetch_users', 'POST')
    googleUsers.value = res.users ?? []
  } catch (e: any) {
    toast.error(e.message)
  } finally {
    loadingUsers.value = false
  }
}

async function setRule(email: string, action: 'include'|'exclude') {
  const em = email.toLowerCase()
  try {
    const { error } = await supabase
      .from('google_sync_rules')
      .upsert({ email: em, action }, { onConflict: 'email' })
    if (error) throw error
    rules.value = new Map(rules.value.set(em, { email: em, action, note: rules.value.get(em)?.note ?? '' }))
  } catch (e: any) {
    toast.error(e.message)
  }
}

async function clearRule(email: string) {
  const em = email.toLowerCase()
  try {
    const { error } = await supabase.from('google_sync_rules').delete().eq('email', em)
    if (error) throw error
    const next = new Map(rules.value); next.delete(em); rules.value = next
  } catch (e: any) {
    toast.error(e.message)
  }
}

function effectiveAction(email: string): 'include'|'exclude' {
  const r = rules.value.get(email.toLowerCase())
  if (r) return r.action
  return settings.value?.default_action === 'exclude' ? 'exclude' : 'include'
}

const existingEmails = ref<Set<string>>(new Set())
async function loadExistingStaffEmails() {
  const { data } = await supabase.from('staff_members').select('email')
  existingEmails.value = new Set((data ?? []).map((r: any) => (r.email ?? '').toLowerCase()))
}

const filteredUsers = computed(() => {
  const q = userSearch.value.trim().toLowerCase()
  return googleUsers.value.filter(u => {
    if (q && !(u.email.toLowerCase().includes(q) || u.name.toLowerCase().includes(q))) return false
    const eff = effectiveAction(u.email)
    if (userFilter.value === 'included' && eff !== 'include') return false
    if (userFilter.value === 'excluded' && eff !== 'exclude') return false
    if (userFilter.value === 'new' && existingEmails.value.has(u.email.toLowerCase())) return false
    if (userFilter.value === 'suspended' && !u.suspended) return false
    return true
  })
})

const userTotalPages = computed(() => Math.max(1, Math.ceil(filteredUsers.value.length / userPageSize)))
const pagedUsers = computed(() => {
  const start = (userPage.value - 1) * userPageSize
  return filteredUsers.value.slice(start, start + userPageSize)
})
const userRangeLabel = computed(() => {
  const total = filteredUsers.value.length
  if (!total) return '0 users'
  const start = (userPage.value - 1) * userPageSize + 1
  const end = Math.min(total, userPage.value * userPageSize)
  return `${start}-${end} of ${total} users`
})
watch([filteredUsers], () => { if (userPage.value > userTotalPages.value) userPage.value = userTotalPages.value })
watch([userFilter, userSearch], () => { userPage.value = 1 })

const pagedRuns = computed(() => {
  const start = (runsPage.value - 1) * runsPageSize
  return runs.value.slice(start, start + runsPageSize)
})
const runsTotalPages = computed(() => Math.max(1, Math.ceil(runs.value.length / runsPageSize)))

const uniqueDeptValues = computed(() => {
  const source = settings.value?.department_source === 'orgUnitPath' ? 'orgUnitPath' : 'department'
  const set = new Set<string>()
  for (const u of googleUsers.value) {
    const v = (source === 'orgUnitPath' ? u.orgUnitPath : u.department) ?? ''
    if (v) set.add(v)
  }
  return Array.from(set).sort((a, b) => a.localeCompare(b))
})

function deptMapValue(google_value: string): string | null {
  return deptMap.value.find(d => d.google_value.toLowerCase() === google_value.toLowerCase())?.department_id ?? null
}

async function setDeptMap(google_value: string, department_id: string | null) {
  try {
    if (!department_id) {
      await supabase.from('google_department_map').delete().eq('google_value', google_value)
    } else {
      await supabase.from('google_department_map').upsert({ google_value, department_id }, { onConflict: 'google_value' })
    }
    await loadDeptMap()
  } catch (e: any) {
    toast.error(e.message)
  }
}

async function saveSettings(patch: Partial<SettingsRow>) {
  if (!isSuperAdmin.value) { toast.error('Only super admins can change these settings'); return }
  try {
    const { error } = await supabase.from('google_sync_settings').update(patch).eq('id', 'default')
    if (error) throw error
    settings.value = { ...(settings.value as SettingsRow), ...patch }
    toast.success('Settings saved')
  } catch (e: any) {
    toast.error(e.message)
  }
}

async function runDryRun() {
  running.value = true
  try {
    const res = await callFn('dry_run', 'POST')
    lastDiff.value = res.diff ?? []
    toast.success(`Dry run: +${res.counters.added} new, ${res.counters.updated} updated, ${res.counters.skipped} unchanged, ${res.counters.excluded} excluded`)
    await loadStatus()
  } catch (e: any) {
    toast.error(e.message)
  } finally {
    running.value = false
  }
}

async function runApply() {
  if (!isSuperAdmin.value) { toast.error('Only super admins can apply a sync'); return }
  const ok = await toast.confirm({
    title: 'Run Google Workspace sync?',
    message: 'This will add, update, and activate/deactivate staff records based on Google Workspace. Admin-edited fields are preserved.',
    variant: 'danger',
    confirmLabel: 'Sync now'
  })
  if (!ok) return
  running.value = true
  try {
    const res = await callFn('apply', 'POST')
    toast.success(`Sync complete: +${res.counters.added}, ~${res.counters.updated}, off${res.counters.deactivated}, on${res.counters.reactivated}`)
    await loadStatus()
  } catch (e: any) {
    toast.error(e.message)
  } finally {
    running.value = false
  }
}

function fmtTime(iso: string | null) {
  if (!iso) return '-'
  return new Date(iso).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
}

onMounted(async () => {
  if (!isSuperAdmin.value) return
  await Promise.all([loadStatus(), loadRules(), loadDeptMap(), loadExistingStaffEmails()])
  await loadUsers()
})
</script>

<template>
  <div v-if="!isSuperAdmin" class="card p-8 text-center">
    <h1 class="section-title">Restricted</h1>
    <p class="section-subtitle">Only super admins can access Google Workspace sync.</p>
  </div>
  <div v-else class="space-y-6">
    <header class="flex items-start justify-between gap-4 flex-wrap">
      <div>
        <h1 class="section-title">Google Workspace sync</h1>
        <p class="section-subtitle">Keep staff records aligned with Google Workspace. Admin edits are preserved.</p>
      </div>
      <div class="flex gap-2">
        <button class="btn-secondary" :disabled="running" @click="runDryRun">
          {{ running ? 'Running...' : 'Dry run' }}
        </button>
        <button v-if="isSuperAdmin" class="btn-primary" :disabled="running" @click="runApply">
          {{ running ? 'Syncing...' : 'Sync now' }}
        </button>
      </div>
    </header>

    <div class="flex gap-1 border-b border-slate-200 text-sm font-medium">
      <button
        v-for="t in (['overview','users','departments','settings'] as const)"
        :key="t"
        class="px-3 py-2 -mb-px border-b-2 transition-colors capitalize"
        :class="activeTab === t ? 'border-sycamore-600 text-sycamore-700' : 'border-transparent text-slate-500 hover:text-slate-900'"
        @click="activeTab = t"
      >
        {{ t === 'overview' ? 'Overview' : t === 'users' ? 'Users' : t === 'departments' ? 'Department mapping' : 'Settings' }}
      </button>
    </div>

    <section v-if="activeTab === 'overview'" class="space-y-4">
      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div class="card p-4">
          <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">Last sync</div>
          <div class="text-lg font-semibold text-slate-900 mt-1">{{ fmtTime(settings?.last_synced_at ?? null) }}</div>
          <div class="text-xs text-slate-500 mt-1">Status: {{ settings?.last_sync_status || 'never' }}</div>
        </div>
        <div class="card p-4">
          <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">Google users</div>
          <div class="text-lg font-semibold text-slate-900 mt-1">{{ googleUsers.length }}</div>
          <div class="text-xs text-slate-500 mt-1">fetched from Workspace</div>
        </div>
        <div class="card p-4">
          <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">Auto sync</div>
          <div class="text-lg font-semibold text-slate-900 mt-1">{{ settings?.auto_sync_enabled ? 'Enabled' : 'Disabled' }}</div>
          <div class="text-xs text-slate-500 mt-1">Daily at 03:00 UTC</div>
        </div>
        <div class="card p-4">
          <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">Default action</div>
          <div class="text-lg font-semibold text-slate-900 mt-1 capitalize">{{ settings?.default_action || 'include' }}</div>
          <div class="text-xs text-slate-500 mt-1">for users without a rule</div>
        </div>
      </div>

      <div v-if="settings?.last_sync_error" class="card p-4 border border-rose-200 bg-rose-50 text-sm text-rose-700">
        Last sync error: {{ settings.last_sync_error }}
      </div>

      <div class="card p-4">
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-sm font-semibold text-slate-900">Recent runs</h2>
          <div class="text-xs text-slate-500">{{ runs.length }} total</div>
        </div>
        <div v-if="loadingStatus" class="text-xs text-slate-400">Loading...</div>
        <table v-else-if="runs.length" class="w-full text-sm">
          <thead>
            <tr class="text-[11px] uppercase text-slate-400 tracking-wide text-left">
              <th class="py-2 pr-2 font-semibold">When</th>
              <th class="py-2 pr-2 font-semibold">Mode</th>
              <th class="py-2 pr-2 font-semibold">By</th>
              <th class="py-2 pr-2 font-semibold text-right">+New</th>
              <th class="py-2 pr-2 font-semibold text-right">~Upd</th>
              <th class="py-2 pr-2 font-semibold text-right">Skip</th>
              <th class="py-2 pr-2 font-semibold text-right">Excl</th>
              <th class="py-2 pr-2 font-semibold text-right">Off</th>
              <th class="py-2 font-semibold">Errors</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="r in pagedRuns" :key="r.id" class="border-t border-slate-100">
              <td class="py-2 pr-2 text-slate-600">{{ fmtTime(r.started_at) }}</td>
              <td class="py-2 pr-2"><span class="badge" :class="r.mode === 'apply' ? 'badge-green' : 'badge-slate'">{{ r.mode }}</span></td>
              <td class="py-2 pr-2 text-slate-600 truncate max-w-[14rem]">{{ r.triggered_by || '-' }}</td>
              <td class="py-2 pr-2 text-right">{{ r.added }}</td>
              <td class="py-2 pr-2 text-right">{{ r.updated }}</td>
              <td class="py-2 pr-2 text-right">{{ r.skipped }}</td>
              <td class="py-2 pr-2 text-right">{{ r.excluded }}</td>
              <td class="py-2 pr-2 text-right">{{ r.deactivated }}</td>
              <td class="py-2 text-rose-600">{{ (r.errors || []).length }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else class="text-sm text-slate-400">No runs yet. Use the Dry run button to preview changes.</p>
        <div v-if="runsTotalPages > 1" class="flex items-center justify-end gap-1 mt-3 pt-3 border-t border-slate-100">
          <button class="px-2 py-1 rounded border border-slate-200 text-xs disabled:opacity-40" :disabled="runsPage <= 1" @click="runsPage -= 1">Prev</button>
          <span class="px-2 text-xs text-slate-600">Page {{ runsPage }} of {{ runsTotalPages }}</span>
          <button class="px-2 py-1 rounded border border-slate-200 text-xs disabled:opacity-40" :disabled="runsPage >= runsTotalPages" @click="runsPage += 1">Next</button>
        </div>
      </div>

      <div v-if="lastDiff.length" class="card p-4">
        <h2 class="text-sm font-semibold text-slate-900 mb-3">Last dry-run changes</h2>
        <ul class="text-sm divide-y divide-slate-100 max-h-80 overflow-y-auto">
          <li v-for="(d, i) in lastDiff.slice(0, 200)" :key="i" class="py-2">
            <div class="flex items-center gap-2">
              <span class="badge" :class="d.action === 'add' ? 'badge-green' : d.action === 'update' ? 'badge-amber' : d.action === 'exclude' ? 'badge-slate' : 'badge-slate'">{{ d.action }}</span>
              <span class="text-slate-700">{{ d.email }}</span>
            </div>
            <div v-if="d.changes" class="text-xs text-slate-500 mt-1 pl-1">
              <span v-for="(ch, k) in d.changes" :key="k" class="block">
                <strong class="font-mono">{{ k }}</strong>: {{ ch.from ?? '-' }} → {{ ch.to ?? '-' }}
              </span>
            </div>
          </li>
        </ul>
      </div>
    </section>

    <section v-if="activeTab === 'users'" class="space-y-4">
      <div class="card p-4 space-y-3">
        <div class="flex flex-wrap items-center gap-2">
          <input v-model="userSearch" class="input flex-1 min-w-[220px]" placeholder="Search by name or email" />
          <select v-model="userFilter" class="input !w-auto">
            <option value="all">All users</option>
            <option value="included">Included</option>
            <option value="excluded">Excluded</option>
            <option value="new">Not yet imported</option>
            <option value="suspended">Suspended in Google</option>
          </select>
          <button class="btn-secondary" :disabled="loadingUsers" @click="loadUsers">
            {{ loadingUsers ? 'Loading...' : 'Refresh' }}
          </button>
        </div>
        <p class="text-xs text-slate-500">
          Default action for users without a rule: <strong class="capitalize">{{ settings?.default_action || 'include' }}</strong>.
          Change per-user with the buttons below.
        </p>
      </div>

      <div class="card overflow-hidden">
        <div class="flex items-center justify-between gap-3 px-4 py-3 border-b border-slate-100 bg-slate-50/60">
          <h2 class="text-sm font-semibold text-slate-900">Google Workspace users</h2>
          <div class="text-xs text-slate-500">{{ userRangeLabel }}</div>
        </div>
        <table class="w-full text-sm">
          <thead class="bg-slate-50">
            <tr class="text-[11px] uppercase text-slate-500 tracking-wide text-left border-b border-slate-200">
              <th class="py-2 px-3 font-semibold">Email</th>
              <th class="py-2 px-3 font-semibold">Name</th>
              <th class="py-2 px-3 font-semibold">Department</th>
              <th class="py-2 px-3 font-semibold">Status</th>
              <th class="py-2 px-3 font-semibold">Rule</th>
              <th class="py-2 px-3 font-semibold text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="loadingUsers"><td colspan="6" class="py-6 px-3 text-center text-slate-400">Loading users...</td></tr>
            <tr v-else-if="!filteredUsers.length"><td colspan="6" class="py-6 px-3 text-center text-slate-400">No users match.</td></tr>
            <tr v-else v-for="u in pagedUsers" :key="u.id" class="border-t border-slate-100">
              <td class="py-2 px-3 text-slate-700">
                {{ u.email }}
                <span v-if="!existingEmails.has(u.email.toLowerCase())" class="ml-1 badge badge-green">new</span>
              </td>
              <td class="py-2 px-3 text-slate-600">{{ u.name }}</td>
              <td class="py-2 px-3 text-slate-500 text-xs">{{ settings?.department_source === 'orgUnitPath' ? u.orgUnitPath : u.department }}</td>
              <td class="py-2 px-3">
                <span v-if="u.suspended" class="badge badge-rose">suspended</span>
                <span v-else class="badge badge-slate">active</span>
              </td>
              <td class="py-2 px-3">
                <span class="badge" :class="effectiveAction(u.email) === 'include' ? 'badge-green' : 'badge-slate'">
                  {{ effectiveAction(u.email) }}
                </span>
                <span v-if="rules.get(u.email.toLowerCase())" class="text-[10px] text-slate-400 ml-1">override</span>
              </td>
              <td class="py-2 px-3 text-right">
                <div class="inline-flex gap-1">
                  <button class="text-xs px-2 py-1 rounded border border-slate-200 hover:bg-slate-50" @click="setRule(u.email, 'include')">Include</button>
                  <button class="text-xs px-2 py-1 rounded border border-slate-200 hover:bg-slate-50" @click="setRule(u.email, 'exclude')">Exclude</button>
                  <button v-if="rules.get(u.email.toLowerCase())" class="text-xs px-2 py-1 rounded text-slate-400 hover:text-rose-600" @click="clearRule(u.email)">clear</button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <div v-if="userTotalPages > 1" class="flex items-center justify-between gap-3 px-4 py-3 border-t border-slate-100 bg-slate-50/60">
          <div class="text-xs text-slate-500">{{ userRangeLabel }}</div>
          <div class="flex items-center gap-1">
            <button class="px-2 py-1 rounded border border-slate-200 text-xs disabled:opacity-40" :disabled="userPage <= 1" @click="userPage = 1">First</button>
            <button class="px-2 py-1 rounded border border-slate-200 text-xs disabled:opacity-40" :disabled="userPage <= 1" @click="userPage -= 1">Prev</button>
            <span class="px-2 text-xs text-slate-600">Page {{ userPage }} of {{ userTotalPages }}</span>
            <button class="px-2 py-1 rounded border border-slate-200 text-xs disabled:opacity-40" :disabled="userPage >= userTotalPages" @click="userPage += 1">Next</button>
            <button class="px-2 py-1 rounded border border-slate-200 text-xs disabled:opacity-40" :disabled="userPage >= userTotalPages" @click="userPage = userTotalPages">Last</button>
          </div>
        </div>
      </div>
    </section>

    <section v-if="activeTab === 'departments'" class="space-y-4">
      <div class="card p-4">
        <h2 class="text-sm font-semibold text-slate-900 mb-1">Department mapping</h2>
        <p class="text-xs text-slate-500 mb-3">
          Map Google Workspace {{ settings?.department_source === 'orgUnitPath' ? 'org unit paths' : 'department values' }}
          to departments in the Hub. Unmapped values are simply left blank on the staff record.
        </p>
        <div v-if="!uniqueDeptValues.length" class="text-sm text-slate-400">No department values found. Fetch users on the Users tab first.</div>
        <table v-else class="w-full text-sm">
          <thead>
            <tr class="text-[11px] uppercase text-slate-400 tracking-wide text-left">
              <th class="py-2 pr-2 font-semibold">Google value</th>
              <th class="py-2 font-semibold">Hub department</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="v in uniqueDeptValues" :key="v" class="border-t border-slate-100">
              <td class="py-2 pr-2 font-mono text-xs text-slate-700">{{ v }}</td>
              <td class="py-2">
                <select
                  class="input !w-auto"
                  :value="deptMapValue(v) || ''"
                  @change="setDeptMap(v, ($event.target as HTMLSelectElement).value || null)"
                >
                  <option value="">— unmapped —</option>
                  <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
                </select>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section v-if="activeTab === 'settings'" class="space-y-4">
      <div class="card p-4 space-y-4">
        <div v-if="!isSuperAdmin" class="text-xs text-slate-500">Only super admins can change these settings.</div>
        <div>
          <label class="block text-[11px] uppercase tracking-wide text-slate-400 font-semibold mb-1">Workspace domain</label>
          <div class="text-sm text-slate-700">{{ settings?.domain || '(configured via GOOGLE_WORKSPACE_DOMAIN secret)' }}</div>
        </div>
        <div>
          <label class="block text-[11px] uppercase tracking-wide text-slate-400 font-semibold mb-1">Default action for new users</label>
          <select :value="settings?.default_action || 'include'" :disabled="!isSuperAdmin" class="input !w-auto" @change="saveSettings({ default_action: ($event.target as HTMLSelectElement).value as any })">
            <option value="include">Include (sync everyone unless excluded)</option>
            <option value="exclude">Exclude (only sync users explicitly included)</option>
          </select>
        </div>
        <div>
          <label class="block text-[11px] uppercase tracking-wide text-slate-400 font-semibold mb-1">Department source</label>
          <select :value="settings?.department_source || 'organizations'" :disabled="!isSuperAdmin" class="input !w-auto" @change="saveSettings({ department_source: ($event.target as HTMLSelectElement).value as any })">
            <option value="organizations">Organization department field</option>
            <option value="orgUnitPath">Org unit path</option>
          </select>
        </div>
        <div>
          <label class="inline-flex items-center gap-2 text-sm text-slate-700">
            <input type="checkbox" :checked="!!settings?.auto_sync_enabled" :disabled="!isSuperAdmin" @change="saveSettings({ auto_sync_enabled: ($event.target as HTMLInputElement).checked })" />
            Run sync automatically once a day
          </label>
        </div>
      </div>
    </section>
  </div>
</template>
