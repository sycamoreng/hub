<script setup lang="ts">
import type { UserProfile } from '~/composables/useProfile'
import { useSupabase } from '~/utils/supabase'

const { fetchStaff, fetchDepartments } = useCompanyData()
const { fetchProfilesByUserIds } = useProfile()
const { user, profileSyncTick } = useAuth()
const supabase = useSupabase()

const staff = ref<any[]>([])
const exited = ref<any[]>([])
const departments = ref<any[]>([])
const profilesByUid = ref<Record<string, UserProfile>>({})
const search = ref('')
const selectedDept = ref('All')
const loading = ref(true)
const view = ref<'active' | 'exited'>('active')

async function load() {
  loading.value = true
  try {
    const [s, d, ex] = await Promise.all([
      fetchStaff(),
      fetchDepartments(),
      supabase.from('staff_directory_exited').select('*').order('full_name')
    ])
    staff.value = s
    departments.value = d
    exited.value = (ex.data ?? []) as any[]
    const uids = [
      ...(s as any[]).map(r => r.auth_user_id).filter(Boolean),
      ...(exited.value as any[]).map(r => r.auth_user_id).filter(Boolean)
    ]
    profilesByUid.value = uids.length ? await fetchProfilesByUserIds(uids) : {}
  } finally { loading.value = false }
}

onMounted(load)
watch([() => user.value?.id, () => profileSyncTick.value], () => load())

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  return staff.value.filter(s => {
    const deptOk = selectedDept.value === 'All' || s.departments?.name === selectedDept.value
    if (!deptOk) return false
    if (!q) return true
    return s.full_name.toLowerCase().includes(q) || s.role.toLowerCase().includes(q) || s.email.toLowerCase().includes(q)
  })
})

const filteredExited = computed(() => {
  const q = search.value.trim().toLowerCase()
  return exited.value.filter(s => {
    const deptOk = selectedDept.value === 'All' || s.department_name === selectedDept.value
    if (!deptOk) return false
    if (!q) return true
    return (s.full_name || '').toLowerCase().includes(q)
      || (s.role || '').toLowerCase().includes(q)
      || (s.email || '').toLowerCase().includes(q)
  })
})

function fmtDate(iso: string | null | undefined) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
}

function initials(name: string) {
  return name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()
}

function avatar(s: any): string | null {
  if (!s.auth_user_id) return null
  return profilesByUid.value[s.auth_user_id]?.avatar_url || null
}
</script>

<template>
  <div class="max-w-7xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">Staff Directory</h1>
      <p class="section-subtitle">Meet the people who make Sycamore thrive.</p>
    </div>

    <div class="flex gap-1 bg-slate-100 rounded-lg p-1 mb-4 w-fit">
      <button type="button" @click="view = 'active'"
        class="text-xs font-semibold px-3 py-1.5 rounded-md"
        :class="view === 'active' ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
        Active <span class="ml-1 text-slate-400">{{ staff.length }}</span>
      </button>
      <button type="button" @click="view = 'exited'"
        class="text-xs font-semibold px-3 py-1.5 rounded-md"
        :class="view === 'exited' ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
        Exited <span class="ml-1 text-slate-400">{{ exited.length }}</span>
      </button>
    </div>

    <div class="card p-4 mb-6 flex flex-col sm:flex-row gap-3">
      <div class="relative flex-1">
        <input v-model="search" type="text" placeholder="Search by name, role, or email..." class="input pl-10" />
        <div class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"><SidebarIcon name="search" /></div>
      </div>
      <select v-model="selectedDept" class="input sm:w-56">
        <option value="All">All departments</option>
        <option v-for="d in departments" :key="d.id" :value="d.name">{{ d.name }}</option>
      </select>
    </div>

    <div v-if="loading" class="text-slate-400">Loading staff...</div>

    <template v-else-if="view === 'active'">
    <div v-if="filtered.length === 0" class="text-slate-400">No staff match your filters.</div>
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <NuxtLink v-for="s in filtered" :key="s.id" :to="`/profile/${s.id}`" class="card card-hover p-5 flex gap-4">
        <div class="relative flex-shrink-0">
          <img
            v-if="avatar(s)"
            :src="avatar(s)!"
            :alt="s.full_name"
            referrerpolicy="no-referrer"
            class="w-14 h-14 rounded-full object-cover border border-slate-200"
          />
          <div v-else class="w-14 h-14 rounded-full bg-gradient-to-br from-sycamore-400 to-sycamore-700 text-white flex items-center justify-center font-bold text-lg">
            {{ initials(s.full_name) }}
          </div>
          <span
            v-if="s.auth_user_id"
            title="Profile claimed"
            class="absolute -bottom-0.5 -right-0.5 w-4 h-4 rounded-full bg-emerald-500 ring-2 ring-white"
          />
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-1.5">
            <h3 class="font-semibold text-slate-900 truncate">{{ s.full_name }}</h3>
          </div>
          <div class="text-sm text-slate-600 truncate">{{ s.role }}</div>
          <div class="text-xs text-slate-500 mt-1">
            <span v-if="s.departments?.name" class="badge badge-green">{{ s.departments.name }}</span>
          </div>
          <div class="text-xs text-slate-500 mt-2 truncate">{{ s.email }}</div>
          <div v-if="s.locations" class="text-xs text-slate-400 mt-0.5">{{ s.locations.city }}</div>
        </div>
      </NuxtLink>
    </div>
    </template>

    <template v-else>
      <div v-if="filteredExited.length === 0" class="text-slate-400">No exited staff records.</div>
      <div v-else class="card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
            <tr>
              <th class="text-left px-5 py-2">Name</th>
              <th class="text-left px-5 py-2">Role</th>
              <th class="text-left px-5 py-2">Department</th>
              <th class="text-left px-5 py-2">Joined</th>
              <th class="text-left px-5 py-2">Exited</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="s in filteredExited" :key="s.id" class="border-t border-slate-100">
              <td class="px-5 py-3">
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-full bg-slate-200 text-slate-600 flex items-center justify-center text-xs font-semibold">
                    {{ s.full_name?.split(' ').map((p: string) => p[0]).slice(0,2).join('').toUpperCase() }}
                  </div>
                  <div>
                    <div class="font-semibold text-slate-900">{{ s.full_name }}</div>
                    <div class="text-xs text-slate-500">{{ s.email }}</div>
                  </div>
                </div>
              </td>
              <td class="px-5 py-3 text-slate-700">{{ s.role || '—' }}</td>
              <td class="px-5 py-3 text-slate-700">{{ s.department_name || '—' }}</td>
              <td class="px-5 py-3 text-slate-500">{{ fmtDate(s.joined_date) }}</td>
              <td class="px-5 py-3 text-slate-500">{{ fmtDate(s.exit_effective_date) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
